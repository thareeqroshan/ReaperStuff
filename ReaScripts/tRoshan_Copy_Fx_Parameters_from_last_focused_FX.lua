--[[
 * ReaScript Name: Copy FX parameters from the last focused FX
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.1
--]] --[[
 * Changelog:
 * v1.1 (2026-09-29)
    + Resolve track, master, and take FX without accessing the wrong chain
    + Preserve the clipboard on failure and record plug-in identity and parameter layout
 * v1.0 (2024-02-16)
 	+ Initial Release
--]]

local EXT_SECTION = "tRoshan_copy_paste_fx_params"
local TITLE = "Copy FX parameters"

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
    local fx, err = focusedFX()
    if not fx then
        reaper.ShowMessageBox(err, TITLE, 0)
        return
    end

    local params = {}
    for index = 0, fx.count - 1 do
        local nameOK, name = fxCall(fx, "GetParamName", index)
        local value, minimum, maximum = fxCall(fx, "GetParam", index)
        if not nameOK or not isFinite(value) or not isFinite(minimum) or not isFinite(maximum)
            or minimum > maximum or value < minimum or value > maximum then
            reaper.ShowMessageBox("Could not read the FX parameters. The clipboard was not changed.", TITLE, 0)
            return
        end
        params[index + 1] = {name = name, value = value, minimum = minimum, maximum = maximum}
    end

    -- Keep the original numbered name/value keys; publish the new format only after a complete copy.
    reaper.DeleteExtState(EXT_SECTION, "format", false)
    reaper.SetExtState(EXT_SECTION, "1", fx.name, false)
    reaper.SetExtState(EXT_SECTION, "fx_type", fx.fxType, false)
    reaper.SetExtState(EXT_SECTION, "fx_ident", fx.ident, false)
    reaper.SetExtState(EXT_SECTION, "param_count", tostring(fx.count), false)
    for index, param in ipairs(params) do
        reaper.SetExtState(EXT_SECTION, tostring(index + 1), string.format("%.17g", param.value), false)
        reaper.SetExtState(EXT_SECTION, "param_name_" .. (index - 1), param.name, false)
        reaper.SetExtState(EXT_SECTION, "param_min_" .. (index - 1), string.format("%.17g", param.minimum), false)
        reaper.SetExtState(EXT_SECTION, "param_max_" .. (index - 1), string.format("%.17g", param.maximum), false)
    end
    local key = fx.count + 2
    while reaper.HasExtState(EXT_SECTION, tostring(key)) do
        reaper.DeleteExtState(EXT_SECTION, tostring(key), false)
        reaper.DeleteExtState(EXT_SECTION, "param_name_" .. (key - 2), false)
        reaper.DeleteExtState(EXT_SECTION, "param_min_" .. (key - 2), false)
        reaper.DeleteExtState(EXT_SECTION, "param_max_" .. (key - 2), false)
        key = key + 1
    end
    reaper.SetExtState(EXT_SECTION, "format", "2", false)

    reaper.ShowMessageBox("The settings from " .. fx.name .. " (" .. fx.location .. ") have been copied.", TITLE, 0)
end

Action()
