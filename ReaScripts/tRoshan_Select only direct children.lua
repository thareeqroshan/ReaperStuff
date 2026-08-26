--[[
 * ReaScript Name: Select only direct children
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.0
--]] --[[
 * Changelog:
 * v1.0 (2026-08-26)
	+ Initial Release
--]]

local selectedTracks = {}
local selectedTrackCount = reaper.CountSelectedTracks(0)

for i = 0, selectedTrackCount - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    selectedTracks[track] = true
end

reaper.Undo_BeginBlock()

reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks

local trackCount = reaper.CountTracks(0)
for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local parent = reaper.GetParentTrack(track)
    if parent and selectedTracks[parent] then
        reaper.SetTrackSelected(track, true)
    end
end

reaper.Undo_EndBlock("Select only direct children", -1)
