-- @noindex
--[[
 * ReaScript Name: tRoshan Video Scene Detect (shared module)
 * Description: Scene detection via the PySceneDetect CLI, used by tRoshan Video Scene Detect GUI.
 * Author: tRoshan
 * License: GPL v3
 * REAPER: 7.x
--]]

local r = reaper
local M = {}

local EPSILON = 1e-6

M.OUTPUT_REGIONS = "regions"
M.OUTPUT_MARKERS = "markers"
M.DETECTORS = {"detect-adaptive", "detect-content", "detect-threshold"}

-- The Windows installer needs no Python; the pip package is for people who already have it.
M.DOWNLOAD_URL = "https://www.scenedetect.com/download/"
M.INSTALL_COMMAND = "pip install --upgrade scenedetect"

-- Returned by M.detect so callers can offer install help instead of showing a raw error.
M.ERR_NOT_INSTALLED = "notinstalled"

local function quote(path)
    return '"' .. path .. '"'
end

local function timeArg(seconds)
    return string.format("%.3f", seconds) .. "s"
end

-- Run a command line. Returns exitCode, output, or nil if the process could not be started.
local function exec(command)
    local result = r.ExecProcess(command, 0)
    if not result then
        return nil
    end
    local exitCode = tonumber(result:match("^(.-)\n"))
    local output = result:match("^.-\n(.*)$") or ""
    return exitCode, output
end

-- Filename without directory or extension, e.g. "C:\clips\intro.mp4" -> "intro".
local function baseName(path)
    local fileName = path:match("[^/\\]+$") or path
    return (fileName:gsub("%.[^%.]+$", ""))
end

