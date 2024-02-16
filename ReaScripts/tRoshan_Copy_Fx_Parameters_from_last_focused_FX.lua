--[[
 * ReaScript Name: Copy Fx Paramters of the last focused FX to the clipboard
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.0
--]] --[[
 * Changelog:
 * v1.0 (2024-02-16)
 	+ Initial Release
--]] local EXT_SECTION = "tRoshan_copy_paste_fx_params"

local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")

function Msg(param)
    reaper.ShowConsoleMsg(tostring(param) .. "\n")
end

function clipboardIterator()
    local i = 0
    return function()
        i = i + 1

        local key = tostring(i)

        if reaper.HasExtState(EXT_SECTION, key) then
            return key
        end
    end
end

function clear()
    for key in clipboardIterator() do
        reaper.DeleteExtState(EXT_SECTION, key, false)
    end
end

function readClipboard()
    local params = {}
    local k = 1
    for key in clipboardIterator() do
        table.insert(params, k, reaper.GetExtState(EXT_SECTION, key))
        k = k + 1
    end

    return params
end

function Action()
    clear()
    retval, tracknumber, itemnumber, fxnumber = reaper.GetFocusedFX()
    track = reaper.GetTrack(0, tracknumber - 1)
    fx_name_retval, fx_name = reaper.TrackFX_GetFXName(track, fxnumber, "")
    reaper.SetExtState(EXT_SECTION, tostring(1), fx_name, false)

    count_params = reaper.TrackFX_GetNumParams(track, fxnumber)
    max_val = 0
    for k = 0, count_params - 1 do
        ret_val, min_val, max_val = reaper.TrackFX_GetParam(track, fxnumber, k)
        retval, buf = reaper.TrackFX_GetParamName(track, fxnumber, k, "")
        reaper.SetExtState(EXT_SECTION, tostring(k + 2), tostring(ret_val), false)
    end
    retval2, trackname = reaper.GetTrackName(track)
    local msg = "The settings from " .. fx_name .. "(" .. trackname .. ") have been copied"
    reaper.ShowMessageBox(msg, "Copy FX parameters", 0)
end -- function

Action()
