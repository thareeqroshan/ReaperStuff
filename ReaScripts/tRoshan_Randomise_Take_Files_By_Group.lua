--[[
 * ReaScript Name: Randomise Take Files by Group
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: ReaImGui (0.9.2+)
 * Version: 1.0
--]]
--[[
 * Changelog:
 * v1.0 (2026-08-04)
    + Initial Release
--]]

-- Randomises ONLY the active take's source file on the selected items.
-- Items are grouped by asset name (trailing "-NNN" / "_NN" and the file
-- extension are removed), so e.g. sfx_passive_jellybunny_jump-001,
-- -002, -003 all fall under "sfx_passive_jellybunny_jump".
-- Item/take volume, pan, pitch, rate, FX, position and length are left
-- untouched. Reversed / section takes are skipped so their state is kept.

local SEP = package.config:sub(1, 1)

local AUDIO_EXT = {
    wav = true, aif = true, aiff = true, aifc = true, flac = true,
    ogg = true, oga = true, opus = true, mp3 = true, m4a = true,
    mp4 = true, wv = true, w64 = true, caf = true, aac = true,
}

local ctx = reaper.ImGui_CreateContext('Randomise Take Files by Group')

local pool_mode = 0      -- 0 = selected items, 1 = disk folder
local method_mode = 0    -- 0 = random (repeats allowed), 1 = shuffle (no repeats)
local avoid_current = true
local groups = {}        -- ordered array of { name, items, dirs, variations }
local group_checked = {} -- name -> bool
local last_signature = nil
local status_text = ""

math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000) % 100000)
math.random(); math.random(); math.random()

local function normalize_path(p)
    if not p or p == "" then return "" end
    p = p:gsub("/", "\\")
    if SEP == "\\" then p = p:lower() end
    return p
end

-- Strip the extension and a trailing variation index (optional -/_ then digits).
local function name_to_group(filename)
    local name = filename:gsub("%.%w+$", "")
    local base = name:gsub("[-_]?%d+$", "")
    if base ~= "" then name = base end -- keep purely-numeric names (e.g. "808") intact
    return name
end

local function source_file_path(take)
    local src = reaper.GetMediaItemTake_Source(take)
    if not src then return nil end
    if reaper.GetMediaSourceType(src, "") == "SECTION" then return nil end
    local path = reaper.GetMediaSourceFileName(src, "")
    if not path or path == "" then return nil end
    return path
end

