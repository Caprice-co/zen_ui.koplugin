local components = {
    require("modules/filebrowser/patches/dashboard/widgets/datetime"),
    require("modules/filebrowser/patches/dashboard/widgets/featured_custom"),
    require("modules/filebrowser/patches/dashboard/widgets/featured_tbr"),
    require("modules/filebrowser/patches/dashboard/widgets/featured_recent"),
    require("modules/filebrowser/patches/dashboard/widgets/stats_triplet"),
    require("modules/filebrowser/patches/dashboard/widgets/reading_goals"),
    require("modules/filebrowser/patches/dashboard/widgets/strip_custom"),
    require("modules/filebrowser/patches/dashboard/widgets/strip_tbr"),
    require("modules/filebrowser/patches/dashboard/widgets/strip_recent"),
    require("modules/filebrowser/patches/dashboard/widgets/quotes"),
}

local by_id = {}
for _i, comp in ipairs(components) do
    by_id[comp.id] = comp
end

local M = {}

function M.list()
    return components
end

function M.get(id)
    return by_id[id]
end

return M
