--[[
 * ReaScript Name: Create Folder From Selected Tracks
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.1
--]] --[[
 * Changelog:
 * v1.1 (2026-09-29)
    + Preserve nested folders and existing closing depths when adding a parent
    + Include selected folders' subtrees and reject unsafe selection gaps or parent crossings
 * v1.0 (2024-02-16)
 	+ Initial Release
--]]

local TITLE = "Create Folder From Selected Tracks"

local function selectionRange()
    local selectedCount = reaper.CountSelectedTracks(0)
    if selectedCount == 0 then
        return nil, "Select at least one track or folder first."
    end

    local selected = {}
    for index = 0, selectedCount - 1 do
        selected[reaper.GetSelectedTrack(0, index)] = true
    end
    local firstTrack = reaper.GetSelectedTrack(0, 0)
    local lastSelected = reaper.GetSelectedTrack(0, selectedCount - 1)
    local firstIndex = reaper.GetMediaTrackInfo_Value(firstTrack, "IP_TRACKNUMBER") - 1
    local lastSelectedIndex = reaper.GetMediaTrackInfo_Value(lastSelected, "IP_TRACKNUMBER") - 1
    local trackCount = reaper.CountTracks(0)
    local baseDepth = reaper.GetTrackDepth(firstTrack)
    local depth = baseDepth

    for index = firstIndex, trackCount - 1 do
        local track = reaper.GetTrack(0, index)
        if depth == baseDepth and not selected[track] then
            return nil, "Select adjacent tracks or folders under the same parent. "
                .. "Unselected sibling tracks cannot be included."
        end
        local change = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if change > 1 or change % 1 ~= 0 or depth + change < 0 then
            return nil, "The selected tracks have an invalid folder structure. No tracks were changed."
        end
        depth = depth + change

        -- A selected folder includes its subtree, ending only after its existing closures.
        if index >= lastSelectedIndex and depth <= baseDepth then
            return {firstIndex = firstIndex, lastTrack = track, lastDepth = change, trackCount = trackCount}
        end
        if depth < baseDepth then
            return nil, "The selection crosses an existing folder boundary. "
                .. "Select adjacent tracks or folders under the same parent."
        end
    end
    return nil, "The selected folder has no closing track. Close the folder before creating a parent."
end

local function Action()
    local range, err = selectionRange()
    if not range then
        reaper.ShowMessageBox(err, TITLE, 0)
        return
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    reaper.InsertTrackAtIndex(range.firstIndex, true)
    local newTrack = reaper.GetTrack(0, range.firstIndex)
    if not newTrack or reaper.CountTracks(0) ~= range.trackCount + 1 then
        err = "Could not insert the folder track. No folder depths were changed."
    else
        local opened = reaper.SetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH", 1)
        local closed = opened and reaper.SetMediaTrackInfo_Value(range.lastTrack, "I_FOLDERDEPTH", range.lastDepth - 1)
        if not closed then
            local restoredNew = reaper.SetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH", 0)
            local restoredLast = reaper.SetMediaTrackInfo_Value(range.lastTrack, "I_FOLDERDEPTH", range.lastDepth)
            if restoredNew and restoredLast then
                reaper.DeleteTrack(newTrack)
                err = "Could not create the folder. The original tracks and folder depths were restored."
            else
                err = "Could not create or restore the folder. Undo this action and check the folder structure."
            end
        end
    end
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Create parent track for selected tracks", -1)

    if err then reaper.ShowMessageBox(err, TITLE, 0) end
end

Action()
