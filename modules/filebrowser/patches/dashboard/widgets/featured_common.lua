local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Font = require("ui/font")
local util = require("util")
local cover_common = require("modules/filebrowser/patches/dashboard/widgets/cover_common")

local M = {}

local function clamp(v, min_v, max_v)
    if v < min_v then return min_v end
    if v > max_v then return max_v end
    return v
end

local function render_progress(percent, w, h)
    local pct = percent or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end

    local fill_w = math.floor(w * pct)
    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        LineWidget:new{ dimen = Geom:new{ w = w, h = h }, background = Blitbuffer.COLOR_LIGHT_GRAY },
    }
    if fill_w > 0 then
        table.insert(bar, LineWidget:new{ dimen = Geom:new{ w = fill_w, h = h }, background = Blitbuffer.COLOR_DARK_GRAY })
    end
    return bar
end

function M.build(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local source = source_key or "recently_read"
    local order = module_cfg.order or "default"
    local book = ctx.data:getFeaturedBook(source, order)
    local Screen = Device.screen
    local show_description = module_cfg.show_description ~= false

    local cover_v_pad = math.max(1, math.floor(height * 0.015))
    local gap = math.max(4, math.floor(width * 0.025))

    if not book then
        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                TextWidget:new{ text = "No books found", face = ctx.face_label },
            },
        }
    end

    local cover_slot_h = math.max(1, height - cover_v_pad * 2)
    local min_text_w = math.max(40, math.floor(width * 0.36))
    local max_cover_w = math.max(1, width - gap - min_text_w)
    local cover_max_w = math.max(1, math.min(math.floor(width * 0.46), math.floor(cover_slot_h * 0.76), max_cover_w))
    local cover_widget, cover_w = cover_common.make_cover_widget(
        book,
        cover_max_w,
        cover_slot_h,
        { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY }
    )
    local cover_slot_w = cover_w or cover_max_w
    gap = math.min(gap, math.max(0, width - cover_slot_w - 1))

    local text_w = math.max(1, width - (cover_slot_w + gap))
    local pct = math.floor((book.percent or 0) * 100 + 0.5)
    local pages_text = book.pages and (tostring(book.pages) .. " pages") or ""

    local progress_h = math.min(cover_slot_h, math.max(1, math.floor(height * 0.022)))
    local progress_w = text_w
    local scale = clamp(cover_slot_h / 300, 0.55, 1.28)
    local title_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(11 * scale + 0.5)))
    local meta_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(9 * scale + 0.5)))
    local desc_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(7 * scale + 0.5)))
    local stats_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(8 * scale + 0.5)))
    local stats_h = math.min(cover_slot_h, math.max(1, math.floor(cover_slot_h * 0.09)))

    local title_line_h = TextWidget:new{ text = "A", face = title_face }:getSize().h or 12
    local author_line_h = TextWidget:new{ text = "A", face = meta_face }:getSize().h or 10
    local desc_line_h = TextWidget:new{ text = "A", face = desc_face }:getSize().h or 8
    local title_h = show_description
        and math.max(math.min(title_line_h, cover_slot_h), math.floor(cover_slot_h * 0.12))
        or math.max(math.min(title_line_h, cover_slot_h), math.floor(cover_slot_h * 0.22))
    local author_h = show_description and math.max(math.min(author_line_h, cover_slot_h), math.floor(cover_slot_h * 0.07)) or 0
    local before_desc_gap = show_description and math.max(1, math.floor(cover_slot_h * 0.02)) or 0
    local after_desc_gap = show_description and math.max(1, desc_line_h) or 0
    local progress_gap = math.max(1, math.floor(cover_slot_h * 0.012))
    local fallback_gap = math.max(1, math.floor(cover_slot_h * 0.02))
    if progress_h + progress_gap + stats_h > cover_slot_h then
        progress_gap = 0
        stats_h = math.max(0, cover_slot_h - progress_h)
    end
    local bottom_block_h = progress_h + progress_gap + stats_h
    if title_h + author_h + bottom_block_h > cover_slot_h then
        local text_budget = math.max(0, cover_slot_h - bottom_block_h)
        if text_budget < 1 then
            title_h = 0
            author_h = 0
        else
            title_h = math.min(title_h, math.max(1, text_budget - (show_description and math.min(author_h, math.floor(text_budget * 0.35)) or 0)))
            author_h = show_description and math.max(0, text_budget - title_h) or 0
        end
    end
    local fixed_h = title_h + author_h + bottom_block_h
    local desc_text = book.description and util.htmlToPlainTextIfHtml(book.description) or ""
    local can_show_desc = show_description
        and type(desc_text) == "string"
        and desc_text ~= ""
        and cover_slot_h >= fixed_h + before_desc_gap + after_desc_gap + desc_line_h
    local half_w = math.floor(text_w / 2)
    local stats_row = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = half_w, h = stats_h },
            TextWidget:new{ text = tostring(pct) .. "%", face = stats_face, fgcolor = Blitbuffer.COLOR_GRAY_3 },
        },
        RightContainer:new{
            dimen = Geom:new{ w = text_w - half_w, h = stats_h },
            TextWidget:new{ text = pages_text, face = stats_face, fgcolor = Blitbuffer.COLOR_GRAY_3 },
        },
    }
    local has_desc = false
    local detail_children = { align = "left" }
    if title_h > 0 then
        table.insert(detail_children, TextBoxWidget:new{
            text = book.title or "",
            width = text_w,
            height = title_h,
            face = title_face,
            bold = true,
            height_overflow_show_ellipsis = true,
        })
    end
    if show_description and author_h > 0 then
        table.insert(detail_children, TextBoxWidget:new{
            text = book.authors or "",
            width = text_w,
            height = author_h,
            face = meta_face,
            fgcolor = Blitbuffer.COLOR_GRAY_3,
            height_overflow_show_ellipsis = true,
        })
        if can_show_desc then
            local desc_h = cover_slot_h - (fixed_h + before_desc_gap + after_desc_gap)
            table.insert(detail_children, VerticalSpan:new{ width = before_desc_gap })
            table.insert(detail_children, TextBoxWidget:new{
                text = desc_text,
                width = text_w,
                height = desc_h,
                face = desc_face,
                fgcolor = Blitbuffer.COLOR_GRAY_3,
                height_overflow_show_ellipsis = true,
            })
            table.insert(detail_children, VerticalSpan:new{ width = after_desc_gap })
            has_desc = true
        end
    end
    if not has_desc then
        local used_h = title_h + author_h + bottom_block_h
        local spare_h = cover_slot_h - used_h
        if spare_h > 0 then
            table.insert(detail_children, VerticalSpan:new{ width = math.min(fallback_gap, spare_h) })
        end
    end
    table.insert(detail_children, render_progress(book.percent, progress_w, progress_h))
    table.insert(detail_children, VerticalSpan:new{ width = progress_gap })
    table.insert(detail_children, stats_row)
    local detail = FrameContainer:new{
        width = text_w,
        height = cover_slot_h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new(detail_children),
    }

    local body = HorizontalGroup:new{
        CenterContainer:new{
            dimen = Geom:new{ w = cover_slot_w, h = cover_slot_h },
            cover_widget,
        },
        HorizontalSpan:new{ width = gap },
        detail,
    }

    local tap = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            TapFeatured = {
                GestureRange:new{ ges = "tap", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
        },
    }
    tap.onTapFeatured = function(tap_self, _arg, ges)
        if not tap_self.dimen or not ges or not ges.pos then
            return false
        end
        if not tap_self.dimen:contains(ges.pos) then
            return false
        end
        ctx.openBook(book.path)
        return true
    end
    tap[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            body,
        },
    }

    if not Device:isTouchDevice() then
        return tap[1]
    end
    return tap
end

return M
