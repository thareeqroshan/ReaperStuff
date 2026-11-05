--[[
 * ReaScript Name: Create Four Child Tracks
 * Description: Create four child tracks per selected track and move its media items to the first child.
 * Author: tRoshan
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.0
 * Changelog:
 *   + Initial release
--]]

local r = reaper
local title = 'Create Four Child Tracks'
local count = r.CountSelectedTracks(0)

if count == 0 then
    r.ShowMessageBox('Select at least one track.', title, 0)
    return
end

local tracks = {}
for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    local depth = r.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
    if depth > 0 then
        r.ShowMessageBox('A selected track is already a folder. No tracks were changed.', title, 0)
        return
    end
    tracks[#tracks + 1] = {track = track, depth = depth}
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
local success, message = pcall(function()
    for index = #tracks, 1, -1 do
        local parent = tracks[index]
        local insertion = r.GetMediaTrackInfo_Value(parent.track, 'IP_TRACKNUMBER')
        local children = {}
        for offset = 0, 3 do
            local track_count = r.CountTracks(0)
            r.InsertTrackAtIndex(insertion + offset, true)
            if r.CountTracks(0) ~= track_count + 1 then
                error('Could not insert a child track.')
            end
            local child = r.GetTrack(0, insertion + offset)
            if not child then error('Could not access a new child track.') end
            children[#children + 1] = child
        end

        local opened = r.SetMediaTrackInfo_Value(parent.track, 'I_FOLDERDEPTH', 1)
        local closed = opened and r.SetMediaTrackInfo_Value(children[4], 'I_FOLDERDEPTH', parent.depth - 1)
        if not closed then error('Could not set the folder depths.') end

        for item_index = r.CountTrackMediaItems(parent.track) - 1, 0, -1 do
            local item = r.GetTrackMediaItem(parent.track, item_index)
            if not r.MoveMediaItemToTrack(item, children[1]) then
                error('Could not move a media item to the first child track.')
            end
        end
    end
end)
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock(title, -1)

if not success then
    r.ShowMessageBox(tostring(message) .. '\nUndo to revert this batch.', title, 0)
end