local shared = require("modules/filebrowser/patches/dashboard/widgets/featured_common")

return {
    id = "featured_custom",
    label = "Custom featured widget",
    size = { preferred = 306, min = 196, max = 476 },
    build = function(ctx)
        return shared.build(ctx, "custom_featured")
    end,
}
