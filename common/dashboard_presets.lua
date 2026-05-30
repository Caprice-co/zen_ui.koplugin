local M = {}

M.DEFAULT_PRESET_NAME = "(Zen UI) Default"

local DEFAULT_DASHBOARD_PAGE = {
    title = M.DEFAULT_PRESET_NAME,
    rows = {
        max_rows = 5,
        order = {
            "datetime",
            "featured_recent",
            "stats_triplet",
            "strip_tbr",
            "featured_custom",
            "featured_tbr",
            "strip_recent",
            "reading_goals",
            "strip_custom",
            "quotes",
        },
        enabled = {
            datetime = true,
            featured_custom = false,
            featured_recent = true,
            featured_tbr = false,
            quotes = true,
            reading_goals = false,
            stats_triplet = false,
            strip_custom = false,
            strip_recent = true,
            strip_tbr = false,
        },
    },
    middle_stats_triplet = {
        "today_pages",
        "today_duration",
        "streak",
    },
    goals = {
        daily_pages_target = 30,
        daily_target = 30,
        daily_time_target_min = 30,
        metric = "pages",
        period = "daily",
        weekly_pages_target = 210,
        weekly_target = 210,
        weekly_time_target_min = 210,
    },
    modules = {
        datetime = {
            show_module_title = false,
        },
        featured_custom = {
            order = "default",
            path = nil,
            show_description = true,
            show_module_title = true,
        },
        featured_recent = {
            order = "default",
            show_description = true,
            show_module_title = false,
        },
        featured_tbr = {
            order = "default",
            show_description = true,
            show_module_title = true,
        },
        quotes = {
            show_module_title = false,
        },
        reading_goals = {
            show_module_title = false,
        },
        stats_triplet = {
            show_module_title = false,
        },
        strip_custom = {
            count = 5,
            order = "default",
            paths = {},
            show_module_title = false,
            show_strip_titles = false,
        },
        strip_recent = {
            count = 5,
            order = "default",
            show_module_title = false,
            show_strip_titles = false,
        },
        strip_tbr = {
            count = 5,
            order = "default",
            show_module_title = false,
            show_strip_titles = false,
        },
    },
    quotes = {
        day_seed = 741666,
        manual_index = 11,
        show_author = true,
    },
}

local DASHBOARD_KEYS = {
    "title",
    "rows",
    "middle_stats_triplet",
    "goals",
    "modules",
    "quotes",
}

local function deepcopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, val in pairs(value) do
        out[deepcopy(key, seen)] = deepcopy(val, seen)
    end
    return out
end

function M.copy(value)
    return deepcopy(value)
end

function M.defaultDashboardPage()
    local page = deepcopy(DEFAULT_DASHBOARD_PAGE)
    page.active_preset = M.DEFAULT_PRESET_NAME
    return page
end

function M.getBuiltinPresets()
    return {
        {
            name = M.DEFAULT_PRESET_NAME,
            builtin = true,
            dashboard_page = deepcopy(DEFAULT_DASHBOARD_PAGE),
        },
    }
end

function M.ensurePresetState(dcfg)
    if type(dcfg.active_preset) ~= "string" or dcfg.active_preset == "" then
        dcfg.active_preset = nil
    end
end

function M.captureDashboardPage(dcfg)
    local out = {}
    for _i, key in ipairs(DASHBOARD_KEYS) do
        out[key] = deepcopy(dcfg[key])
    end
    return out
end

function M.applyDashboardPagePreset(dcfg, preset)
    if type(dcfg) ~= "table" or type(preset) ~= "table" then return end
    local source = type(preset.dashboard_page) == "table" and preset.dashboard_page or preset
    if source.title == nil and type(preset.name) == "string" then
        dcfg.title = preset.name
    end
    for _i, key in ipairs(DASHBOARD_KEYS) do
        if source[key] ~= nil then
            dcfg[key] = deepcopy(source[key])
        end
    end
end

return M
