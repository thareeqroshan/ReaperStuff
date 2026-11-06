-- @noindex

local r = reaper
local BatchRename = {}

local function default_options()
    return {
        replace_name = false, name = '', find = '', replacement = '',
        prefix = '', suffix = '', numbering = false,
        start = 1, digits = 2, separator = '_',
    }
end

local function rename(name, index, options)
    if options.replace_name then name = options.name end
    if options.find ~= '' then
        local parts = {}
        local position = 1
        while true do
            local first, last = name:find(options.find, position, true)
            if not first then break end
            parts[#parts + 1] = name:sub(position, first - 1)
            parts[#parts + 1] = options.replacement
            position = last + 1
        end
        parts[#parts + 1] = name:sub(position)
        name = table.concat(parts)
    end
    name = options.prefix .. name
    if options.numbering then
        name = name .. options.separator .. string.format('%0' .. options.digits .. 'd', options.start + index - 1)
    end
    return name .. options.suffix
end

function BatchRename.show(title, kind, selected, set_name, refresh)
    if not r.ImGui_CreateContext then
        r.ShowMessageBox('Please install ReaImGui through ReaPack, then run this script again.', title, 0)
        return
    end

    local ctx = r.ImGui_CreateContext(title)
    local options = default_options()
    local status = ''

    local function apply(project, entries)
        local renamed = 0
        r.Undo_BeginBlock2(project)
        local success, message = pcall(function()
            for _, entry in ipairs(entries) do
                if entry.new_name ~= entry.name then
                    if not set_name(project, entry.target, entry.new_name) then
                        error('Could not rename ' .. kind:lower() .. ' ' .. entry.number)
                    end
                    renamed = renamed + 1
                end
            end
        end)
        r.Undo_EndBlock2(project, title, -1)
        refresh()
        status = string.format('Renamed %d %s(s).', renamed, kind:lower())
        if not success then
            r.ShowMessageBox(status .. '\n' .. tostring(message) .. '\nUndo to revert this batch.', title, 0)
        end
    end

    local function text_field(label, key)
        r.ImGui_Text(ctx, label)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed
        changed, options[key] = r.ImGui_InputText(ctx, '##' .. key, options[key])
    end

    local function field_pair(id, first_label, first_key, second_label, second_key)
        if r.ImGui_BeginTable(ctx, id, 2, r.ImGui_TableFlags_SizingStretchSame()) then
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            text_field(first_label, first_key)
            r.ImGui_TableSetColumnIndex(ctx, 1)
            text_field(second_label, second_key)
            r.ImGui_EndTable(ctx)
        end
    end

    local function draw_options()
        local changed
        changed, options.replace_name = r.ImGui_Checkbox(ctx, 'Replace entire name', options.replace_name)
        r.ImGui_SameLine(ctx)
        r.ImGui_BeginDisabled(ctx, not options.replace_name)
        r.ImGui_SetNextItemWidth(ctx, -1)
        changed, options.name = r.ImGui_InputText(ctx, '##name', options.name)
        r.ImGui_EndDisabled(ctx)

        field_pair('Find and replace', 'Find', 'find', 'Replace with', 'replacement')
        field_pair('Affixes', 'Prefix', 'prefix', 'Suffix', 'suffix')

        changed, options.numbering = r.ImGui_Checkbox(ctx, 'Numbering', options.numbering)
        if options.numbering and r.ImGui_BeginTable(ctx, 'Numbering options', 3, r.ImGui_TableFlags_SizingStretchSame()) then
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_Text(ctx, 'Start')
            r.ImGui_SetNextItemWidth(ctx, -1)
            changed, options.start = r.ImGui_InputInt(ctx, '##start', options.start)
            options.start = math.max(0, math.min(1000000000, options.start))
            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_Text(ctx, 'Minimum digits')
            r.ImGui_SetNextItemWidth(ctx, -1)
            changed, options.digits = r.ImGui_InputInt(ctx, '##digits', options.digits)
            options.digits = math.max(1, math.min(10, options.digits))
            r.ImGui_TableSetColumnIndex(ctx, 2)
            text_field('Separator', 'separator')
            r.ImGui_EndTable(ctx)
        end
    end

    local function draw_preview(entries)
        local _, available = r.ImGui_GetContentRegionAvail(ctx)
        local footer = r.ImGui_GetFrameHeightWithSpacing(ctx) * 2 + 8
        local flags = r.ImGui_TableFlags_BordersInnerH() | r.ImGui_TableFlags_RowBg()
            | r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_ScrollY()
        if r.ImGui_BeginTable(ctx, 'Preview', 3, flags, 0, math.max(60, available - footer)) then
            r.ImGui_TableSetupColumn(ctx, kind, r.ImGui_TableColumnFlags_WidthFixed(), 54)
            r.ImGui_TableSetupColumn(ctx, 'Current name')
            r.ImGui_TableSetupColumn(ctx, 'New name')
            r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
            r.ImGui_TableHeadersRow(ctx)
            for _, entry in ipairs(entries) do
                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_Text(ctx, string.format('%d', entry.number))
                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_TextWrapped(ctx, entry.name == '' and '(empty)' or entry.name)
                r.ImGui_TableSetColumnIndex(ctx, 2)
                if entry.new_name == entry.name then r.ImGui_BeginDisabled(ctx) end
                r.ImGui_TextWrapped(ctx, entry.new_name == '' and '(empty)' or entry.new_name)
                if entry.new_name == entry.name then r.ImGui_EndDisabled(ctx) end
            end
            r.ImGui_EndTable(ctx)
        end
    end

    local function loop()
        r.ImGui_SetNextWindowSize(ctx, 740, 540, r.ImGui_Cond_FirstUseEver())
        r.ImGui_SetNextWindowSizeConstraints(ctx, 540, 460, 16384, 16384)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 16, 14)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 5)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 8, 4)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
        local visible, open = r.ImGui_Begin(ctx, title, true)
        if visible then
            draw_options()
            local project = r.EnumProjects(-1)
            local entries = selected(project)
            local changes = 0
            for index, entry in ipairs(entries) do
                entry.new_name = rename(entry.name, index, options)
                if entry.new_name ~= entry.name then changes = changes + 1 end
            end
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, string.format('%d %ss selected    %d changes', #entries, kind:lower(), changes))
            draw_preview(entries)

            r.ImGui_BeginDisabled(ctx, changes == 0)
            if r.ImGui_Button(ctx, 'Apply', 96, 0) then apply(project, entries) end
            r.ImGui_EndDisabled(ctx)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Reset', 72, 0) then
                options = default_options()
                status = ''
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Close', 72, 0) then open = false end
            r.ImGui_TextDisabled(ctx, status)
            r.ImGui_End(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 4)
        if open then r.defer(loop) end
    end

    r.defer(loop)
end

return BatchRename