local function scan_selection()
    groups = {}
    local by_name = {}
    local count = reaper.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take and not reaper.TakeIsMIDI(take) then
            local path = source_file_path(take)
            if path then
                local filename = path:match("[^/\\]+$") or path
                local gname = name_to_group(filename)
                local g = by_name[gname]
                if not g then
                    g = { name = gname, items = {}, dirs = {} }
                    by_name[gname] = g
                    groups[#groups + 1] = g
                end
                g.items[#g.items + 1] = { item = item, take = take, path = path, key = normalize_path(path) }
                local dir = path:match("^(.*)[/\\][^/\\]*$")
                if dir then g.dirs[normalize_path(dir)] = dir end
            end
        end
    end

    table.sort(groups, function(a, b) return a.name:lower() < b.name:lower() end)

    local kept = {}
    for _, g in ipairs(groups) do
        local seen = {}
        local distinct = 0
        for _, it in ipairs(g.items) do
            if not seen[it.key] then
                seen[it.key] = true
                distinct = distinct + 1
            end
        end
        g.variations = distinct
        if group_checked[g.name] == nil then
            kept[g.name] = true
        else
            kept[g.name] = group_checked[g.name]
        end
    end
    group_checked = kept
end

local function selection_signature()
    local count = reaper.CountSelectedMediaItems(0)
    local parts = { tostring(count) }
    for i = 0, count - 1 do
        parts[#parts + 1] = tostring(reaper.GetSelectedMediaItem(0, i))
    end
    return table.concat(parts, "|")
end

-- Distinct audio files on disk that belong to the same group.
local function disk_variations(group)
    local ordered = {}
    local seen = {}
    for _, dir in pairs(group.dirs) do
        local i = 0
        while true do
            local f = reaper.EnumerateFiles(dir, i)
            if not f or f == "" then break end
            i = i + 1
            local ext = f:match("%.(%w+)$")
            if ext and AUDIO_EXT[ext:lower()] and name_to_group(f) == group.name then
                local full = dir .. SEP .. f
                local key = normalize_path(full)
                if not seen[key] then
                    seen[key] = true
                    ordered[#ordered + 1] = full
                end
            end
        end
    end
    return ordered
end

local function build_candidates(group)
    if pool_mode == 1 then
        return disk_variations(group)
    end

    -- Shuffle keeps the exact multiset on the timeline so it is a true
    -- permutation; Random uses the distinct set so each variation is equally
    -- likely.
    if method_mode == 1 then
        local list = {}
        for _, it in ipairs(group.items) do
            list[#list + 1] = it.path
        end
        return list
    end

    local list, seen = {}, {}
    for _, it in ipairs(group.items) do
        if not seen[it.key] then
            seen[it.key] = true
            list[#list + 1] = it.path
        end
    end
    return list
end

local function distinct_count(list)
    local seen = {}
    local n = 0
    for _, p in ipairs(list) do
        local k = normalize_path(p)
        if not seen[k] then
            seen[k] = true
            n = n + 1
        end
    end
    return n
end

local function shuffled_copy(list)
    local c = {}
    for i = 1, #list do c[i] = list[i] end
    for i = #c, 2, -1 do
        local j = math.random(i)
        c[i], c[j] = c[j], c[i]
    end
    return c
end

-- Best-effort: stop an item from being handed back the file it already has.
local function avoid_fixed_points(items, assign)
    for i = 1, #items do
        if normalize_path(assign[i]) == items[i].key then
            for j = 1, #items do
                if j ~= i
                    and normalize_path(assign[j]) ~= items[i].key
                    and normalize_path(assign[i]) ~= items[j].key then
                    assign[i], assign[j] = assign[j], assign[i]
                    break
                end
            end
        end
    end
end

local function assignments_for(group)
    local candidates = build_candidates(group)
    if #candidates == 0 then return nil end

    local can_avoid = avoid_current and distinct_count(candidates) >= 2
    local assign = {}

    if method_mode == 0 then
        for idx, it in ipairs(group.items) do
            local pick
            if #candidates == 1 then
                pick = candidates[1]
            else
                repeat
                    pick = candidates[math.random(#candidates)]
                until (not can_avoid) or normalize_path(pick) ~= it.key
            end
            assign[idx] = pick
        end
    else
        local bag = {}
        for idx = 1, #group.items do
            if #bag == 0 then bag = shuffled_copy(candidates) end
            assign[idx] = table.remove(bag)
        end
        if can_avoid then avoid_fixed_points(group.items, assign) end
    end

    return assign
end

-- Mirror the new file name onto the take, keeping its current extension style.
local function rename_take_to_source(take, oldpath, newpath)
    local old_file = oldpath:match("[^/\\]+$") or oldpath
    local new_file = newpath:match("[^/\\]+$") or newpath
    local _, cur = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    local newname = new_file
    if cur == old_file:gsub("%.%w+$", "") then
        newname = new_file:gsub("%.%w+$", "")
    end
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", newname, true)
end

local function do_randomise()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local changed_items = 0
    local changed_groups = 0
    for _, g in ipairs(groups) do
        if group_checked[g.name] then
            local assign = assignments_for(g)
            if assign then
                changed_groups = changed_groups + 1
                for idx, it in ipairs(g.items) do
                    local newpath = assign[idx]
                    if normalize_path(newpath) ~= it.key then
                        local newsrc = reaper.PCM_Source_CreateFromFile(newpath)
                        if newsrc then
                            reaper.SetMediaItemTake_Source(it.take, newsrc)
                            rename_take_to_source(it.take, it.path, newpath)
                            reaper.UpdateItemInProject(it.item)
                            changed_items = changed_items + 1
                        end
                    end
                end
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("tRoshan Randomise Take Files by Group", -1)

    status_text = string.format("Randomised %d group(s), changed %d item(s).", changed_groups, changed_items)
    last_signature = nil -- force a rescan so the list reflects the new files
end

local function draw_options()
    reaper.ImGui_Text(ctx, "Candidate files:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Selected items", pool_mode == 0) then pool_mode = 0 end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Disk folder", pool_mode == 1) then pool_mode = 1 end

    reaper.ImGui_Text(ctx, "Method:         ")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Random", method_mode == 0) then method_mode = 0 end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Shuffle", method_mode == 1) then method_mode = 1 end

    local _, av = reaper.ImGui_Checkbox(ctx, "Avoid keeping current file", avoid_current)
    avoid_current = av
end

local function draw_group_list()
    if #groups == 0 then
        reaper.ImGui_TextWrapped(ctx, "No selected items with audio takes. Select some items and they will appear here.")
        return
    end
    if reaper.ImGui_BeginChild(ctx, "groups", 0, 220, reaper.ImGui_ChildFlags_Borders()) then
        for _, g in ipairs(groups) do
            local label = string.format("%s  (%d items, %d variations)##%s", g.name, #g.items, g.variations, g.name)
            local _, chk = reaper.ImGui_Checkbox(ctx, label, group_checked[g.name])
            group_checked[g.name] = chk
        end
        reaper.ImGui_EndChild(ctx)
    end
end

local function loop()
    local sig = selection_signature()
    if sig ~= last_signature then
        last_signature = sig
        scan_selection()
    end

    reaper.ImGui_SetNextWindowSize(ctx, 460, 470, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'Randomise Take Files by Group', true)
    if visible then
        draw_options()
        reaper.ImGui_Separator(ctx)

        if reaper.ImGui_Button(ctx, "Select all") then
            for _, g in ipairs(groups) do group_checked[g.name] = true end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Select none") then
            for _, g in ipairs(groups) do group_checked[g.name] = false end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Refresh") then
            last_signature = nil
        end

        draw_group_list()
        reaper.ImGui_Separator(ctx)

        local any_selected = false
        for _, g in ipairs(groups) do
            if group_checked[g.name] then
                any_selected = true
                break
            end
        end

        if not any_selected then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Randomise", 120, 30) then do_randomise() end
        if not any_selected then reaper.ImGui_EndDisabled(ctx) end

        if status_text ~= "" then
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextWrapped(ctx, status_text)
        end

        reaper.ImGui_End(ctx)
    end

    if open then reaper.defer(loop) end
end

reaper.defer(loop)
