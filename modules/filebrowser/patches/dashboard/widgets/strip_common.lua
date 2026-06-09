local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local cover_common = require("modules/filebrowser/patches/dashboard/widgets/cover_common")
local Font = require("ui/font")
local Device = require("device")

local M = {}
M.SIZE = { preferred_pct = 0.20, min_pct = 0.12, max_pct = 0.30, grow_priority = 3 }

function M.build_strip(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local Screen = Device.screen
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local source = source_key or "recently_read"
    local order = module_cfg.order or "default"
    local two_rows = module_cfg.two_rows == true
    local per_row = 5
    local count
    if two_rows then
        count = per_row * 2
    else
        count = tonumber(module_cfg.count) or 5
        if count < 3 then count = 3 end
        if count > 5 then count = 5 end
    end
    local show_strip_titles = module_cfg.show_strip_titles == true
    local interactive = module_cfg.interactive ~= false

    local books = ctx.data:getBooksForStrip(source, count, order, ctx.component_id)
    if #books == 0 then
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

    local num_rows = two_rows and 2 or 1
    local row_gap = two_rows and math.max(2, Screen:scaleBySize(3)) or 0
    local row_top_pad = math.max(4, Screen:scaleBySize(4))
    local row_bottom_pad = math.max(4, Screen:scaleBySize(4))
    local strip_title_face = Font:getFace("smallinfofont", Screen:scaleBySize(10))
    local title_h = show_strip_titles and math.max(14, Screen:scaleBySize(12)) or 0
    local title_gap = show_strip_titles and math.max(1, Screen:scaleBySize(2)) or 0
    local avail_h = height - row_top_pad - row_bottom_pad - (num_rows - 1) * row_gap
    local max_cover_h_per_row = math.max(28, math.floor((avail_h - num_rows * (title_h + title_gap)) / num_rows))

    local row_books = {}
    for r = 1, num_rows do
        row_books[r] = {}
    end
    for i, book in ipairs(books) do
        local r = math.ceil(i / per_row)
        if r <= num_rows then
            table.insert(row_books[r], book)
        end
    end

    local function build_row_widget(row_list)
        local n = #row_list
        local min_gap = math.max(4, math.min(10, math.floor(width * 0.012)))
        local max_cover_w = math.max(24, math.floor((width - min_gap * (n - 1)) / n))
        local cover_h = math.min(max_cover_h_per_row, math.floor(max_cover_w * 1.62))
        if cover_h < 28 then cover_h = max_cover_h_per_row end

        local items = {}
        local covers_w = 0
        local row_h = 0
        for _i, book in ipairs(row_list) do
            local cover, cover_w = cover_common.make_cover_widget(
                book,
                max_cover_w,
                cover_h,
                { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY }
            )
            cover_w = cover_w or max_cover_w
            local cover_size = cover.getSize and cover:getSize() or nil
            local actual_cover_h = (cover_size and cover_size.h) or cover_h
            local item_h = show_strip_titles and (actual_cover_h + title_gap + title_h) or actual_cover_h
            if item_h > row_h then row_h = item_h end
            covers_w = covers_w + cover_w
            items[#items + 1] = {
                book = book,
                cover = cover,
                w = cover_w,
                cover_h = actual_cover_h,
                h = item_h,
            }
        end

        local gap = 0
        local extra_gap_px = 0
        if #items > 1 then
            local available_gap = math.max(min_gap * (#items - 1), width - covers_w)
            gap = math.floor(available_gap / (#items - 1))
            extra_gap_px = available_gap - gap * (#items - 1)
        end

        local row = HorizontalGroup:new{ align = "center" }
        for _i, item in ipairs(items) do
            local book = item.book
            local item_w = item.w
            local path = book.path

            local content
            if show_strip_titles and title_h > 0 then
                content = VerticalGroup:new{
                    align = "center",
                    CenterContainer:new{
                        dimen = Geom:new{ w = item_w, h = item.cover_h },
                        item.cover,
                    },
                    VerticalSpan:new{ width = title_gap },
                    TextBoxWidget:new{
                        text = book.title or "",
                        width = item_w,
                        height = title_h,
                        face = strip_title_face,
                        alignment = "center",
                        fgcolor = Blitbuffer.COLOR_GRAY_3,
                        height_overflow_show_ellipsis = true,
                    },
                }
            else
                content = CenterContainer:new{ dimen = Geom:new{ w = item_w, h = item.cover_h }, item.cover }
            end

            local item_widget = content
            if interactive and Device:isTouchDevice() then
                local tap = InputContainer:new{
                    dimen = Geom:new{ w = item_w, h = item.h },
                    ges_events = {
                        TapCover = {
                            GestureRange:new{ ges = "tap", range = Geom:new{
                                x = 0, y = 0,
                                w = Screen:getWidth(), h = Screen:getHeight(),
                            } },
                        },
                        HoldCover = {
                            GestureRange:new{ ges = "hold", range = Geom:new{
                                x = 0, y = 0,
                                w = Screen:getWidth(), h = Screen:getHeight(),
                            } },
                        },
                    },
                }
                tap.onTapCover = function(tap_self, _arg, ges)
                    if not tap_self.dimen or not ges or not ges.pos then return false end
                    if ctx.openTopMenu and ctx.openTopMenu(ges) then return true end
                    if not tap_self.dimen:contains(ges.pos) then return false end
                    ctx.openBook(path)
                    return true
                end
                tap.onHoldCover = function(tap_self, _arg, ges)
                    if not tap_self.dimen or not ges or not ges.pos then return false end
                    if not tap_self.dimen:contains(ges.pos) then return false end
                    if ctx.showBookMenu then return ctx.showBookMenu(path) end
                    return false
                end
                tap[1] = content
                item_widget = tap
            end

            table.insert(row, item_widget)
            if _i < #items then
                local gap_w = gap
                if extra_gap_px > 0 then
                    gap_w = gap_w + 1
                    extra_gap_px = extra_gap_px - 1
                end
                table.insert(row, HorizontalSpan:new{ width = gap_w })
            end
        end

        return row, row_h
    end

    local vgroup = VerticalGroup:new{}
    table.insert(vgroup, VerticalSpan:new{ width = row_top_pad })
    local total_row_h = 0
    for r = 1, num_rows do
        if #row_books[r] > 0 then
            local row_widget, row_h = build_row_widget(row_books[r])
            total_row_h = total_row_h + row_h
            table.insert(vgroup, CenterContainer:new{ dimen = Geom:new{ w = width, h = row_h }, row_widget })
            if r < num_rows and #row_books[r + 1] > 0 then
                table.insert(vgroup, VerticalSpan:new{ width = row_gap })
            end
        end
    end
    table.insert(vgroup, VerticalSpan:new{ width = row_bottom_pad })

    local frame = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        TopContainer:new{
            dimen = Geom:new{ w = width, h = height },
            vgroup,
        },
    }

    if not interactive or not Device:isTouchDevice() then
        return frame
    end

    local swipe = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            SwipeStrip = {
                GestureRange:new{ ges = "swipe", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
        },
    }
    swipe.onSwipeStrip = function(swipe_self, _arg, ges)
        if not swipe_self.dimen or not ges or not ges.pos then return false end
        if not swipe_self.dimen:contains(ges.pos) then return false end
        if ges.direction == "west" then
            if ctx.shiftStrip then ctx.shiftStrip(source, count, order, "next", ctx.component_id, two_rows) end
            return true
        elseif ges.direction == "east" then
            if ctx.shiftStrip then ctx.shiftStrip(source, count, order, "previous", ctx.component_id, two_rows) end
            return true
        end
        return false
    end
    swipe[1] = frame
    return swipe
end

return M
