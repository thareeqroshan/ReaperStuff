--[[
 * ReaScript Name: Rename Selected Regions
 * Description: Batch rename selected regions or tracks with a live preview, literal find/replace, prefix, suffix, and numbering.
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.x with native region selection APIs
 * Extensions: ReaImGui
 * Version: 1.1
 * Provides:
 *   [main] tRoshan_Rename_Selected_Tracks.lua
 *   Functions/BatchRename.lua
 * Changelog:
 *   + Add a selected-track renamer and a shared compact dialog with a resizable preview
--]]

local r = reaper
local title = 'Rename Selected Regions'

if not r.GetRegionOrMarker or not r.GetRegionOrMarkerInfo_Value
    or not r.GetSetRegionOrMarkerInfo_String then
    r.ShowMessageBox('Please update REAPER. This script requires the native region selection APIs.', title, 0)
    return
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
                    target = marker, name = name,
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

local function set_name(project, marker, name)
    return r.GetSetRegionOrMarkerInfo_String(project, marker, 'P_NAME', name, true)
end

local info = debug.getinfo(1, 'S')
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
local BatchRename = dofile(script_path .. 'Functions/BatchRename.lua')
BatchRename.show(title, 'Region', selected_regions, set_name, r.UpdateTimeline)