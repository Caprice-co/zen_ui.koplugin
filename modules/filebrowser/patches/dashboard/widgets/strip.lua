local shared = require("modules/filebrowser/patches/dashboard/widgets/strip_common")

return {
    id = "strip",
    label = "Strip widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx)
    end,
}
