--[[
 * ReaScript Name: Item Properties Randomizer
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Version: 1.0
--]] --[[
 * Changelog:
 * v1.0 (2024-11-19)
 	+ Initial Release
--]] local info = debug.getinfo(1, 'S');
ScriptPath = info.source:match [[^@?(.*[\/])[^\/]-$]]
-- dofile(ScriptPath .. 'Functions/Theme.lua') -- Functions for using the markov in reaper

function msg(m)
    reaper.ShowConsoleMsg(tostring(m) .. "\n")
end

-- function to check if a mediaitem has pan take envelope
function hasPanTakeEnvelope(item)
    local take = reaper.GetActiveTake(item)
    local takeEnvelope = reaper.GetTakeEnvelopeByName(take, "PAN")
    if takeEnvelope ~= nil then
        return true
    else
        return false
    end
end

-- function to create pan take envelope
function createPanTakeEnvelope(item)
    local take = reaper.GetActiveTake(item)
    local takeEnvelope = reaper.GetTakeEnvelopeByName(take, "Pan")
    if takeEnvelope == nil then
        reaper.InsertTakeEnvelopePoint(take, -1, 0, 0, 0, 0, true)
        reaper.InsertTakeEnvelopePoint(take, -1, 1, 0, 0, 0, true)
        reaper.Envelope_SortPoints(takeEnvelope)
    end
    return takeEnvelope
end

function shiftTakePan(item, shift)
    -- get all the points in the take pan envelope and shift them by shift
    local take = reaper.GetActiveTake(item)
    local takeEnvelope = reaper.GetTakeEnvelopeByName(take, "Pan")
    -- msg(takeEnvelope)
    local pointCount = reaper.CountEnvelopePoints(takeEnvelope)
    for i = 0, pointCount - 1 do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(takeEnvelope, i)
        -- clamp the pan value to -1 and 1
        new_value = value + shift
        if value + shift > 1 then
            new_value = 1
        end

        reaper.SetEnvelopePoint(takeEnvelope, i, time, new_value, shape, tension, selected, true)
    end
end

function decibel_to_double(decibel)
    return 10 ^ (decibel / 20)
end

function double_to_decibel(double)
    return 20 * math.log(double, 10)
end

function randomFloat(lower, greater)
    return lower + math.random() * (greater - lower)
end

local function randomize_properties()
    -- use the data from the drag sliders to randomize the properties
    reaper.Undo_BeginBlock()
    local count = reaper.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)

        if vol_toggle then
            offset = randomFloat(v_current_min, v_current_max)
            volume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
            volume = double_to_decibel(volume) + offset
            -- msg(decibel_to_double(volume))
            reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", decibel_to_double(volume))
        end

        if pan_toggle then
            reaper.Main_OnCommandEx(reaper.NamedCommandLookup("_S&M_TAKEENV2"), 0)
            shiftTakePan(item, randomFloat(p_current_min, p_current_max))
        end

        if pitch_toggle then
            offset = randomFloat(pitch_current_min, pitch_current_max)
            local pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH") + offset
            reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch)
        end

        if rate_toggle then
            offset = randomFloat(rate_current_min, rate_current_max)
            local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") * offset
            reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
            item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            item_len = item_len / offset
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_len)
        end
        reaper.UpdateItemInProject(item)
        reaper.UpdateArrange()
    end
    reaper.Undo_EndBlock("tRoshan Randomise Properties on Selected Items", -1)
end

vol_toggle, pan_toggle, pitch_toggle, rate_toggle = true, true, true, true
vol, pan, pitch, rate = 1.0, 0.0, 0.0, 1.0
v_current_min, v_current_max = -3.0, 3.0
p_current_min, p_current_max = -1.0, 1.0
pitch_current_min, pitch_current_max = -4.0, 4.0
rate_current_min, rate_current_max = 0.5, 2.0

local vol_range, pan_range, pitch_range, rate_range = {-12, 12}, {-1.0, 1.0}, {-12.0, 12.0}, {0.25, 4.0}
ctx = reaper.ImGui_CreateContext('My script', reaper.ImGui_ConfigFlags_DockingEnable())
height, width = 500, 170

demo = dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/ReaImGui_Demo.lua')
show_style_editor = false
SetDock = nil
local function loop()
    -- PushTheme(ctx)
    -- if show_style_editor then
    --     demo.PushStyle(ctx)
    --     demo.ShowDemoWindow(ctx)
    -- end

    if SetDock then
        reaper.ImGui_SetNextWindowDockID(ctx, SetDock)
        if SetDock == 0 then
            reaper.ImGui_SetNextWindowSize(ctx, height, width)
        end
        SetDock = nil
    end

    local visible, open = reaper.ImGui_Begin(ctx, 'Randomise Item Properties', true,
        reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_MenuBar())
    if visible then
        local retval_dock = reaper.ImGui_IsWindowDocked(ctx)
        local dock_text = retval_dock and 'Undock' or 'Dock'

        if reaper.ImGui_BeginMenuBar(ctx) then
            if reaper.ImGui_MenuItem(ctx, dock_text) then
                if retval_dock then
                    SetDock = 0
                else
                    SetDock = -3
                end
            end
            reaper.ImGui_EndMenuBar(ctx)
        end

        margin_x = 80
        _, vol_toggle = reaper.ImGui_Checkbox(ctx, "Vol", vol_toggle)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, margin_x)
        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetWindowWidth(ctx) - 100)
        if v_current_min > v_current_max then
            v_current_min = v_current_max
        elseif v_current_max < v_current_min then
            v_current_min = v_current_max
        end
        _, v_current_min, v_current_max = reaper.ImGui_SliderDouble2(ctx, "##VolumeRange", v_current_min, v_current_max,
            vol_range[1], vol_range[2], "%.2f db")

        _, pan_toggle = reaper.ImGui_Checkbox(ctx, "Pan", pan_toggle)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, margin_x)
        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetWindowWidth(ctx) - 100)
        _, p_current_min, p_current_max = reaper.ImGui_SliderDouble2(ctx, "##PanRange", p_current_min, p_current_max,
            pan_range[1], pan_range[2], "%.2f")
        _, pitch_toggle = reaper.ImGui_Checkbox(ctx, "Pitch", pitch_toggle)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, margin_x)
        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetWindowWidth(ctx) - 100)
        _, pitch_current_min, pitch_current_max = reaper.ImGui_SliderDouble2(ctx, "##PitchRange", pitch_current_min,
            pitch_current_max, pitch_range[1], pitch_range[2], "%.2f semitones")
        _, rate_toggle = reaper.ImGui_Checkbox(ctx, "Rate", rate_toggle)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, margin_x)
        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetWindowWidth(ctx) - 100)
        _, rate_current_min, rate_current_max = reaper.ImGui_SliderDouble2(ctx, "##RateRange", rate_current_min,
            rate_current_max, rate_range[1], rate_range[2], "%.2f x")

        reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetWindowWidth(ctx) / 2 - 50, 140)

        if reaper.ImGui_Button(ctx, "Randomize", 100, 0) then
            randomize_properties()
        end
        reaper.ImGui_End(ctx)
    end
    -- PopTheme(ctx)
    -- if show_style_editor then
    --     demo.PopStyle(ctx)
    -- end
    if open then
        reaper.defer(loop)
    end
end
reaper.ImGui_SetNextWindowDockID(ctx, 0)
reaper.ImGui_SetNextWindowSize(ctx, height, width, reaper.ImGui_Cond_Always())
reaper.defer(loop)
