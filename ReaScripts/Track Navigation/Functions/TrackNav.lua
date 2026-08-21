-- @noindex
-- Shared helpers for the tRoshan track-navigation scripts.
-- Load with:  local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')
--
-- Navigation is visibility-aware: tracks hidden from the TCP or sitting inside
-- a fully collapsed folder are skipped. Scroll-into-view uses js_ReaScriptAPI
-- for the downward case; without it, only upward off-screen scrolling happens.

local M = {}

-- 0-based index of a track, or -1 for nil / master.
function M.index(track)
    if not track then return -1 end
    return math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
end

-- Shown in the arrange (TCP) and not inside a fully collapsed folder.
function M.isVisible(track)
    if not track then return false end
    if reaper.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 0 then
        return false
    end
    local parent = reaper.GetParentTrack(track)
    while parent do
        if reaper.GetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT") == 2 then
            return false
        end
        parent = reaper.GetParentTrack(parent)
    end
    return true
end

-- Topmost / bottommost selected track, in track order. nil if nothing selected.
function M.firstSelected()
    return reaper.GetSelectedTrack(0, 0)
end

function M.lastSelected()
    local count = reaper.CountSelectedTracks(0)
    if count == 0 then return nil end
    return reaper.GetSelectedTrack(0, count - 1)
end

function M.firstVisible()
    for i = 0, reaper.CountTracks(0) - 1 do
        local t = reaper.GetTrack(0, i)
        if M.isVisible(t) then return t end
    end
    return nil
end

function M.lastVisible()
    for i = reaper.CountTracks(0) - 1, 0, -1 do
        local t = reaper.GetTrack(0, i)
        if M.isVisible(t) then return t end
    end
    return nil
end

function M.nextVisible(fromIndex)
    for i = fromIndex + 1, reaper.CountTracks(0) - 1 do
        local t = reaper.GetTrack(0, i)
        if M.isVisible(t) then return t end
    end
    return nil
end

function M.prevVisible(fromIndex)
    for i = fromIndex - 1, 0, -1 do
        local t = reaper.GetTrack(0, i)
        if M.isVisible(t) then return t end
    end
    return nil
end

function M.insertTrackAtEnd()
    local count = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(count, true)
    return reaper.GetTrack(0, count)
end

function M.insertTrackAtStart()
    reaper.InsertTrackAtIndex(0, true)
    return reaper.GetTrack(0, 0)
end

-- Arrange view height in pixels (needs js_ReaScriptAPI), or nil.
local function arrangeHeight()
    if not reaper.JS_Window_FindChildByID then return nil end
    local arrange = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 0x3E8)
    if not arrange then return nil end
    local ok, _, h = reaper.JS_Window_GetClientSize(arrange)
    if ok and h and h > 0 then return h end
    return nil
end

-- Scroll the arrange (and mixer) to the track, only when it is off-screen.
function M.reveal(track)
    if not track then return end
    reaper.SetMixerScroll(track)
    local y = reaper.GetMediaTrackInfo_Value(track, "I_TCPY")
    local h = reaper.GetMediaTrackInfo_Value(track, "I_TCPH")
    local viewH = arrangeHeight()
    local offscreen
    if viewH then
        offscreen = y < 0 or (y + h) > viewH
    else
        offscreen = y < 0
    end
    if offscreen then
        reaper.Main_OnCommand(40913, 0) -- Track: Vertical scroll selected tracks into view
    end
end

local function isMaster(track)
    return track == reaper.GetMasterTrack(0)
end

function M.selectOnly(track)
    if not track or isMaster(track) then return end
    reaper.SetOnlyTrackSelected(track)
    M.reveal(track)
end

function M.addToSelection(track)
    if not track or isMaster(track) then return end
    reaper.SetTrackSelected(track, true)
    M.reveal(track)
end

function M.removeFromSelection(track)
    if not track or isMaster(track) then return end
    reaper.SetTrackSelected(track, false)
end

-- High-level navigation ------------------------------------------------------

function M.selectNext(insertAtEdge)
    if reaper.CountTracks(0) == 0 then
        if insertAtEdge then
            reaper.Undo_BeginBlock()
            M.selectOnly(M.insertTrackAtEnd())
            reaper.Undo_EndBlock("tRoshan Select next track", -1)
        end
        return
    end
    local ref = M.lastSelected() or reaper.GetLastTouchedTrack()
    local idx = M.index(ref)
    if idx < 0 then
        M.selectOnly(M.firstVisible() or reaper.GetTrack(0, 0))
        return
    end
    local target = M.nextVisible(idx)
    if target then
        M.selectOnly(target)
    elseif insertAtEdge then
        reaper.Undo_BeginBlock()
        M.selectOnly(M.insertTrackAtEnd())
        reaper.Undo_EndBlock("tRoshan Select next track", -1)
    end
end

function M.selectPrevious(insertAtEdge)
    if reaper.CountTracks(0) == 0 then
        if insertAtEdge then
            reaper.Undo_BeginBlock()
            M.selectOnly(M.insertTrackAtStart())
            reaper.Undo_EndBlock("tRoshan Select previous track", -1)
        end
        return
    end
    local ref = M.firstSelected() or reaper.GetLastTouchedTrack()
    local idx = M.index(ref)
    if idx < 0 then
        M.selectOnly(M.lastVisible() or reaper.GetTrack(0, reaper.CountTracks(0) - 1))
        return
    end
    local target = M.prevVisible(idx)
    if target then
        M.selectOnly(target)
    elseif insertAtEdge then
        reaper.Undo_BeginBlock()
        M.selectOnly(M.insertTrackAtStart())
        reaper.Undo_EndBlock("tRoshan Select previous track", -1)
    end
end

function M.extendUp()
    local top = M.firstSelected()
    if not top then
        M.addToSelection(reaper.GetLastTouchedTrack() or M.lastVisible())
        return
    end
    local above = M.prevVisible(M.index(top))
    if above then M.addToSelection(above) end
end

function M.extendDown()
    local bottom = M.lastSelected()
    if not bottom then
        M.addToSelection(reaper.GetLastTouchedTrack() or M.firstVisible())
        return
    end
    local below = M.nextVisible(M.index(bottom))
    if below then M.addToSelection(below) end
end

function M.shrinkTop()
    M.removeFromSelection(M.firstSelected())
end

function M.shrinkBottom()
    M.removeFromSelection(M.lastSelected())
end

return M
