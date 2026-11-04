--[[
 * ReaScript Name: Rename Selected Regions
 * Description: Batch rename selected regions with a live preview, literal find/replace, prefix, suffix, and numbering.
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.x with native region selection APIs
 * Extensions: ReaImGui
 * Version: 1.0
 * Changelog:
 *   + Initial release
--]]

local r = reaper
local title = 'Rename Selected Regions'

if not r.GetRegionOrMarker or not r.GetRegionOrMarkerInfo_Value
    or not r.GetSetRegionOrMarkerInfo_String then
    r.ShowMessageBox('Please update REAPER. This script requires the native region selection APIs.', title, 0)
    return
end

if not r.ImGui_CreateContext then
    r.ShowMessageBox('Please install ReaImGui through ReaPack, then run this script again.', title, 0)
    return
end

local ctx = r.ImGui_CreateContext(title)

local function default_options()
    return {
        replace_name = false, name = '', find = '', replacement = '',
        prefix = '', suffix = '', numbering = false,
        start = 1, digits = 2, separator = '_',
    }
end

local options = default_options()
local status = ''

local function rename(name, index)
    if options.replace_name then name = options.name end
    if options.find ~= '' then
        local parts = {}
        local position = 1
        while true do
            local first, last = name:find(options.find, position, true)
            if not first then break end
            parts[#parts + 1] = name:sub(position, first - 1)
            parts[#parts + 1] = options.replacement
            position = last + 1
        end
        parts[#parts + 1] = name:sub(position)
        name = table.concat(parts)
    end
    name = options.prefix .. name
    if options.numbering then
        name = name .. options.separator .. string.format('%0' .. options.digits .. 'd', options.start + index - 1)
    end
    return name .. options.suffix
end

local function selected_regions(project)
    local regions = {}
    local count = r.CountProjectMarkers(project)
    for index = 0, count - 1 do
        local marker = r.GetRegionOrMarker(project, index, '')
        if r.GetRegionOrMarkerInfo_Value(project, marker, 'B_ISREGION') ~= 0
            and r.GetRegionOrMarkerInfo_Value(project, marker, 'B_UISEL') ~= 0 then
            local success, name = r.GetSetRegionOrMarkerInfo_String(project, marker, 'P_NAME', '', false)
            if success then
                regions[#regions + 1] = {
                    marker = marker, name = name,
                    number = r.GetRegionOrMarkerInfo_Value(project, marker, 'I_NUMBER'),
                    position = r.GetRegionOrMarkerInfo_Value(project, marker, 'D_STARTPOS'),
                    index = index,
                }
            end
        end
    end
    table.sort(regions, function(first, second)
        if first.position == second.position then return first.index < second.index end
        return first.position < second.position
    end)
    return regions
end

local function apply(project, regions)
    local renamed = 0
    r.Undo_BeginBlock2(project)
    local success, message = pcall(function()
        for _, region in ipairs(regions) do
            if region.new_name ~= region.name then
                local updated = r.GetSetRegionOrMarkerInfo_String(project, region.marker, 'P_NAME', region.new_name, true)
                if not updated then error('Could not rename region ' .. region.number) end
                renamed = renamed + 1
            end
        end
    end)
    r.Undo_EndBlock2(project, title, -1)
    r.UpdateTimeline()
    status = string.format('Renamed %d region(s).', renamed)
    if not success then
        r.ShowMessageBox(status .. '\n' .. tostring(message) .. '\nUndo to revert this batch.', title, 0)
    end
end

local function draw_options()
    local changed
    changed, options.replace_name = r.ImGui_Checkbox(ctx, 'Replace entire name', options.replace_name)
    r.ImGui_BeginDisabled(ctx, not options.replace_name)
    changed, options.name = r.ImGui_InputText(ctx, 'New name', options.name)
    r.ImGui_EndDisabled(ctx)
    changed, options.find = r.ImGui_InputText(ctx, 'Find (literal, case-sensitive)', options.find)
    changed, options.replacement = r.ImGui_InputText(ctx, 'Replace with', options.replacement)
    changed, options.prefix = r.ImGui_InputText(ctx, 'Prefix', options.prefix)
    changed, options.suffix = r.ImGui_InputText(ctx, 'Suffix', options.suffix)
    changed, options.numbering = r.ImGui_Checkbox(ctx, 'Append numbering', options.numbering)
    if options.numbering then
        changed, options.start = r.ImGui_InputInt(ctx, 'Start number', options.start)
        options.start = math.max(0, math.min(1000000000, options.start))
        changed, options.digits = r.ImGui_InputInt(ctx, 'Minimum digits', options.digits)
        options.digits = math.max(1, math.min(10, options.digits))
        changed, options.separator = r.ImGui_InputText(ctx, 'Number separator', options.separator)
    end
end

local function draw_preview(regions)
    local flags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()
        | r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_ScrollY()
    if r.ImGui_BeginTable(ctx, 'Region preview', 3, flags, 0, 220) then
        r.ImGui_TableSetupColumn(ctx, 'Region', r.ImGui_TableColumnFlags_WidthFixed(), 60)
        r.ImGui_TableSetupColumn(ctx, 'Current name')
        r.ImGui_TableSetupColumn(ctx, 'New name')
        r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
        r.ImGui_TableHeadersRow(ctx)
        for _, region in ipairs(regions) do
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_Text(ctx, tostring(region.number))
            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_TextWrapped(ctx, region.name == '' and '(empty)' or region.name)
            r.ImGui_TableSetColumnIndex(ctx, 2)
            r.ImGui_TextWrapped(ctx, region.new_name == '' and '(empty)' or region.new_name)
        end
        r.ImGui_EndTable(ctx)
    end
end

local function loop()
    r.ImGui_SetNextWindowSize(ctx, 680, 600, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, title, true)
    if visible then
        draw_options()
        local project = r.EnumProjects(-1)
        local regions = selected_regions(project)
        local changes = 0
        for index, region in ipairs(regions) do
            region.new_name = rename(region.name, index)
            if region.new_name ~= region.name then changes = changes + 1 end
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, string.format('%d selected region(s), %d name change(s)', #regions, changes))
        draw_preview(regions)
        r.ImGui_BeginDisabled(ctx, changes == 0)
        if r.ImGui_Button(ctx, 'Apply') then apply(project, regions) end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Reset') then
            options = default_options()
            status = ''
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Close') then open = false end
        if status ~= '' then r.ImGui_Text(ctx, status) end
        r.ImGui_End(ctx)
    end
    if open then r.defer(loop) end
end

r.defer(loop)