--[[
 * ReaScript Name: Space Selected Items
 * Description: Space selected items in timeline order across tracks, keeping the first item in place.
 * Author: tRoshan
 * REAPER: 7.0
 * Version: 1.0
 * Changelog:
 *   + Initial release
--]]

local r = reaper
local title = 'Space Selected Items'
local project = r.EnumProjects(-1)
local count = r.CountSelectedMediaItems(project)

if count < 2 then
    r.ShowMessageBox('Select at least two media items.', title, 0)
    return
end

local accepted, input = r.GetUserInputs(title, 1, 'Gap between items (seconds):', '1')
if not accepted then return end

local gap = tonumber(input)
if not gap or gap ~= gap or gap < 0 or gap == math.huge then
    r.ShowMessageBox('Enter a finite number of seconds, zero or greater.', title, 0)
    return
end

local items = {}
for index = 0, count - 1 do
    local item = r.GetSelectedMediaItem(project, index)
    items[#items + 1] = {
        item = item,
        position = r.GetMediaItemInfo_Value(item, 'D_POSITION'),
        length = r.GetMediaItemInfo_Value(item, 'D_LENGTH'),
        index = index,
    }
end

table.sort(items, function(first, second)
    if first.position == second.position then return first.index < second.index end
    return first.position < second.position
end)

r.Undo_BeginBlock2(project)
r.PreventUIRefresh(1)
local success, message = pcall(function()
    local ending = items[1].position + items[1].length
    for index = 2, #items do
        local item = items[index]
        local position = ending + gap
        if not r.SetMediaItemPosition(item.item, position, false) then
            error('Could not reposition a selected item.')
        end
        ending = position + item.length
    end
end)
r.PreventUIRefresh(-1)
r.Undo_EndBlock2(project, title, -1)
r.UpdateArrange()

if not success then
    r.ShowMessageBox(tostring(message) .. '\nUndo to revert this batch.', title, 0)
end