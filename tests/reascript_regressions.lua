-- @noindex
-- Run from the repository root with Lua 5.4. No REAPER instance is used.

local separator = package.config:sub(1, 1)
local scripts = {
    folder = "tRoshan_Create_Folder_From_Selected_Tracks.lua",
    copy = "tRoshan_Copy_Fx_Parameters_from_last_focused_FX.lua",
    paste = "tRoshan_Paste_Fx_Parameters_from_last_focused_FX.lua"
}

local passed, failed = 0, 0
local filter = arg and arg[1]

local function equal(actual, expected, message)
    assert(actual == expected,
        (message or "Unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, action)
    if filter and not name:lower():find(filter:lower(), 1, true) then return end
    local ok, err = pcall(action)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function sameTable(actual, expected)
    for key, value in pairs(expected) do equal(actual[key], value, tostring(key)) end
    for key, value in pairs(actual) do equal(value, expected[key], tostring(key)) end
end

local function baseMock()
    local state = {messages = {}, undo = 0, undoBegins = 0, undoEnds = 0, refresh = 0}
    local reaper = {}
    state.reaper = reaper
    reaper.ShowMessageBox = function(message, title)
        state.messages[#state.messages + 1] = {message = message, title = title}
        return 0
    end
    reaper.MB = reaper.ShowMessageBox
    reaper.ShowConsoleMsg = function(message) error("Unexpected console output: " .. message) end
    reaper.Undo_BeginBlock = function()
        state.undo = state.undo + 1
        state.undoBegins = state.undoBegins + 1
    end
    reaper.Undo_EndBlock = function()
        state.undo = state.undo - 1
        state.undoEnds = state.undoEnds + 1
        assert(state.undo >= 0, "Unbalanced undo block")
    end
    reaper.PreventUIRefresh = function(delta)
        state.refresh = state.refresh + delta
        assert(state.refresh >= 0, "Unbalanced UI refresh")
    end
    reaper.get_action_context = function() return false, state.actionPath end
    return state
end

local function runAction(state, name)
    state.actionPath = "ReaScripts" .. separator .. scripts[name]
    local environment = setmetatable({reaper = state.reaper}, {__index = _G})
    assert(loadfile(state.actionPath, "t", environment))()
    equal(state.undo, 0, "Undo balance")
    equal(state.refresh, 0, "UI refresh balance")
end

local function lastMessage(state, text)
    assert(#state.messages > 0, "Expected a user notification")
    local message = state.messages[#state.messages].message:lower()
    assert(message:find(text:lower(), 1, true), "Expected '" .. text .. "' in: " .. message)
end

local function failedPaste(state, text)
    lastMessage(state, text)
    for _, message in ipairs(state.messages) do
        assert(not message.message:find("have been pasted", 1, true), "False paste success")
    end
    equal(#state.writes, 0, "Invalid paste must not write parameters")
    equal(state.undoBegins, 0, "Invalid paste must not open an undo block")
end

local function hierarchy(tracks)
    local parents, depths, stack = {}, {}, {}
    for _, track in ipairs(tracks) do
        parents[track] = stack[#stack]
        depths[track] = #stack
        if track.delta == 1 then
            stack[#stack + 1] = track
        elseif track.delta < 0 then
            for _ = 1, -track.delta do
                assert(#stack > 0, "Folder closes above the project root")
                table.remove(stack)
            end
        end
    end
    return parents, depths
end

local function folderMock(deltas, selected)
    local state = baseMock()
    local reaper = state.reaper
    state.tracks, state.mutations, state.setCalls = {}, 0, 0
    for i, delta in ipairs(deltas) do
        state.tracks[i] = {id = i, delta = delta, selected = false, routing = "original routing " .. i}
    end
    for _, index in ipairs(selected) do state.tracks[index].selected = true end
    local function selectedTracks()
        local tracks = {}
        for _, track in ipairs(state.tracks) do
            if track.selected then tracks[#tracks + 1] = track end
        end
        return tracks
    end
    reaper.CountTracks = function() return #state.tracks end
    reaper.CountSelectedTracks = function() return #selectedTracks() end
    reaper.GetSelectedTrack = function(_, index) return selectedTracks()[index + 1] end
    reaper.GetTrack = function(_, index) return state.tracks[index + 1] end
    reaper.IsTrackSelected = function(track) return track.selected end
    reaper.GetParentTrack = function(track) return hierarchy(state.tracks)[track] end
    reaper.GetTrackDepth = function(track)
        local _, depths = hierarchy(state.tracks)
        return depths[track]
    end
    reaper.GetMediaTrackInfo_Value = function(track, key)
        assert(track, "Invalid track handle")
        if key == "I_FOLDERDEPTH" then return track.delta end
        assert(key == "IP_TRACKNUMBER", "Unexpected track field: " .. key)
        for i, candidate in ipairs(state.tracks) do
            if candidate == track then return i end
        end
        error("Unknown track handle")
    end
    reaper.InsertTrackAtIndex = function(index)
        if state.failInsert then return end
        state.wrapper = {id = "wrapper", delta = 0, selected = false}
        table.insert(state.tracks, index + 1, state.wrapper)
        state.mutations = state.mutations + 1
    end
    reaper.SetMediaTrackInfo_Value = function(track, key, value)
        equal(key, "I_FOLDERDEPTH")
        assert(track, "Invalid track handle")
        state.setCalls = state.setCalls + 1
        if state.setCalls == state.failSet then return false end
        track.delta = value
        state.mutations = state.mutations + 1
        return true
    end
    reaper.DeleteTrack = function(track)
        for i, candidate in ipairs(state.tracks) do
            if candidate == track then
                table.remove(state.tracks, i)
                state.mutations = state.mutations + 1
                return
            end
        end
        error("Unknown track to delete")
    end
    reaper.TrackList_AdjustWindows = function() end
    reaper.UpdateArrange = function() end
    return state
end

local function folderCase(deltas, selected, first, last)
    local state = folderMock(deltas, selected)
    local originals = copyTable(state.tracks)
    local originalParents = hierarchy(originals)
    runAction(state, "folder")
    if not first then
        equal(state.mutations, 0, "Unsupported selection changed the project")
        equal(state.undoBegins, 0, "Unsupported selection opened an undo block")
        equal(#state.tracks, #originals)
        assert(#state.messages > 0, "Unsupported selection needs an explanation")
        for i, track in ipairs(originals) do
            equal(state.tracks[i], track)
            equal(track.delta, deltas[i])
        end
        return
    end
    equal(#state.tracks, #originals + 1)
    equal(state.tracks[first], state.wrapper, "Wrapper insertion boundary")
    equal(state.wrapper.delta, 1)
    equal(state.undoBegins, 1)
    equal(state.undoEnds, 1)
    local parents = hierarchy(state.tracks)
    equal(parents[state.wrapper], originalParents[originals[first]], "Wrapper's original parent")
    for i, track in ipairs(originals) do
        equal(track.delta, deltas[i] - (i == last and 1 or 0), "Preserved depth delta for track " .. i)
        equal(track.routing, "original routing " .. i)
        local parent = parents[track]
        if parent == state.wrapper then parent = parents[parent] end
        equal(parent, originalParents[track], "Original parent for track " .. i)
        local ancestor, wrapped = parents[track], false
        while ancestor do
            if ancestor == state.wrapper then wrapped = true end
            ancestor = parents[ancestor]
        end
        equal(wrapped, i >= first and i <= last, "Wrapper membership for track " .. i)
    end
end

test("folder: flat adjacent tracks leave following tracks outside", function()
    folderCase({0, 0, 0}, {1, 2}, 1, 2)
end)
test("folder: complete folder preserves its -1 closure", function()
    folderCase({1, 0, -1, 0}, {1, 2, 3}, 1, 3)
end)
test("folder: nested folder preserves its -2 closure", function()
    folderCase({1, 1, 0, -2, 0}, {1, 2, 3, 4}, 1, 4)
end)
test("folder: selected folder parent includes its existing subtree", function()
    folderCase({1, 1, 0, -2, 0}, {1}, 1, 4)
end)
test("folder: final selected folder extends through nested descendants", function()
    folderCase({0, 1, 1, 0, -2, 0}, {1, 2}, 1, 5)
end)
test("folder: wrapping siblings inside an existing parent", function()
    folderCase({1, 0, 0, 0, -1, 0}, {2, 3}, 2, 3)
end)
test("folder: last child still closes its original parent", function()
    folderCase({1, 0, -1, 0}, {2, 3}, 2, 3)
end)
test("folder: selected subtree closes multiple existing parents", function()
    folderCase({1, 1, 0, -2, 0}, {2}, 2, 4)
end)
test("folder: individual child with -2 closure", function()
    folderCase({1, 1, 0, -2, 0}, {4}, 4, 4)
end)
test("folder: adjacent selected folder roots need not select their children", function()
    folderCase({1, -1, 1, -1, 0}, {1, 3}, 1, 4)
end)
test("folder: selected descendants do not split their selected ancestor", function()
    folderCase({1, 1, -1, -1, 0}, {1, 3}, 1, 4)
end)
test("folder: final project track", function() folderCase({0, 0}, {2}, 2, 2) end)
test("folder: no selected tracks", function() folderCase({0, 0}, {}) end)
test("folder: empty project", function() folderCase({}, {}) end)
test("folder: unselected sibling gap", function() folderCase({0, 0, 0}, {1, 3}) end)
test("folder: unselected folder gap", function() folderCase({0, 1, -1, 0}, {1, 4}) end)
test("folder: selection crosses an existing parent's boundary", function()
    folderCase({1, 0, -1, 1, 0, -1, 0}, {2, 3, 4})
end)
test("folder: equal-depth tracks with different parents", function()
    folderCase({1, 0, -1, 1, 0, -1, 0}, {3, 5})
end)
test("folder: selected folder has no closing track", function() folderCase({1, 0, 0}, {1}) end)
test("folder: insertion failure does not change existing tracks", function()
    local state = folderMock({0, 0, 0}, {1, 2})
    state.failInsert = true
    runAction(state, "folder")
    equal(state.mutations, 0)
    equal(#state.tracks, 3)
    lastMessage(state, "could not insert")
end)
test("folder: failed depth writes restore the original tracks", function()
    for failedCall = 1, 2 do
        local deltas = {1, -1, 0}
        local state = folderMock(deltas, {1})
        local originals = copyTable(state.tracks)
        state.failSet = failedCall
        runAction(state, "folder")
        equal(#state.tracks, #originals)
        for i, track in ipairs(state.tracks) do
            equal(track, originals[i])
            equal(track.delta, deltas[i])
        end
        lastMessage(state, "restored")
    end
end)

test("folder: exhaustive balanced hierarchies and selections up to six tracks", function()
    local cases = 0
    local function check(deltas)
        local count = #deltas
        for mask = 1, (1 << count) - 1 do
            local selected, selectedSet = {}, {}
            local state = folderMock(deltas, {})
            local parents = hierarchy(state.tracks)
            for i, track in ipairs(state.tracks) do
                if mask & (1 << (i - 1)) ~= 0 then
                    selected[#selected + 1] = i
                    selectedSet[track] = true
                end
            end
            local first, last, rootParent, foundRoot, valid = nil, nil, nil, false, true
            local covered = {}
            for i, track in ipairs(state.tracks) do
                local ancestor, selectedAncestor = parents[track], false
                while ancestor do
                    if selectedSet[ancestor] then selectedAncestor = true end
                    ancestor = parents[ancestor]
                end
                covered[i] = selectedSet[track] or selectedAncestor
                if covered[i] then
                    first, last = first or i, i
                end
                if selectedSet[track] and not selectedAncestor then
                    if foundRoot and rootParent ~= parents[track] then valid = false end
                    rootParent, foundRoot = parents[track], true
                end
            end
            for i = first, last do
                if not covered[i] then valid = false end
            end
            local ok, err = pcall(folderCase, deltas, selected, valid and first or nil, last)
            assert(ok, "Depths [" .. table.concat(deltas, ",") .. "], selected ["
                .. table.concat(selected, ",") .. "]: " .. tostring(err))
            cases = cases + 1
        end
    end
    local function generate(deltas, depth, remaining)
        if remaining == 0 then
            if depth == 0 then check(deltas) end
            return
        end
        for delta = -depth, 1 do
            deltas[#deltas + 1] = delta
            generate(deltas, depth + delta, remaining - 1)
            deltas[#deltas] = nil
        end
    end
    for count = 1, 6 do generate({}, 0, count) end
    print("  Checked " .. cases .. " hierarchy/selection combinations")
end)

local function plugin(values)
    local fx = {
        name = "VST3: Example", fxType = "VST3", ident = "example.vst3",
        params = {}, names = {}, minimums = {}, maximums = {}
    }
    for i, value in ipairs(values or {0.12345678901234566, -3.5, 1200}) do
        fx.params[i] = value
        fx.names[i] = "Parameter " .. i
        fx.minimums[i], fx.maximums[i] = -100, 2000
    end
    return fx
end

local function fxMock()
    local state = baseMock()
    local reaper = state.reaper
    state.ext, state.reads, state.writes = {}, {}, {}
    state.master = {kind = "MediaTrack*", name = "MASTER", fx = {[0] = plugin()}}
    state.track = {kind = "MediaTrack*", name = "Audio", fx = {[0] = plugin()}, items = {}}
    state.tracks = {
        [0] = state.track,
        [1] = {kind = "MediaTrack*", name = "Second track", fx = {[0] = plugin()}, items = {}}
    }
    state.item = {kind = "MediaItem*", takes = {}}
    state.track.items[0] = state.item
    state.take = {kind = "MediaItem_Take*", fx = {[0] = plugin()}}
    state.otherTake = {kind = "MediaItem_Take*", fx = {[0] = plugin()}}
    state.item.takes[0], state.item.takes[2] = state.otherTake, state.take
    state.focus = {true, 0, -1, 0, 0, 0}
    reaper.GetTouchedOrFocusedFX = function(mode)
        equal(mode, 1, "Query focused, not last-touched FX")
        return table.unpack(state.focus)
    end
    reaper.GetFocusedFX = function()
        local ok, track, item, take, fx = table.unpack(state.focus)
        if not ok then return 0, 0, 0, 0 end
        return item < 0 and 1 or 2, track + 1, item, item < 0 and fx or (take << 16) | fx
    end
    reaper.GetMasterTrack = function() return state.master end
    reaper.GetTrack = function(_, index) return state.tracks[index] end
    reaper.GetTrackMediaItem = function(track, index)
        assert(track and track.kind == "MediaTrack*", "Invalid track handle")
        return track.items and track.items[index]
    end
    reaper.GetTake = function(item, index)
        assert(item and item.kind == "MediaItem*", "Invalid item handle")
        return item.takes[index]
    end
    reaper.GetTrackName = function(track)
        assert(track and track.kind == "MediaTrack*", "Invalid track handle")
        return true, track.name
    end
    reaper.ValidatePtr2 = function(_, object, kind)
        return object ~= nil and object.kind == kind and not object.invalid
    end
    reaper.HasExtState = function(_, key) return state.ext[key] ~= nil end
    reaper.GetExtState = function(_, key) return state.ext[key] or "" end
    reaper.SetExtState = function(_, key, value, persist)
        equal(persist, false, "Clipboard must remain session-local")
        state.ext[key] = value
    end
    reaper.DeleteExtState = function(_, key, persist)
        equal(persist, false)
        state.ext[key] = nil
    end
    for _, api in ipairs({"TrackFX_", "TakeFX_"}) do
        local kind = api == "TrackFX_" and "MediaTrack*" or "MediaItem_Take*"
        local function getFX(object, index, operation)
            assert(object and object.kind == kind and not object.invalid, "Wrong FX API or invalid handle")
            state.reads[#state.reads + 1] = {api = api, object = object, index = index, operation = operation}
            return object.fx[index]
        end
        reaper[api .. "GetFXName"] = function(object, index)
            local fx = getFX(object, index, "name")
            return fx ~= nil and not fx.badName, fx and fx.name or ""
        end
        reaper[api .. "GetNamedConfigParm"] = function(object, index, key)
            local fx = getFX(object, index, key)
            if not fx then return false, "" end
            if key == "fx_type" then return not fx.badIdentity, fx.fxType end
            if key == "fx_ident" then return not fx.badIdentity, fx.ident end
            if key == "container_count" then return fx.container == true, fx.container and "1" or "" end
            error("Unexpected FX configuration field: " .. key)
        end
        reaper[api .. "GetNumParams"] = function(object, index)
            local fx = getFX(object, index, "count")
            return fx and #fx.params or 0
        end
        reaper[api .. "GetParam"] = function(object, index, parameter)
            local fx = assert(getFX(object, index, "parameter"), "Missing FX")
            return fx.params[parameter + 1], fx.minimums[parameter + 1], fx.maximums[parameter + 1]
        end
        reaper[api .. "GetParamName"] = function(object, index, parameter)
            local fx = assert(getFX(object, index, "parameter name"), "Missing FX")
            return not fx.badParamName, fx.names[parameter + 1]
        end
        reaper[api .. "SetParam"] = function(object, index, parameter, value)
            local fx = assert(getFX(object, index, "write"), "Missing FX")
            assert(type(value) == "number", "Parameter must be numeric")
            state.writes[#state.writes + 1] = {
                api = api, object = object, index = index, parameter = parameter, value = value
            }
            if state.failWrite == parameter or (state.failRestore and parameter == 0 and value == 0) then
                return false
            end
            assert(fx.params[parameter + 1] ~= nil, "Invalid parameter index")
            fx.params[parameter + 1] = value
            return true
        end
    end
    return state
end

local function resetActivity(state)
    state.messages, state.reads, state.writes = {}, {}, {}
    state.undoBegins, state.undoEnds = 0, 0
end

local function copyFX(state)
    runAction(state, "copy")
    lastMessage(state, "have been copied")
    resetActivity(state)
end

local function checkRoundTrip(trackIndex, itemIndex, takeIndex, fxIndex)
    local state = fxMock()
    local object = trackIndex == -1 and state.master or state.tracks[trackIndex]
    if itemIndex >= 0 then
        object = {kind = "MediaItem_Take*", fx = {}}
        state.tracks[trackIndex].items[itemIndex] = {kind = "MediaItem*", takes = {[takeIndex] = object}}
    end
    object.fx[fxIndex] = plugin()
    local fx = object.fx[fxIndex]
    local expected = copyTable(fx.params)
    state.focus = {true, trackIndex, itemIndex, takeIndex, fxIndex, 1}
    runAction(state, "copy")
    lastMessage(state, "have been copied")
    for _, call in ipairs(state.reads) do
        equal(call.object, object, "Copy must read only the focused FX owner")
        equal(call.index, fxIndex, "Copy must preserve the encoded FX index")
    end
    resetActivity(state)
    for i = 1, #fx.params do fx.params[i] = 0 end
    runAction(state, "paste")
    sameTable(fx.params, expected)
    equal(#state.writes, #expected)
    for _, call in ipairs(state.reads) do
        equal(call.object, object, "Only the focused FX owner may be accessed")
        equal(call.index, fxIndex, "Encoded FX index must be preserved")
    end
    for _, call in ipairs(state.writes) do
        equal(call.object, object)
        equal(call.index, fxIndex)
    end
    equal(state.undoBegins, 1)
    equal(state.undoEnds, 1)
    lastMessage(state, "have been pasted")
end

test("FX: regular track round-trip preserves raw parameter precision", function()
    checkRoundTrip(0, -1, 0, 0)
end)
test("FX: nonzero regular track and FX indices", function() checkRoundTrip(1, -1, 0, 3) end)
test("FX: master track round-trip", function() checkRoundTrip(-1, -1, 0, 0) end)
test("FX: take round-trip", function() checkRoundTrip(0, 0, 0, 0) end)
test("FX: nonzero track, item, take, and FX indices", function() checkRoundTrip(1, 3, 2, 3) end)
test("FX: input FX preserves encoded index", function() checkRoundTrip(0, -1, 0, 0x1000000) end)
test("FX: monitoring FX preserves encoded index", function() checkRoundTrip(-1, -1, 0, 0x1000000) end)
test("FX: plug-in inside a track container", function() checkRoundTrip(0, -1, 0, 0x2000005) end)
test("FX: plug-in inside a take container", function() checkRoundTrip(0, 0, 2, 0x2000005) end)
test("FX: plug-in inside an input FX container", function() checkRoundTrip(0, -1, 0, 0x3000005) end)

test("FX: a take and track FX at the same index never access the wrong plug-in", function()
    local state = fxMock()
    state.track.fx[0].params = {0.4, 0.5, 0.6}
    local trackValues = copyTable(state.track.fx[0].params)
    local otherTakeValues = copyTable(state.otherTake.fx[0].params)
    local expected = copyTable(state.take.fx[0].params)
    state.focus = {true, 0, 0, 2, 0, 0}
    runAction(state, "copy")
    for _, call in ipairs(state.reads) do equal(call.object, state.take, "Copy must use the focused take") end
    for i = 1, #expected do state.take.fx[0].params[i] = 0 end
    runAction(state, "paste")
    sameTable(state.take.fx[0].params, expected)
    sameTable(state.track.fx[0].params, trackValues)
    sameTable(state.otherTake.fx[0].params, otherTakeValues)
    for _, call in ipairs(state.reads) do equal(call.object, state.take) end
    for _, call in ipairs(state.writes) do equal(call.object, state.take) end
end)

test("FX: same plug-in can paste across track, master, and take chains", function()
    local state = fxMock()
    local expected = copyTable(state.track.fx[0].params)
    copyFX(state)
    state.master.fx[0].params = {0, 0, 0}
    state.focus = {true, -1, -1, 0, 0, 0}
    runAction(state, "paste")
    sameTable(state.master.fx[0].params, expected)
    state.take.fx[0].params = {0, 0, 0}
    state.focus = {true, 0, 0, 2, 0, 0}
    runAction(state, "paste")
    sameTable(state.take.fx[0].params, expected)
end)

test("FX: renamed instance uses plug-in identity rather than display name", function()
    local state = fxMock()
    local expected = copyTable(state.track.fx[0].params)
    copyFX(state)
    state.track.fx[0].name = "My renamed instance"
    state.track.fx[0].params = {0, 0, 0}
    runAction(state, "paste")
    sameTable(state.track.fx[0].params, expected)
    lastMessage(state, "have been pasted")
end)

local invalidTargets = {
    {"no focus", function(state) state.focus[1] = false end, "focus"},
    {"missing track", function(state) state.focus[2] = 99 end, "available"},
    {"invalid track handle", function(state) state.track.invalid = true end, "available"},
    {"missing item", function(state) state.focus[3] = 99 end, "available"},
    {"invalid item handle", function(state)
        state.focus[3], state.focus[4], state.item.invalid = 0, 2, true
    end, "available"},
    {"missing take", function(state) state.focus[3], state.focus[4] = 0, 99 end, "available"},
    {"invalid take handle", function(state)
        state.focus[3], state.focus[4], state.take.invalid = 0, 2, true
    end, "available"},
    {"missing FX", function(state) state.focus[5] = 99 end, "available"},
    {"negative FX index", function(state) state.focus[5] = -1 end, "focus"},
    {"unreadable FX identity", function(state) state.track.fx[0].badIdentity = true end, "identify"},
    {"whole container", function(state) state.track.fx[0].container = true end, "container"},
    {"missing REAPER 7 API", function(state) state.reaper.GetTouchedOrFocusedFX = nil end, "REAPER 7"}
}
for _, case in ipairs(invalidTargets) do
    test("FX: " .. case[1] .. " preserves clipboard and cannot paste", function()
        local state = fxMock()
        copyFX(state)
        local clipboard = copyTable(state.ext)
        case[2](state)
        runAction(state, "copy")
        sameTable(state.ext, clipboard)
        lastMessage(state, case[3])
        resetActivity(state)
        runAction(state, "paste")
        failedPaste(state, case[3])
        sameTable(state.ext, clipboard)
    end)
end

test("FX: unreadable source parameters preserve the old clipboard", function()
    for _, corrupt in ipairs({
        function(fx) fx.badParamName = true end,
        function(fx) fx.params[1] = 0 / 0 end,
        function(fx) fx.params[1] = math.huge end,
        function(fx) fx.minimums[1] = math.huge end,
        function(fx) fx.maximums[1] = -101 end,
        function(fx) fx.params = {} end
    }) do
        local state = fxMock()
        copyFX(state)
        local clipboard = copyTable(state.ext)
        corrupt(state.track.fx[0])
        runAction(state, "copy")
        sameTable(state.ext, clipboard)
        assert(#state.messages > 0)
        assert(not state.messages[#state.messages].message:find("have been copied", 1, true))
    end
end)

test("FX: empty clipboard", function()
    local state = fxMock()
    runAction(state, "paste")
    failedPaste(state, "clipboard")
end)
test("FX: legacy clipboard explicitly requires a fresh copy", function()
    local state = fxMock()
    state.ext = {["1"] = "VST3: Example", ["2"] = "0.5"}
    runAction(state, "paste")
    failedPaste(state, "copy")
    equal(state.ext["2"], "0.5")
end)
test("FX: failed copy preserves a legacy clipboard too", function()
    local state = fxMock()
    state.ext = {["1"] = "VST3: Example", ["2"] = "0.5"}
    local clipboard = copyTable(state.ext)
    state.focus[1] = false
    runAction(state, "copy")
    sameTable(state.ext, clipboard)
    lastMessage(state, "focus")
end)

local corruptClipboards = {
    {"unsupported format", function(ext) ext.format = "999" end},
    {"missing identity", function(ext) ext.fx_ident = nil end},
    {"missing FX type", function(ext) ext.fx_type = nil end},
    {"invalid count", function(ext) ext.param_count = "not a number" end},
    {"fractional count", function(ext) ext.param_count = "2.5" end},
    {"unbounded count", function(ext) ext.param_count = "1e300" end},
    {"missing value", function(ext) ext["3"] = nil end},
    {"nonnumeric value", function(ext) ext["3"] = "invalid" end},
    {"infinite value", function(ext) ext["3"] = "1e999" end},
    {"out-of-range value", function(ext) ext["3"] = "3000" end},
    {"missing parameter name", function(ext) ext.param_name_1 = nil end},
    {"invalid parameter minimum", function(ext) ext.param_min_1 = "invalid" end},
    {"invalid parameter maximum", function(ext) ext.param_max_1 = "1e999" end},
    {"extra parameter", function(ext) ext["5"] = "0.5" end}
}
for _, case in ipairs(corruptClipboards) do
    test("FX clipboard: " .. case[1] .. " rejects all writes", function()
        local state = fxMock()
        copyFX(state)
        case[2](state.ext)
        local clipboard, values = copyTable(state.ext), copyTable(state.track.fx[0].params)
        runAction(state, "paste")
        failedPaste(state, "clipboard")
        sameTable(state.ext, clipboard)
        sameTable(state.track.fx[0].params, values)
    end)
end

local incompatibleTargets = {
    {"different identity despite matching display name", function(fx) fx.ident = "different.vst3" end},
    {"different plug-in type", function(fx) fx.fxType = "VST" end},
    {"fewer parameters", function(fx) table.remove(fx.params) end},
    {"more parameters", function(fx) fx.params[4] = 0 end},
    {"reordered parameters", function(fx) fx.names[1], fx.names[2] = fx.names[2], fx.names[1] end},
    {"different parameter range", function(fx) fx.minimums[2] = -50 end}
}
for _, case in ipairs(incompatibleTargets) do
    test("FX compatibility: " .. case[1], function()
        local state = fxMock()
        copyFX(state)
        case[2](state.track.fx[0])
        local values = copyTable(state.track.fx[0].params)
        runAction(state, "paste")
        failedPaste(state, "incompatible")
        sameTable(state.track.fx[0].params, values)
    end)
end

test("FX: copying a smaller layout removes stale clipboard parameters", function()
    local state = fxMock()
    copyFX(state)
    state.track.fx[0] = plugin({0.75})
    copyFX(state)
    equal(state.ext["3"], nil)
    equal(state.ext.param_name_1, nil)
    state.track.fx[0].params[1] = 0
    runAction(state, "paste")
    equal(state.track.fx[0].params[1], 0.75)
    lastMessage(state, "have been pasted")
end)

test("FX: a rejected parameter write reports failure and balances undo/UI refresh", function()
    local state = fxMock()
    copyFX(state)
    state.failWrite = 1
    state.track.fx[0].params = {0, 0, 0}
    runAction(state, "paste")
    lastMessage(state, "could not")
    sameTable(state.track.fx[0].params, {0, 0, 0})
    lastMessage(state, "restored")
    equal(state.undoBegins, 1)
    equal(state.undoEnds, 1)
    for _, message in ipairs(state.messages) do
        assert(not message.message:find("have been pasted", 1, true), "False success after write failure")
    end
end)
test("FX: rollback failure is explicitly reported", function()
    local state = fxMock()
    copyFX(state)
    state.failWrite, state.failRestore = 1, true
    state.track.fx[0].params = {0, 0, 0}
    runAction(state, "paste")
    lastMessage(state, "could not be restored")
    equal(state.undoBegins, 1)
    equal(state.undoEnds, 1)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
