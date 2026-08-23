--[[
 * ReaScript Name: Video Scene Detect
 * Description: Configure scene detection (markers/regions, detector, threshold, colour, ...) then run it on the selected video items.
 * Author: tRoshan
 * License: GPL v3
 * REAPER: 7.x
 * Extensions: ReaImGui; requires the `scenedetect` CLI on PATH (https://www.scenedetect.com/download/, or pip install --upgrade scenedetect).
 * Version: 1.5
 * Provides: Functions/SceneDetect.lua
 * Changelog: Detect scenes across every selected video item instead of only the first
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
local pendingDetect = false

local cliInstalled = true
local checkedThisSession = false

-- Probing costs a Python process, so once the helper is found we remember it and stop looking.
local function checkInstallOnce()
    if checkedThisSession then
        return
    end
    checkedThisSession = true
    if r.GetExtState(EXT_SECTION, "cliFound") == "1" then
        return
    end
    cliInstalled = SceneDetect.isAvailable()
    if cliInstalled then
        r.SetExtState(EXT_SECTION, "cliFound", "1", true)
    end
end

-- ReaImGui has no open-URL call and CF_ShellExecute would pull in SWS, so shell out per platform.
local function openUrl(url)
    local system = r.GetOS()
    if system:match("^Win") then
        os.execute('start "" "' .. url .. '"')
    elseif system:match("OSX") or system:match("macOS") then
        os.execute('open "' .. url .. '"')
    else
        os.execute('xdg-open "' .. url .. '"')
    end
end

local function drawInstallHelp()
    r.ImGui_TextWrapped(ctx, "Scene detection needs PySceneDetect, which is not installed yet.")
    r.ImGui_Spacing(ctx)

    r.ImGui_Text(ctx, "Download it:")
    r.ImGui_SetNextItemWidth(ctx, 290)
    r.ImGui_InputText(ctx, "##url", SceneDetect.DOWNLOAD_URL, r.ImGui_InputTextFlags_ReadOnly())
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Open") then
        openUrl(SceneDetect.DOWNLOAD_URL)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Or, if you already have Python:")
    r.ImGui_SetNextItemWidth(ctx, 290)
    r.ImGui_InputText(ctx, "##pip", SceneDetect.INSTALL_COMMAND, r.ImGui_InputTextFlags_ReadOnly())

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Check again", 120, 0) then
        r.DeleteExtState(EXT_SECTION, "cliFound", true)
        checkedThisSession = false
        checkInstallOnce()
    end
end

local function drawControls()
    checkInstallOnce()
    if not cliInstalled then
        drawInstallHelp()
        return
    end
    local videos = SceneDetect.getSelectedVideos()
    if #videos == 1 then
        local path = SceneDetect.videoPath(videos[1])
        r.ImGui_Text(ctx, "Selected: " .. (path:match("[^/\\]+$") or path))
    elseif #videos > 1 then
        r.ImGui_Text(ctx, "Selected: " .. #videos .. " video items")
    else
        r.ImGui_TextColored(ctx, 0xE06060FF, "Select a video item.")
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

    -- Captured before the button: setting pendingDetect below would otherwise unbalance BeginDisabled.
    local disabled = #videos == 0 or pendingDetect
    if disabled then
        r.ImGui_BeginDisabled(ctx)
    end
    if r.ImGui_Button(ctx, "Detect", 120, 30) then
        saveOptions(opts)
        status = "Detecting scenes..."
        pendingDetect = true
    end
    if disabled then
        r.ImGui_EndDisabled(ctx)
    end

    if status ~= "" then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, status)
    end
end

local function runPendingDetect()
    pendingDetect = false
    local count, message, reason = SceneDetect.detect(opts)
    if count then
        status = string.format("Created %d %s.", count, opts.output)
        if message then
            status = status .. " " .. message
        end
    elseif reason == SceneDetect.ERR_NOT_INSTALLED then
        r.DeleteExtState(EXT_SECTION, "cliFound", true)
        cliInstalled = false
        status = ""
    else
        status = message
    end
end

local function loop()
    -- Run at the top of the next frame, once REAPER has drawn the frame announcing the scan.
    if pendingDetect then
        runPendingDetect()
    end
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
