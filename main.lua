local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local Dispatcher = require("dispatcher")
local gettext = require("i18n")
local T = require("ffi/util").template

local PageGrid = require("pagegrid")

local function _(msgid)
    return gettext.pgettext("FullTextUnderline", msgid)
end

local function formatSignedValue(value)
    if value > 0 then
        return "+" .. value
    end
    return tostring(value)
end

local DOC_SETTING_KEY = "fulltext_underline_page_grid_v5"
local PREVIOUS_SETTING_KEY = "fulltext_underline_v4"
local GLOBAL_DEFAULTS_KEY = "fulltextunderline_global_defaults"

local DEFAULT_SETTINGS = {
    enabled = true,
    style = "dashed",
    line_mode = "full",
    line_length_adjust = 0,
    line_position = 0,
    line_width_level = 1,
    dash_length = 8,
    gap_length = 4,
    include_headings = false,
    settings_version = 16,
}

local VALID_STYLE = { solid = true, dashed = true, dotted = true }
local VALID_LINE_MODE = { full = true, text = true }
local POSITION_MIN, POSITION_MAX = -10, 10
local LENGTH_ADJUST_MIN, LENGTH_ADJUST_MAX = -20, 20
local LINE_WIDTH_MIN, LINE_WIDTH_MAX = 1, 6
local PROFILE_ACTIONS = {
    { name = "fulltextunderline_enabled", field = "enabled" },
    { name = "fulltextunderline_style", field = "style" },
    { name = "fulltextunderline_line_mode", field = "line_mode" },
    {
        name = "fulltextunderline_line_length_adjust",
        field = "line_length_adjust",
    },
    { name = "fulltextunderline_line_position", field = "line_position" },
    {
        name = "fulltextunderline_line_width_level",
        field = "line_width_level",
    },
    { name = "fulltextunderline_include_headings", field = "include_headings" },
}

local FullTextUnderline = WidgetContainer:extend{
    name = "fulltextunderline",
    is_doc_only = true,
    supported = false,
}

