-- @noindex
--[[
 * ReaScript Name: Rename Selected Tracks
 * Description: Batch rename selected tracks with a live preview, literal find/replace, prefix, suffix, and numbering.
 * Author: tRoshan
 * REAPER: 7.0
 * Extensions: ReaImGui
--]]

local r = reaper

local function selected_tracks(project)
    local tracks = {}
    for index = 0, r.CountSelectedTracks(project) - 1 do
        local track = r.GetSelectedTrack(project, index)
        local success, name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
        if success then
            tracks[#tracks + 1] = {
                target = track, name = name,
                number = r.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER'),
            }
        end
    end
    return tracks
end

local function set_name(_, track, name)
    return r.GetSetMediaTrackInfo_String(track, 'P_NAME', name, true)
end

local function refresh()
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

local info = debug.getinfo(1, 'S')
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
local BatchRename = dofile(script_path .. 'Functions/BatchRename.lua')
BatchRename.show('Rename Selected Tracks', 'Track', selected_tracks, set_name, refresh)