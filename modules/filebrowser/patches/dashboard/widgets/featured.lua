local shared = require("modules/filebrowser/patches/dashboard/widgets/featured_common")

return {
    id = "featured",
    label = "Featured widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx)
    end,
}
