--[[
 * ReaScript Name: Create Regions From Selected Items
 * Description: Create one region per selected item with take or track names, a colour picker, and track or parent render routing.
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: ReaImGui
 * Version: 1.0
 * Changelog:
 *   + Initial release
--]]

local r = reaper
local title = 'Create Regions From Selected Items'

if not r.ImGui_CreateContext then
    r.ShowMessageBox('Please install ReaImGui through ReaPack, then run this script again.', title, 0)
    return
end

local ctx = r.ImGui_CreateContext(title)
local name_source = 0
local route = 0
local colour = 0x66BBAA

local function selected_items(project)
    local items = {}
    local problem
    for index = 0, r.CountMediaItems(project) - 1 do
        local item = r.GetMediaItem(project, index)
        if r.IsMediaItemSelected(item) then
            local track = r.GetMediaItemTrack(item)
            local _, track_name = r.GetTrackName(track)
            local name = track_name
            if name_source == 0 then
                local take = r.GetActiveTake(item)
                if take then
                    name = r.GetTakeName(take)
                else
                    name = '(no active take)'
                    problem = 'A selected item has no active take.'
                end
            end
            local destination = track
            local destination_name = track_name
            if route == 1 then
                destination = r.GetParentTrack(track) or r.GetMasterTrack(project)
                _, destination_name = r.GetTrackName(destination)
            end
            local position = r.GetMediaItemInfo_Value(item, 'D_POSITION')
            local length = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
            if length <= 0 then problem = 'A selected item has no positive duration.' end
            items[#items + 1] = {
                name = name, position = position, ending = position + length,
                destination = destination, destination_name = destination_name, index = index,
            }
        end
    end
    table.sort(items, function(first, second)
        if first.position == second.position then return first.index < second.index end
        return first.position < second.position
    end)
    return items, problem
end

local function create_regions(project, items)
    local native_colour = r.ColorToNative((colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF) | 0x1000000
    local created = 0
    r.Undo_BeginBlock2(project)
    local success, message = pcall(function()
        for _, item in ipairs(items) do
            local region = r.AddProjectMarker2(project, true, item.position, item.ending, item.name, -1, native_colour)
            if region < 0 then error('Could not create region for ' .. item.name) end
            created = created + 1
            r.SetRegionRenderMatrix(project, region, item.destination, 1)
        end
    end)
    r.Undo_EndBlock2(project, title, -1)
    r.UpdateTimeline()
    if not success then
        r.ShowMessageBox(string.format('Created %d region(s) before an error.\n%s\nUndo to revert this batch.', created, tostring(message)), title, 0)
    end
    return success
end

local function draw_preview(items)
    local flags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()
        | r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_ScrollY()
    if r.ImGui_BeginTable(ctx, 'Regions', 4, flags, 0, 240) then
        r.ImGui_TableSetupColumn(ctx, 'Region name')
        r.ImGui_TableSetupColumn(ctx, 'Start')
        r.ImGui_TableSetupColumn(ctx, 'End')
        r.ImGui_TableSetupColumn(ctx, 'Render track')
        r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
        r.ImGui_TableHeadersRow(ctx)
        for _, item in ipairs(items) do
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_TextWrapped(ctx, item.name == '' and '(empty)' or item.name)
            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_Text(ctx, r.format_timestr_pos(item.position, '', -1))
            r.ImGui_TableSetColumnIndex(ctx, 2)
            r.ImGui_Text(ctx, r.format_timestr_pos(item.ending, '', -1))
            r.ImGui_TableSetColumnIndex(ctx, 3)
            r.ImGui_TextWrapped(ctx, item.destination_name)
        end
        r.ImGui_EndTable(ctx)
    end
end

local function loop()
    r.ImGui_SetNextWindowSize(ctx, 700, 430, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, title, true)
    if visible then
        local changed
        changed, name_source = r.ImGui_Combo(ctx, 'Region name', name_source, 'Active take name\0Track name\0')
        changed, route = r.ImGui_Combo(ctx, 'Render routing', route, 'Item track\0Parent track (Master if none)\0')
        changed, colour = r.ImGui_ColorEdit3(ctx, 'Colour', colour, r.ImGui_ColorEditFlags_NoInputs())
        local project = r.EnumProjects(-1)
        local items, problem = selected_items(project)
        r.ImGui_Text(ctx, string.format('%d selected item(s)', #items))
        draw_preview(items)
        if problem then r.ImGui_TextWrapped(ctx, problem) end
        r.ImGui_BeginDisabled(ctx, #items == 0 or problem ~= nil)
        if r.ImGui_Button(ctx, 'Create regions') then
            if create_regions(project, items) then open = false end
        end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Cancel') then open = false end
        r.ImGui_End(ctx)
    end
    if open then r.defer(loop) end
end

r.defer(loop)