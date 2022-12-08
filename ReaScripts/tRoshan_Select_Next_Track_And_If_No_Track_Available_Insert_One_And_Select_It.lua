function main()
    local track = reaper.GetSelectedTrack(0, 0)
    local track_count = reaper.CountTracks(0)
    if track_count > 0 then
        if track == reaper.GetTrack(0, track_count-1) then
            reaper.InsertTrackAtIndex(track_count, true)
            track = reaper.GetTrack(0, track_count)
        else
            track = reaper.GetTrack(0, reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
        end
    else
        reaper.InsertTrackAtIndex(1, true)
        track = reaper.GetTrack(0, 0)
    end
    reaper.SetOnlyTrackSelected(track)
    reaper.SetTrackSelected(track, true)
end
    
reaper.defer(main)