-- PySceneDetect list-scenes fields never contain commas, so a simple split is safe.
local function splitCSVLine(line)
    local fields = {}
    for value in string.gmatch(line, "([^,]+)") do
        fields[#fields + 1] = value
    end
    return fields
end

-- Read a PySceneDetect "*-Scenes.csv" file into { startSeconds, endSeconds } entries.
local function readScenes(csvPath)
    local file = io.open(csvPath, "r")
    if not file then
        return nil
    end
    local scenes = {}
    local lineNumber = 0
    for line in file:lines() do
        lineNumber = lineNumber + 1
        -- Line 1 is the "Timecode List" row, line 2 is the column header row.
        if lineNumber > 2 then
            local fields = splitCSVLine(line)
            scenes[#scenes + 1] = {
                startSeconds = tonumber(fields[4]),
                endSeconds = tonumber(fields[7])
            }
        end
    end
    file:close()
    return scenes
end

-- Delete "Scene" markers and regions whose start falls inside the given range.
local function deleteScenesInRange(prefix, rangeStart, rangeEnd)
    local total = r.CountProjectMarkers(0)
    for i = total - 1, 0, -1 do
        local _, _, pos, _, name = r.EnumProjectMarkers(i)
        local isScene = name:sub(1, #prefix) == prefix
        if isScene and pos >= rangeStart - EPSILON and pos <= rangeEnd + EPSILON then
            r.DeleteProjectMarkerByIndex(0, i)
        end
    end
end

-- Create one marker or region per scene, clipped to the target range.
local function createFromScenes(scenes, options, rangeStart, rangeEnd)
    local wantRegion = options.output == M.OUTPUT_REGIONS
    local created = 0
    for _, scene in ipairs(scenes) do
        if scene.startPos then
            -- Clamp rather than skip, so a trim landing mid-scene still yields a scene for what is visible.
            local startPos = math.max(scene.startPos, rangeStart)
            local endPos = math.min(scene.endPos, rangeEnd)
            if endPos > startPos + EPSILON then
                created = created + 1
                local name = options.namePrefix .. created
                if wantRegion then
                    r.AddProjectMarker2(0, true, startPos, endPos, name, -1, options.color)
                else
                    r.AddProjectMarker2(0, false, startPos, 0, name, -1, options.color)
                end
            end
        end
    end
    return created
end

function M.defaultOptions()
    return {
        output = M.OUTPUT_REGIONS,
        detector = "detect-adaptive",
        threshold = -1, -- < 0 = use the detector's own default
        minSceneLen = 0, -- seconds; <= 0 = use the detector's own default
        namePrefix = "Scene ",
        color = r.ColorToNative(90, 160, 230) | 0x1000000,
        clearExisting = true,
        useTimeSelection = false
    }
end

-- Returns item, source, videoPath, or nil + errorMessage.
function M.getSelectedVideo()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then
        return nil, "No media item selected."
    end
    local take = r.GetActiveTake(item)
    if not take then
        return nil, "The selected item has no active take."
    end
    local source = r.GetMediaItemTake_Source(take)
    if r.GetMediaSourceType(source, "") ~= "VIDEO" then
        return nil, "The selected item's active take is not a video source."
    end
    return item, source, r.GetMediaSourceFileName(source, "")
end

function M.isAvailable()
    return exec("scenedetect version") ~= nil
end

-- Detect scenes for the selected video item and create markers/regions.
-- Returns createdCount, or nil + errorMessage.
function M.detect(options)
    local item, sourceOrErr, videoPath = M.getSelectedVideo()
    if not item then
        return nil, sourceOrErr
    end
    if not M.isAvailable() then
        return nil, 'Could not run "scenedetect". Install it from ' .. M.DOWNLOAD_URL ..
            ' or, with Python installed, run: ' .. M.INSTALL_COMMAND, M.ERR_NOT_INSTALLED
    end

    local itemStart = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local itemEnd = itemStart + r.GetMediaItemInfo_Value(item, "D_LENGTH")

    -- scenedetect reports positions inside the source file, so the take's trim and rate must be undone.
    local take = r.GetActiveTake(item)
    local startOffset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local playRate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

    local rangeStart, rangeEnd = itemStart, itemEnd
    if options.useTimeSelection then
        local selStart, selEnd = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if selEnd <= selStart then
            return nil, "No time selection. Make one over the item, or turn that option off."
        end
        rangeStart = math.max(itemStart, selStart)
        rangeEnd = math.min(itemEnd, selEnd)
        if rangeEnd <= rangeStart then
            return nil, "The time selection does not overlap the selected item."
        end
    end

    local separator = package.config:sub(1, 1)
    local outputDir = os.getenv("TEMP") or os.getenv("TMPDIR") or r.GetProjectPath("")
    local name = baseName(videoPath)
    local csvPath = outputDir .. separator .. name .. "-Scenes.csv"

    -- Scan only the stretch of the source the item uses. Seeking does not rebase the reported
    -- timestamps, so they stay absolute and the mapping above still holds.
    local sourceStart = math.max(0, startOffset + (rangeStart - itemStart) * playRate)
    local sourceEnd = startOffset + (rangeEnd - itemStart) * playRate

    local parts = {"scenedetect", "-i", quote(videoPath), "-o", quote(outputDir),
                   "time", "-s", timeArg(sourceStart), "-e", timeArg(sourceEnd),
                   options.detector}
    if options.threshold and options.threshold >= 0 then
        parts[#parts + 1] = "-t"
        parts[#parts + 1] = tostring(options.threshold)
    end
    if options.minSceneLen and options.minSceneLen > 0 then
        parts[#parts + 1] = "-m"
        parts[#parts + 1] = tostring(options.minSceneLen) .. "s"
    end
    parts[#parts + 1] = "list-scenes"
    parts[#parts + 1] = "-q"

    local exitCode, output = exec(table.concat(parts, " "))
    if exitCode == nil then
        return nil, "Failed to launch scenedetect."
    end
    if exitCode ~= 0 then
        return nil, "scenedetect exited with code " .. exitCode .. ":\n" .. output
    end

    local scenes = readScenes(csvPath)
    os.remove(csvPath) -- don't leave the CLI's CSV behind in the temp folder
    if not scenes then
        return nil, "Could not read the scene list at:\n    " .. csvPath
    end
    if #scenes == 0 then
        return nil, "No scenes were detected."
    end

    for _, scene in ipairs(scenes) do
        if scene.startSeconds and scene.endSeconds then
            scene.startPos = itemStart + (scene.startSeconds - startOffset) / playRate
            scene.endPos = itemStart + (scene.endSeconds - startOffset) / playRate
        end
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    if options.clearExisting then
        deleteScenesInRange(options.namePrefix, rangeStart, rangeEnd)
    end
    local created = createFromScenes(scenes, options, rangeStart, rangeEnd)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Video Scene Detect: create " .. created .. " " .. options.output, -1)

    return created
end

return M
