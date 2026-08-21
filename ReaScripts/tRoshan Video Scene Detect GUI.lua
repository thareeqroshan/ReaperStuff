--[[
 * ReaScript Name: Video Scene Detect
 * Description: Configure scene detection (markers/regions, detector, threshold, colour, ...) then run it on the selected video item.
 * Author: tRoshan
 * License: GPL v3
 * REAPER: 7.x
 * Extensions: ReaImGui; requires the `scenedetect` CLI on PATH (https://www.scenedetect.com/download/, or pip install --upgrade scenedetect).
 * Version: 1.0.2
 * Provides: Functions/SceneDetect.lua
 * Changelog: Ship Functions/SceneDetect.lua with the package so a fresh install can load it
--]]

local info = debug.getinfo(1, 'S')
local scriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local SceneDetect = dofile(scriptPath .. 'Functions/SceneDetect.lua')

local r = reaper
local ctx = r.ImGui_CreateContext('Video Scene Detect')

local EXT_SECTION = "tRoshan_VideoSceneDetect"
local DETECTOR_LABELS = "Adaptive\0Content\0Threshold\0"
local DETECTOR_DEFAULT_THRESHOLD = {
    ["detect-adaptive"] = 3.0,
    ["detect-content"] = 27.0,
    ["detect-threshold"] = 12.0
}

local function detectorIndex(detector)
    for i, name in ipairs(SceneDetect.DETECTORS) do
        if name == detector then
            return i - 1
        end
    end
    return 0
end

-- ReaImGui ColorEdit3 uses 0xXXRRGGBB (RGB in the low 3 bytes), not 0xRRGGBBAA.
local function nativeToImgui(native)
    local rr, gg, bb = r.ColorFromNative(native & 0xFFFFFF)
    return (rr << 16) | (gg << 8) | bb
end

local function imguiToNative(col)
    local rr = (col >> 16) & 0xFF
    local gg = (col >> 8) & 0xFF
    local bb = col & 0xFF
    return r.ColorToNative(rr, gg, bb) | 0x1000000
end

local function saveOptions(o)
    r.SetExtState(EXT_SECTION, "output", o.output, true)
    r.SetExtState(EXT_SECTION, "detector", o.detector, true)
    r.SetExtState(EXT_SECTION, "threshold", tostring(o.threshold), true)
    r.SetExtState(EXT_SECTION, "minSceneLen", tostring(o.minSceneLen), true)
    r.SetExtState(EXT_SECTION, "namePrefix", o.namePrefix, true)
    r.SetExtState(EXT_SECTION, "color", tostring(o.color), true)
    r.SetExtState(EXT_SECTION, "clearExisting", o.clearExisting and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "useTimeSelection", o.useTimeSelection and "1" or "0", true)
end

local function loadOptions()
    local o = SceneDetect.defaultOptions()
    local function stored(key)
        local v = r.GetExtState(EXT_SECTION, key)
        if v == "" then
            return nil
        end
        return v
    end
    o.output = stored("output") or o.output
    o.detector = stored("detector") or o.detector
    o.threshold = tonumber(stored("threshold") or "") or o.threshold
    o.minSceneLen = tonumber(stored("minSceneLen") or "") or o.minSceneLen
    o.namePrefix = stored("namePrefix") or o.namePrefix
    o.color = tonumber(stored("color") or "") or o.color
    local clear = stored("clearExisting")
    if clear then
        o.clearExisting = clear == "1"
    end
    local timeSel = stored("useTimeSelection")
    if timeSel then
        o.useTimeSelection = timeSel == "1"
    end

    -- Show concrete values in the GUI even when the module defaults mean "use detector default".
    if o.threshold < 0 then
        o.threshold = DETECTOR_DEFAULT_THRESHOLD[o.detector] or 3.0
    end
    if o.minSceneLen <= 0 then
        o.minSceneLen = 0.6
    end
    return o
end

local opts = loadOptions()
local imguiColor = nativeToImgui(opts.color)
local status = ""

local function drawControls()
    local item, sourceOrErr, videoPath = SceneDetect.getSelectedVideo()
    if item then
        r.ImGui_Text(ctx, "Selected: " .. (videoPath:match("[^/\\]+$") or videoPath))
    else
        r.ImGui_TextColored(ctx, 0xE06060FF, sourceOrErr)
    end
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, "Output:")
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Regions", opts.output == SceneDetect.OUTPUT_REGIONS) then
        opts.output = SceneDetect.OUTPUT_REGIONS
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Markers", opts.output == SceneDetect.OUTPUT_MARKERS) then
        opts.output = SceneDetect.OUTPUT_MARKERS
    end

    r.ImGui_SetNextItemWidth(ctx, 160)
    local detChanged, detIdx = r.ImGui_Combo(ctx, "Detector", detectorIndex(opts.detector), DETECTOR_LABELS)
    if detChanged then
        opts.detector = SceneDetect.DETECTORS[detIdx + 1]
        opts.threshold = DETECTOR_DEFAULT_THRESHOLD[opts.detector] or opts.threshold
    end

    r.ImGui_SetNextItemWidth(ctx, 160)
    local thChanged, th = r.ImGui_InputDouble(ctx, "Threshold", opts.threshold)
    if thChanged then
        opts.threshold = math.max(0, th)
    end

    r.ImGui_SetNextItemWidth(ctx, 160)
    local mlChanged, ml = r.ImGui_InputDouble(ctx, "Min scene length (s)", opts.minSceneLen)
    if mlChanged then
        opts.minSceneLen = math.max(0, ml)
    end

    r.ImGui_SetNextItemWidth(ctx, 160)
    local npChanged, np = r.ImGui_InputText(ctx, "Name prefix", opts.namePrefix)
    if npChanged then
        opts.namePrefix = np
    end

    local colChanged, col = r.ImGui_ColorEdit3(ctx, "Colour", imguiColor, r.ImGui_ColorEditFlags_NoInputs())
    if colChanged then
        imguiColor = col
        opts.color = imguiToNative(col)
    end

    local _, clearVal = r.ImGui_Checkbox(ctx, "Clear existing scene markers/regions in range first", opts.clearExisting)
    opts.clearExisting = clearVal
    local _, tsVal = r.ImGui_Checkbox(ctx, "Scan only the time selection", opts.useTimeSelection)
    opts.useTimeSelection = tsVal

    r.ImGui_Separator(ctx)

    if not item then
        r.ImGui_BeginDisabled(ctx)
    end
    if r.ImGui_Button(ctx, "Detect", 120, 30) then
        saveOptions(opts)
        local count, detectErr = SceneDetect.detect(opts)
        if count then
            status = string.format("Created %d %s.", count, opts.output)
        else
            status = detectErr
        end
    end
    if not item then
        r.ImGui_EndDisabled(ctx)
    end

    if status ~= "" then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, status)
    end

    r.ImGui_Spacing(ctx)
    if r.ImGui_CollapsingHeader(ctx, "Installing the scenedetect CLI") then
        r.ImGui_TextWrapped(ctx, "Windows installer, no Python needed:")
        r.ImGui_Text(ctx, SceneDetect.DOWNLOAD_URL)
        if r.ImGui_Button(ctx, "Copy link") then
            r.ImGui_SetClipboardText(ctx, SceneDetect.DOWNLOAD_URL)
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, "Or, if you already have Python:")
        r.ImGui_Text(ctx, SceneDetect.INSTALL_COMMAND)
        if r.ImGui_Button(ctx, "Copy pip command") then
            r.ImGui_SetClipboardText(ctx, SceneDetect.INSTALL_COMMAND)
        end
    end
end

local function loop()
    r.ImGui_SetNextWindowSize(ctx, 440, 360, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Video Scene Detect', true)
    if visible then
        drawControls()
        r.ImGui_End(ctx)
    end
    if open then
        r.defer(loop)
    else
        saveOptions(opts)
    end
end

r.defer(loop)
