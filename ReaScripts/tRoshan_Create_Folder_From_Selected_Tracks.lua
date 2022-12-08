function Msg(value)
  if console then
    reaper.ShowConsoleMsg(tostring(value) .. "\n")
  end
end

function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

reaper.Undo_BeginBlock()

-- Get a list of the selected tracks
local selectedTracks = {}
local numSelectedTracks = reaper.CountSelectedTracks(0)
for i = 0, numSelectedTracks - 1 do
  selectedTracks[i] = reaper.GetSelectedTrack(0, i)
end

-- Get the index of the first selected track 
local firstTrack = selectedTracks[0]
local lastTrack = selectedTracks[tablelength(selectedTracks) - 1]
local firstTrackIndex = reaper.GetMediaTrackInfo_Value(firstTrack, "IP_TRACKNUMBER")

-- Create a new track just above the first selected track
reaper.InsertTrackAtIndex(firstTrackIndex - 1, true)
local newTrack = reaper.GetTrack(0, firstTrackIndex - 1)
reaper.SetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH", 1)
reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", -1)


reaper.Undo_EndBlock("Create parent track for selected tracks", -1)

