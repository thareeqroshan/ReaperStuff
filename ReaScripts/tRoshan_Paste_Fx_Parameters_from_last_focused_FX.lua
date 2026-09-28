--[[
 * ReaScript Name: Paste FX parameters to the last focused FX
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.1
--]] --[[
 * Changelog:
 * v1.1 (2026-09-29)
    + Resolve track, master, and take FX without accessing the wrong chain
    + Validate clipboard identity and parameter layout before writing; report failures accurately
 * v1.0 (2024-02-16)
 	+ Initial Release
--]]

local EXT_SECTION = "tRoshan_copy_paste_fx_params"
local TITLE = "Paste FX parameters"

local function isFinite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function fxCall(fx, method, ...)
    return reaper[fx.api .. method](fx.object, fx.index, ...)
end

local function focusedFX()
    if not reaper.GetTouchedOrFocusedFX then
        return nil, "REAPER 7.0 or later is required."
    end
    local ok, trackIndex, itemIndex, takeIndex, fxIndex = reaper.GetTouchedOrFocusedFX(1)
    if not ok or trackIndex < -1 or itemIndex < -1 or fxIndex < 0 then
        return nil, "No focused FX is available. Focus an FX window first."
    end

    local track
    if trackIndex == -1 then
        track = reaper.GetMasterTrack(0)
    else
        track = reaper.GetTrack(0, trackIndex)
    end
    if not track or not reaper.ValidatePtr2(0, track, "MediaTrack*") then
        return nil, "The last focused FX track is no longer available."
    end

    local fx = {object = track, index = fxIndex, api = "TrackFX_"}
    if itemIndex >= 0 then
        local item = reaper.GetTrackMediaItem(track, itemIndex)
        if not item or not reaper.ValidatePtr2(0, item, "MediaItem*") or takeIndex < 0 then
            return nil, "The last focused FX item is no longer available."
        end
        local take = reaper.GetTake(item, takeIndex)
        if not take or not reaper.ValidatePtr2(0, take, "MediaItem_Take*") then
            return nil, "The last focused FX take is no longer available."
        end
        fx.object, fx.api = take, "TakeFX_"
    end

    local nameOK, name = fxCall(fx, "GetFXName")
    if not nameOK or name == "" then
        return nil, "The last focused FX is no longer available."
    end
    if fxCall(fx, "GetNamedConfigParm", "container_count") then
        return nil, "Focus an individual plug-in inside the container, not the container itself."
    end
    local typeOK, fxType = fxCall(fx, "GetNamedConfigParm", "fx_type")
    local identOK, ident = fxCall(fx, "GetNamedConfigParm", "fx_ident")
    if not typeOK or not identOK or fxType == "" or ident == "" then
        return nil, "Could not identify the focused plug-in safely."
    end
    local count = fxCall(fx, "GetNumParams")
    if not isFinite(count) or count < 1 or count % 1 ~= 0 then
        return nil, "Could not read the focused FX parameter layout."
    end
    local trackNameOK, trackName = reaper.GetTrackName(track)
    if not trackNameOK then
        return nil, "The last focused FX track is no longer available."
    end
    fx.name, fx.fxType, fx.ident, fx.count, fx.location = name, fxType, ident, count, trackName
    if itemIndex >= 0 then
        fx.location = trackName .. ", item " .. (itemIndex + 1) .. ", take " .. (takeIndex + 1)
    end
    return fx
end

local function Action()
    if not reaper.HasExtState(EXT_SECTION, "1") then
        reaper.ShowMessageBox("No values in clipboard. Run Copy FX parameters first.", TITLE, 0)
        return
    end
    if reaper.GetExtState(EXT_SECTION, "format") ~= "2" then
        reaper.ShowMessageBox("The clipboard format is outdated or unsupported. Update both FX parameter actions "
            .. "and run Copy FX parameters again.", TITLE, 0)
        return
    end

    local count = math.tointeger(tonumber(reaper.GetExtState(EXT_SECTION, "param_count")))
    local fxType = reaper.GetExtState(EXT_SECTION, "fx_type")
    local ident = reaper.GetExtState(EXT_SECTION, "fx_ident")
    if not count or count < 1 or fxType == "" or ident == ""
        or reaper.GetExtState(EXT_SECTION, "1") == ""
        or reaper.HasExtState(EXT_SECTION, tostring(count + 2)) then
        reaper.ShowMessageBox("The FX clipboard is invalid. Run Copy FX parameters again.", TITLE, 0)
        return
    end
    local fx, err = focusedFX()
    if not fx then
        reaper.ShowMessageBox(err, TITLE, 0)
        return
    end
    if fx.fxType ~= fxType or fx.ident ~= ident then
        reaper.ShowMessageBox("The clipboard plug-in is incompatible with the focused FX. "
            .. "Copy parameters from the same plug-in type first.", TITLE, 0)
        return
    end
    if fx.count ~= count then
        reaper.ShowMessageBox("The clipboard parameter layout is incompatible with the focused FX "
            .. "(different parameter counts).", TITLE, 0)
        return
    end

    local params, originals = {}, {}
    for index = 0, count - 1 do
        local value = tonumber(reaper.GetExtState(EXT_SECTION, tostring(index + 2)))
        local minimum = tonumber(reaper.GetExtState(EXT_SECTION, "param_min_" .. index))
        local maximum = tonumber(reaper.GetExtState(EXT_SECTION, "param_max_" .. index))
        if not reaper.HasExtState(EXT_SECTION, "param_name_" .. index)
            or not isFinite(value) or not isFinite(minimum) or not isFinite(maximum)
            or minimum > maximum or value < minimum or value > maximum then
            reaper.ShowMessageBox("The FX clipboard contains invalid parameter data. Run Copy FX parameters again.", TITLE, 0)
            return
        end
        local nameOK, name = fxCall(fx, "GetParamName", index)
        local original, targetMin, targetMax = fxCall(fx, "GetParam", index)
        if not nameOK or name ~= reaper.GetExtState(EXT_SECTION, "param_name_" .. index)
            or minimum ~= targetMin or maximum ~= targetMax or not isFinite(original) then
            reaper.ShowMessageBox("The clipboard parameter layout is incompatible with the focused FX "
                .. "(parameter names or ranges differ).", TITLE, 0)
            return
        end
        params[index + 1], originals[index + 1] = value, original
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    local failedAt
    for index, value in ipairs(params) do
        if not fxCall(fx, "SetParam", index - 1, value) then
            failedAt = index
            break
        end
    end
    local restored = true
    if failedAt then
        for index = failedAt - 1, 1, -1 do
            if not fxCall(fx, "SetParam", index - 1, originals[index]) then restored = false end
        end
    end
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(TITLE, -1)

    if failedAt then
        local message = "Could not set parameter " .. failedAt .. " of " .. fx.name .. "."
        if restored then
            message = message .. "\nAny earlier parameter writes were restored."
        else
            message = message .. "\nSome values could not be restored. Check the FX settings or undo the paste."
        end
        reaper.ShowMessageBox(message, TITLE, 0)
        return
    end
    reaper.ShowMessageBox("The settings have been pasted to " .. fx.name .. " (" .. fx.location .. ").", TITLE, 0)
end

Action()