local function normalizeInteger(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

local function normalizeSettings(settings)
    local normalized = {
        enabled = DEFAULT_SETTINGS.enabled,
        style = DEFAULT_SETTINGS.style,
        line_mode = DEFAULT_SETTINGS.line_mode,
        line_length_adjust = DEFAULT_SETTINGS.line_length_adjust,
        line_position = DEFAULT_SETTINGS.line_position,
        line_width_level = DEFAULT_SETTINGS.line_width_level,
        dash_length = DEFAULT_SETTINGS.dash_length,
        gap_length = DEFAULT_SETTINGS.gap_length,
        include_headings = DEFAULT_SETTINGS.include_headings,
        settings_version = 16,
    }
    if type(settings) ~= "table" then return normalized end
    if type(settings.enabled) == "boolean" then
        normalized.enabled = settings.enabled
    end
    if VALID_STYLE[settings.style] then
        normalized.style = settings.style
    end
    if VALID_LINE_MODE[settings.line_mode] then
        normalized.line_mode = settings.line_mode
    end
    local line_length_adjust = normalizeInteger(settings.line_length_adjust,
        LENGTH_ADJUST_MIN, LENGTH_ADJUST_MAX)
    if line_length_adjust then
        normalized.line_length_adjust = line_length_adjust
    end
    local line_width_level = normalizeInteger(settings.line_width_level,
        LINE_WIDTH_MIN, LINE_WIDTH_MAX)
    if line_width_level then
        normalized.line_width_level = line_width_level
    elseif settings.line_width == 1 or settings.line_width == 2 then
        -- Preserve the V1.2 visual selection during the field migration.
        normalized.line_width_level = settings.line_width
    end
    local line_position = normalizeInteger(settings.line_position,
        POSITION_MIN, POSITION_MAX)
    if line_position then
        normalized.line_position = line_position
    end
    if type(settings.dash_length) == "number" and settings.dash_length > 0 then
        normalized.dash_length = math.floor(settings.dash_length)
    end
    if type(settings.gap_length) == "number" and settings.gap_length > 0 then
        normalized.gap_length = math.floor(settings.gap_length)
    end
    if type(settings.include_headings) == "boolean" then
        normalized.include_headings = settings.include_headings
    end
    return normalized
end

local function makeGlobalDefaults(settings)
    local normalized = normalizeSettings(settings)
    return {
        enabled = normalized.enabled,
        style = normalized.style,
        line_mode = normalized.line_mode,
        line_length_adjust = normalized.line_length_adjust,
        line_position = normalized.line_position,
        line_width_level = normalized.line_width_level,
        include_headings = normalized.include_headings,
        settings_version = 16,
    }
end

local function readGlobalOrBuiltInDefaults()
    local global_defaults = G_reader_settings:readSetting(GLOBAL_DEFAULTS_KEY)
    if type(global_defaults) == "table" then
        return normalizeSettings(global_defaults), true
    end
    return normalizeSettings(), false
end

function FullTextUnderline:onDispatcherRegisterActions()
    Dispatcher:registerAction("fulltextunderline_enabled", {
        category = "string",
        event = "SetFullTextUnderlineEnabled",
        title = _("Full Text Underline: Enable"),
        args = { true, false },
        toggle = { _("On"), _("Off") },
        rolling = true,
    })
    Dispatcher:registerAction("fulltextunderline_style", {
        category = "string",
        event = "SetFullTextUnderlineStyle",
        title = _("Full Text Underline: Line Style"),
        args = { "solid", "dashed", "dotted" },
        toggle = { _("Solid"), _("Dashed"), _("Dotted") },
        rolling = true,
    })
    Dispatcher:registerAction("fulltextunderline_line_mode", {
        category = "string",
        event = "SetFullTextUnderlineLineMode",
        title = _("Full Text Underline: Underline Mode"),
        args = { "full", "text" },
        toggle = { _("Full-width Lines"), _("Text-width Lines") },
        rolling = true,
    })
    Dispatcher:registerAction("fulltextunderline_line_length_adjust", {
        category = "absolutenumber",
        event = "SetFullTextUnderlineLineLengthAdjust",
        title = _("Full Text Underline: Underline Length"),
        min = LENGTH_ADJUST_MIN,
        max = LENGTH_ADJUST_MAX,
        step = 1,
        rolling = true,
    })
    Dispatcher:registerAction("fulltextunderline_line_position", {
        category = "absolutenumber",
        event = "SetFullTextUnderlineLinePosition",
        title = _("Full Text Underline: Underline Position"),
        min = POSITION_MIN,
        max = POSITION_MAX,
        step = 1,
        rolling = true,
    })
    Dispatcher:registerAction("fulltextunderline_line_width_level", {
        category = "absolutenumber",
        event = "SetFullTextUnderlineLineWidthLevel",
        title = _("Full Text Underline: Line Thickness"),
        min = LINE_WIDTH_MIN,
        max = LINE_WIDTH_MAX,
        step = 1,
        rolling = true,
    })
    Dispatcher:registerAction("fulltextunderline_include_headings", {
        category = "string",
        event = "SetFullTextUnderlineIncludeHeadings",
        title = _("Full Text Underline: Underline Headings"),
        args = { true, false },
        toggle = { _("On"), _("Off") },
        rolling = true,
    })
end

function FullTextUnderline:installProfilesIntegration()
    local profiles = self.ui and self.ui.profiles
    if not profiles or self._profiles_integration then return end
    if profiles._fulltextunderline_profile_owner then return end

    local original = profiles.getProfileFromCurrentBookSettings
    if type(original) ~= "function" then return end
    local plugin = self
    local wrapper = function(profiles_instance, new_name)
        local profile = original(profiles_instance, new_name)
        if type(profile) ~= "table" then return profile end
        profile.settings = profile.settings or { name = new_name }
        profile.settings.order = profile.settings.order or {}
        local present = {}
        for _, name in ipairs(profile.settings.order) do present[name] = true end
        for _, action in ipairs(PROFILE_ACTIONS) do
            profile[action.name] = plugin.settings[action.field]
            if not present[action.name] then
                profile.settings.order[#profile.settings.order + 1] = action.name
                present[action.name] = true
            end
        end
        return profile
    end

    profiles._fulltextunderline_profile_owner = self
    profiles.getProfileFromCurrentBookSettings = wrapper
    self._profiles_integration = {
        profiles = profiles,
        original = original,
        wrapper = wrapper,
    }
end

function FullTextUnderline:uninstallProfilesIntegration()
    local integration = self._profiles_integration
    if not integration then return end
    local profiles = integration.profiles
    if profiles.getProfileFromCurrentBookSettings == integration.wrapper then
        profiles.getProfileFromCurrentBookSettings = integration.original
    end
    if profiles._fulltextunderline_profile_owner == self then
        profiles._fulltextunderline_profile_owner = nil
    end
    self._profiles_integration = nil
end

function FullTextUnderline:init()
    self.settings = normalizeSettings()
    self.supported = self.ui
        and self.ui.document
        and self.ui.document.provider == "crengine"
        and self.ui.document.info
        and not self.ui.document.info.has_pages
        and self.ui.view ~= nil

    if self.supported then
        self:onDispatcherRegisterActions()
        -- Register before the first ReaderView paint. The module is always
        -- present but paintTo is a no-op while disabled.
        PageGrid.register(self)
        self.ui.menu:registerToMainMenu(self)
        self:installProfilesIntegration()
    end
end

function FullTextUnderline:onReadSettings(config)
    local saved = config:readSetting(DOC_SETTING_KEY)
    if type(saved) == "table" then
        self.settings = normalizeSettings(saved)
        self._has_book_settings = true
        self._using_global_defaults = false
    else
        local previous = config:readSetting(PREVIOUS_SETTING_KEY)
        if type(previous) == "table" then
            -- A legacy per-book setting still outranks global defaults.
            self.settings = normalizeSettings(previous)
            self._has_book_settings = true
            self._using_global_defaults = false
            config:saveSetting(DOC_SETTING_KEY, self.settings)
        else
            local has_global_defaults
            self.settings, has_global_defaults = readGlobalOrBuiltInDefaults()
            self._has_book_settings = false
            self._using_global_defaults = has_global_defaults
        end
    end
    self._profile_override_active = false
    PageGrid.invalidate(self, "read_settings")
end

function FullTextUnderline:saveSettings()
    if self.ui and self.ui.doc_settings then
        self._has_book_settings = true
        self._using_global_defaults = false
        self.ui.doc_settings:saveSetting(DOC_SETTING_KEY, {
            enabled = self.settings.enabled,
            style = self.settings.style,
            line_mode = self.settings.line_mode,
            line_length_adjust = self.settings.line_length_adjust,
            line_position = self.settings.line_position,
            line_width_level = self.settings.line_width_level,
            dash_length = self.settings.dash_length,
            gap_length = self.settings.gap_length,
            include_headings = self.settings.include_headings,
            settings_version = 16,
        })
    end
end

function FullTextUnderline:onSaveSettings()
    if self._has_book_settings and not self._profile_override_active then
        self:saveSettings()
    end
end

function FullTextUnderline:showConfirmation(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 2,
    })
end

function FullTextUnderline:saveCurrentAsGlobalDefaults()
    G_reader_settings:saveSetting(GLOBAL_DEFAULTS_KEY,
        makeGlobalDefaults(self.settings))
    G_reader_settings:flush()
    self:showConfirmation(_("Current underline settings saved as the default for new books."))
end

function FullTextUnderline:resetCurrentBookToDefaults()
    if self.ui and self.ui.doc_settings then
        self.ui.doc_settings:delSetting(DOC_SETTING_KEY)
        self.ui.doc_settings:delSetting(PREVIOUS_SETTING_KEY)
    end
    local has_global_defaults
    self.settings, has_global_defaults = readGlobalOrBuiltInDefaults()
    self._has_book_settings = false
    self._using_global_defaults = has_global_defaults
    self._profile_override_active = false
    self:requestReaderViewRedraw("reset_current_book_to_defaults")
    self:showConfirmation(has_global_defaults
        and _("This book has been reset to the plugin defaults.")
        or _("This book has been reset to the built-in defaults."))
end

function FullTextUnderline:resetGlobalDefaultsToBuiltIn()
    G_reader_settings:delSetting(GLOBAL_DEFAULTS_KEY)
    G_reader_settings:flush()
    self:showConfirmation(_("Plugin defaults cleared. New books will use the built-in defaults."))
end

function FullTextUnderline:requestReaderViewRedraw(reason)
    PageGrid.invalidate(self, reason)
    -- Menu callbacks may run while the menu is still the top window. Mark the
    -- complete ReaderView dialog dirty on the next tick so document, saved and
    -- temporary highlights, and this view module are painted into one buffer.
    UIManager:nextTick(function()
        if self.ui and self.ui.view and self.ui.view.dialog then
            logger.info("fulltextunderline: one ReaderView partial redraw:", reason)
            UIManager:setDirty(self.ui.view.dialog, "partial")
        end
    end)
end

function FullTextUnderline:commitSettingsChange(reason)
    -- A direct menu change is an explicit current-book choice and ends any
    -- transient Profile override before persisting the new book settings.
    self._profile_override_active = false
    if self._batched_update then
        self._batched_settings_changed = true
        self._batched_redraw_reason = "profile"
        return
    end
    self:saveSettings()
    self:requestReaderViewRedraw(reason)
end

function FullTextUnderline:onBatchedUpdate()
    self._batched_update = true
end

function FullTextUnderline:onBatchedUpdateDone()
    self._batched_update = false
    if self._batched_profile_settings_changed then
        self._batched_profile_settings_changed = nil
        self:requestReaderViewRedraw("profile")
    end
    if not self._batched_settings_changed then return end
    self._batched_settings_changed = nil
    local reason = self._batched_redraw_reason or "profile"
    self._batched_redraw_reason = nil
    self:saveSettings()
    self:requestReaderViewRedraw(reason)
end

function FullTextUnderline:updateEnabled(enabled)
    if self.settings.enabled == enabled then return end
    self.settings.enabled = enabled
    self:commitSettingsChange(enabled and "enable" or "disable")
end

function FullTextUnderline:updateStyle(style)
    if not VALID_STYLE[style] or self.settings.style == style then return end
    -- Update runtime state first, then clear every geometry/style cache, then
    -- request exactly one complete ReaderView repaint. No document event is sent.
    self.settings.style = style
    self:commitSettingsChange("style_" .. style)
end

function FullTextUnderline:updateLineMode(line_mode)
    if not VALID_LINE_MODE[line_mode]
        or self.settings.line_mode == line_mode then
        return
    end
    self.settings.line_mode = line_mode
    self:commitSettingsChange("line_mode_" .. line_mode)
end

function FullTextUnderline:updateLineLengthAdjust(line_length_adjust)
    line_length_adjust = normalizeInteger(line_length_adjust,
        LENGTH_ADJUST_MIN, LENGTH_ADJUST_MAX)
    if not line_length_adjust
        or self.settings.line_length_adjust == line_length_adjust then
        return
    end
    self.settings.line_length_adjust = line_length_adjust
    self:commitSettingsChange("line_length_adjust_" .. line_length_adjust)
end

function FullTextUnderline:updateLineWidthLevel(line_width_level)
    line_width_level = normalizeInteger(line_width_level,
        LINE_WIDTH_MIN, LINE_WIDTH_MAX)
    if not line_width_level then return end
    if self.settings.line_width_level == line_width_level then return end
    self.settings.line_width_level = line_width_level
    self:commitSettingsChange("line_width_level_" .. line_width_level)
end

function FullTextUnderline:updateIncludeHeadings(include_headings)
    if self.settings.include_headings == include_headings then return end
    self.settings.include_headings = include_headings
    self:commitSettingsChange(include_headings
        and "include_headings" or "exclude_headings")
end

function FullTextUnderline:updateLinePosition(line_position)
    line_position = normalizeInteger(line_position, POSITION_MIN, POSITION_MAX)
    if not line_position then return end
    if self.settings.line_position == line_position then return end
    self.settings.line_position = line_position
    self:commitSettingsChange("line_position_" .. line_position)
end

function FullTextUnderline:applyProfileValue(field, value, reason)
    local changed = self.settings[field] ~= value
    self.settings[field] = value
    -- Presence of even one underline action makes this a transient Profile
    -- override. It must never be written into doc_settings automatically.
    self._profile_override_active = true
    if not changed then return end
    if self._batched_update then
        self._batched_profile_settings_changed = true
    else
        self:requestReaderViewRedraw(reason)
    end
end

function FullTextUnderline:onSetFullTextUnderlineEnabled(enabled)
    if type(enabled) == "boolean" then
        self:applyProfileValue("enabled", enabled, "profile_enabled")
    end
end

function FullTextUnderline:onSetFullTextUnderlineStyle(style)
    if VALID_STYLE[style] then
        self:applyProfileValue("style", style, "profile_style")
    end
end

function FullTextUnderline:onSetFullTextUnderlineLineMode(line_mode)
    if VALID_LINE_MODE[line_mode] then
        self:applyProfileValue("line_mode", line_mode, "profile_line_mode")
    end
end

function FullTextUnderline:onSetFullTextUnderlineLineLengthAdjust(adjust)
    adjust = normalizeInteger(adjust, LENGTH_ADJUST_MIN, LENGTH_ADJUST_MAX)
    if adjust then
        self:applyProfileValue("line_length_adjust", adjust,
            "profile_line_length_adjust")
    end
end

function FullTextUnderline:onSetFullTextUnderlineLinePosition(line_position)
    line_position = normalizeInteger(line_position, POSITION_MIN, POSITION_MAX)
    if line_position then
        self:applyProfileValue("line_position", line_position,
            "profile_line_position")
    end
end

function FullTextUnderline:onSetFullTextUnderlineLineWidthLevel(level)
    level = normalizeInteger(level, LINE_WIDTH_MIN, LINE_WIDTH_MAX)
    if level then
        self:applyProfileValue("line_width_level", level,
            "profile_line_width_level")
    end
end

function FullTextUnderline:onSetFullTextUnderlineIncludeHeadings(include_headings)
    if type(include_headings) == "boolean" then
        self:applyProfileValue("include_headings", include_headings,
            "profile_include_headings")
    end
end

function FullTextUnderline:paintTo(bb, x, y)
    if self.supported and self.settings.enabled then
        PageGrid.paint(self, bb, x, y)
    end
end

function FullTextUnderline:onPageUpdate()
    PageGrid.invalidate(self, "page_update")
end

function FullTextUnderline:onPosUpdate()
    PageGrid.invalidate(self, "pos_update")
end

function FullTextUnderline:onDocumentRerendered()
    PageGrid.invalidate(self, "document_rerendered")
end

function FullTextUnderline:onViewRecalculate()
    PageGrid.invalidate(self, "view_recalculate")
end

function FullTextUnderline:onSetDimensions()
    PageGrid.invalidate(self, "set_dimensions")
end

function FullTextUnderline:onReaderReady()
    -- The Profiles plugin may load after this plugin. At ReaderReady all
    -- document plugins are available, so install the narrow save hook here.
    self:installProfilesIntegration()
end

function FullTextUnderline:onCloseDocument()
    self:uninstallProfilesIntegration()
    PageGrid.unregister(self)
    PageGrid.invalidate(self, "close_document")
end

function FullTextUnderline:addToMainMenu(menu_items)
    menu_items.fulltext_underline = {
        text = _("Full Text Underline"),
        sorting_hint = "typeset",
        sub_item_table = {
            {
                text = _("Enable"),
                checked_func = function()
                    return self.settings.enabled
                end,
                callback = function()
                    self:updateEnabled(not self.settings.enabled)
                end,
            },
            {
                text = _("Line Style"),
                sub_item_table = {
                    {
                        text = _("Solid"),
                        radio = true,
                        checked_func = function()
                            return self.settings.style == "solid"
                        end,
                        callback = function()
                            self:updateStyle("solid")
                        end,
                    },
                    {
                        text = _("Dashed"),
                        radio = true,
                        checked_func = function()
                            return self.settings.style == "dashed"
                        end,
                        callback = function()
                            self:updateStyle("dashed")
                        end,
                    },
                    {
                        text = _("Dotted"),
                        radio = true,
                        checked_func = function()
                            return self.settings.style == "dotted"
                        end,
                        callback = function()
                            self:updateStyle("dotted")
                        end,
                    },
                },
            },
            {
                text = _("Underline Mode"),
                sub_item_table = {
                    {
                        text = _("Full-width Lines"),
                        radio = true,
                        checked_func = function()
                            return self.settings.line_mode == "full"
                        end,
                        callback = function()
                            self:updateLineMode("full")
                        end,
                    },
                    {
                        text = _("Text-width Lines"),
                        radio = true,
                        checked_func = function()
                            return self.settings.line_mode == "text"
                        end,
                        callback = function()
                            self:updateLineMode("text")
                        end,
                    },
                },
            },
            {
                text_func = function()
                    return T(_("Underline Position: %1"),
                        formatSignedValue(self.settings.line_position))
                end,
                sub_item_table_func = function()
                    return {
                        {
                            text = "-",
                            keep_menu_open = true,
                            enabled_func = function()
                                return self.settings.line_position > POSITION_MIN
                            end,
                            callback = function(touchmenu_instance)
                                self:updateLinePosition(
                                    self.settings.line_position - 1)
                                touchmenu_instance:updateItems()
                            end,
                        },
                        {
                            text_func = function()
                                return tostring(self.settings.line_position)
                            end,
                            enabled = false,
                        },
                        {
                            text = "+",
                            keep_menu_open = true,
                            enabled_func = function()
                                return self.settings.line_position < POSITION_MAX
                            end,
                            callback = function(touchmenu_instance)
                                self:updateLinePosition(
                                    self.settings.line_position + 1)
                                touchmenu_instance:updateItems()
                            end,
                        },
                    }
                end,
            },
            {
                text_func = function()
                    return T(_("Underline Length: %1"),
                        formatSignedValue(self.settings.line_length_adjust))
                end,
                sub_item_table_func = function()
                    return {
                        {
                            text = "-",
                            keep_menu_open = true,
                            enabled_func = function()
                                return self.settings.line_length_adjust
                                    > LENGTH_ADJUST_MIN
                            end,
                            callback = function(touchmenu_instance)
                                self:updateLineLengthAdjust(
                                    self.settings.line_length_adjust - 1)
                                touchmenu_instance:updateItems()
                            end,
                        },
                        {
                            text_func = function()
                                return tostring(self.settings.line_length_adjust)
                            end,
                            enabled = false,
                        },
                        {
                            text = "+",
                            keep_menu_open = true,
                            enabled_func = function()
                                return self.settings.line_length_adjust
                                    < LENGTH_ADJUST_MAX
                            end,
                            callback = function(touchmenu_instance)
                                self:updateLineLengthAdjust(
                                    self.settings.line_length_adjust + 1)
                                touchmenu_instance:updateItems()
                            end,
                        },
                    }
                end,
            },
            {
                text_func = function()
                    return T(_("Line Thickness: %1"),
                        self.settings.line_width_level)
                end,
                sub_item_table_func = function()
                    return {
                        {
                            text = "-",
                            keep_menu_open = true,
                            enabled_func = function()
                                return self.settings.line_width_level
                                    > LINE_WIDTH_MIN
                            end,
                            callback = function(touchmenu_instance)
                                self:updateLineWidthLevel(
                                    self.settings.line_width_level - 1)
                                touchmenu_instance:updateItems()
                            end,
                        },
                        {
                            text_func = function()
                                return tostring(self.settings.line_width_level)
                            end,
                            enabled = false,
                        },
                        {
                            text = "+",
                            keep_menu_open = true,
                            enabled_func = function()
                                return self.settings.line_width_level
                                    < LINE_WIDTH_MAX
                            end,
                            callback = function(touchmenu_instance)
                                self:updateLineWidthLevel(
                                    self.settings.line_width_level + 1)
                                touchmenu_instance:updateItems()
                            end,
                        },
                    }
                end,
            },
            {
                text = _("Underline Headings"),
                checked_func = function()
                    return self.settings.include_headings
                end,
                callback = function()
                    self:updateIncludeHeadings(
                        not self.settings.include_headings)
                end,
            },
            {
                text = _("More Settings"),
                sub_item_table = {
                    {
                        text = _("Set Current Settings as Default"),
                        callback = function()
                            self:saveCurrentAsGlobalDefaults()
                        end,
                    },
                    {
                        text = _("Reset This Book to Default"),
                        callback = function()
                            self:resetCurrentBookToDefaults()
                        end,
                    },
                    {
                        text = _("Restore Built-in Defaults"),
                        callback = function()
                            self:resetGlobalDefaultsToBuiltIn()
                        end,
                    },
                },
            },
        },
    }
end

return FullTextUnderline
