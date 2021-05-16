local EXT_SECTION = "tRoshan_copy_paste_fx_params"

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
  local params = readClipboard()

  if #params < 1 then
    reaper.MB("No values in clipboard", script_name, 0)
    return
  end

  reaper.Undo_BeginBlock()
  retval, tracknumber, itemnumber, fxnumber = reaper.GetFocusedFX()
  track = reaper.GetTrack(0, tracknumber - 1)
  count_params = reaper.TrackFX_GetNumParams(track, fxnumber)
  -- for k = 0, count_params - 1 do

  --   param_retval, minval, maxval = reaper.TrackFX_GetParam(track, fxnumber, k)
  --   reaper.TrackFX_SetParam(track, fxnumber, k, param_retval + 0.1)
  --   reaper.TrackFX_SetParam(track, fxnumber, k, param_retval)
  --   -- envelope = reaper.GetFXEnvelope( track, fxnumber, k, true )
  -- end

  fx_name_retval, fx_name = reaper.TrackFX_GetFXName(track, fxnumber, "")
  if fx_name == params[1] then
    table.remove(params, 1)

    for key, value in pairs(params) do
      --Msg(key)
      reaper.TrackFX_SetParam(track, fxnumber, tonumber(key - 1), tonumber(value))
    end
  end
  reaper.Undo_EndBlock(script_name, -1)
  retval2, trackname = reaper.GetTrackName(track)
  local msg = "The settings have been pasted to " .. fx_name .. "(" .. trackname .. ")"
  reaper.ShowMessageBox(msg, "Paste FX parameters", 0)
end

reaper.PreventUIRefresh(1)
Action()

reaper.PreventUIRefresh(-1)
