local _ = require("gettext")

local M = {}

local function save_config(plugin)
    if plugin and type(plugin.saveConfig) == "function" then
        plugin:saveConfig()
    end
end

local function get_reader()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI and ReaderUI.instance or nil
end

local function refresh_reader()
    local reader = get_reader()
    if reader then
        require("ui/uimanager"):setDirty(reader, "ui")
    end
end

local function apply_top_status_bar(plugin, enabled)
    local apply = require("modules/settings/zen_settings_apply")
    apply.apply_feature_toggle(plugin, "reader_top_status_bar", enabled)
end

local function is_top_status_bar_enabled(plugin)
    local features = plugin and plugin.config and plugin.config.features
    return type(features) == "table" and features.reader_top_status_bar == true
end

local function set_top_status_bar(plugin, enabled)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    if features.reader_top_status_bar == enabled then
        refresh_reader()
        return true
    end
    features.reader_top_status_bar = enabled
    save_config(plugin)
    apply_top_status_bar(plugin, enabled)
    return true
end

local function get_footer()
    local reader = get_reader()
    return reader and reader.view and reader.view.footer or nil
end

local function is_bottom_status_bar_visible()
    local footer = get_footer()
    return footer and footer.view and footer.view.footer_visible == true
end

local function fallback_footer_mode(footer)
    if not footer or type(footer.mode_list) ~= "table" then return 1 end
    return footer.mode_list.page_progress or 1
end

local function set_bottom_status_bar(plugin, enabled)
    local footer = get_footer()
    if not footer then return false end

    local plugin_config = plugin and plugin.config or nil
    local mode_list = footer.mode_list or {}
    local off_mode = mode_list.off or 0
    if enabled then
        local reader_footer = plugin_config and plugin_config.reader_footer
        local last_mode = reader_footer and reader_footer.last_status_bar_mode
        if type(last_mode) ~= "number" or last_mode == off_mode then
            last_mode = G_reader_settings:readSetting("reader_footer_mode")
        end
        if type(last_mode) ~= "number" or last_mode == off_mode then
            last_mode = fallback_footer_mode(footer)
        end
        footer:applyFooterMode(last_mode)
        G_reader_settings:saveSetting("reader_footer_mode", last_mode)
    else
        if plugin_config and type(plugin_config.reader_footer) ~= "table" then
            plugin_config.reader_footer = {}
        end
        if plugin_config and type(footer.mode) == "number" and footer.mode ~= off_mode then
            plugin_config.reader_footer.last_status_bar_mode = footer.mode
            save_config(plugin)
        end
        footer:applyFooterMode(off_mode)
        G_reader_settings:saveSetting("reader_footer_mode", off_mode)
    end

    footer:refreshFooter(true, true)
    if type(footer.rescheduleFooterAutoRefreshIfNeeded) == "function" then
        footer:rescheduleFooterAutoRefreshIfNeeded()
    end
    return true
end

function M.onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("zen_ui_toggle_zen_mode", {
        category = "none",
        event = "ToggleZenMode",
        title = _("Zen UI - Toggle Zen Mode"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_lockdown_mode", {
        category = "none",
        event = "ToggleLockdownMode",
        title = _("Zen UI - Toggle Lockdown Mode"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_reader_top_status_bar", {
        category = "none",
        event = "ToggleReaderTopStatusBar",
        title = _("Zen UI - Toggle top reader status bar"),
        reader = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_reader_bottom_status_bar", {
        category = "none",
        event = "ToggleReaderBottomStatusBar",
        title = _("Zen UI - Toggle bottom reader status bar"),
        reader = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_reader_status_bars", {
        category = "none",
        event = "ToggleReaderStatusBars",
        title = _("Zen UI - Toggle reader status bars"),
        reader = true,
    })
end

function M.onToggleZenMode(plugin)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    if features.lockdown_mode == true and features.zen_mode == true then
        return true
    end
    features.zen_mode = not features.zen_mode
    save_config(plugin)
    require("modules/settings/zen_settings_apply").prompt_restart()
    return true
end

function M.onToggleLockdownMode(plugin)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    local enabling = not features.lockdown_mode
    features.lockdown_mode = enabling
    if enabling then features.zen_mode = true end
    local ok_lm, lockdown_mod = pcall(require, "modules/global/patches/lockdown_mode")
    if ok_lm and type(lockdown_mod) == "table" then
        lockdown_mod.apply_magnify_layout(plugin, enabling)
    end
    save_config(plugin)
    require("modules/settings/zen_settings_apply").prompt_restart()
    return true
end

function M.onToggleReaderTopStatusBar(plugin)
    return set_top_status_bar(plugin, not is_top_status_bar_enabled(plugin))
end

function M.onToggleReaderBottomStatusBar(plugin)
    return set_bottom_status_bar(plugin, not is_bottom_status_bar_visible())
end

function M.onToggleReaderStatusBars(plugin)
    local enable = not (is_top_status_bar_enabled(plugin) or is_bottom_status_bar_visible())
    local top_ok = set_top_status_bar(plugin, enable)
    local bottom_ok = set_bottom_status_bar(plugin, enable)
    return top_ok or bottom_ok
end

function M.install(target)
    target.onDispatcherRegisterActions = M.onDispatcherRegisterActions
    target.onToggleZenMode = M.onToggleZenMode
    target.onToggleLockdownMode = M.onToggleLockdownMode
    target.onToggleReaderTopStatusBar = M.onToggleReaderTopStatusBar
    target.onToggleReaderBottomStatusBar = M.onToggleReaderBottomStatusBar
    target.onToggleReaderStatusBars = M.onToggleReaderStatusBars
end

return M
