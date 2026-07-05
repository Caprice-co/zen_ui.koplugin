local M = {}

local FileManager
local Geom
local Screen
local UIManager
local logger
local _

local action_tabs_close_library = {
    continue = true,
    search = true,
    calibre_search = true,
    stats = true,
    exit = true,
}

local is_real_exit_target

local function is_library_view(widget)
    return widget and widget.name == "library_view"
end

function M.isLibraryView(widget)
    return is_library_view(widget)
end

function M.isScrollBarMenu(widget)
    local name = widget and widget.name
    return name == "available_sources_listing"
        or name == "chapter_listing"
        or name == "installed_sources_listing"
        or name == "library_view"
        or name == "manga_search_results"
        or name == "notification_view"
end

function M.getStandaloneTabId(widget)
    if is_library_view(widget) then
        return "manga"
    end
end

function M.shouldCloseBeforeActionTab(widget, tab_id)
    return is_library_view(widget)
        and (action_tabs_close_library[tab_id] == true
            or type(tab_id) == "string" and tab_id:sub(1, 3) == "ct_")
end

local function normalize_path(path)
    if type(path) ~= "string" or path == "" then return nil end
    return path:gsub("^/sdcard/", "/storage/emulated/0/"):gsub("/+$", "")
end

local function path_is_inside(path, directory)
    path = normalize_path(path)
    directory = normalize_path(directory)
    return path and directory
        and path:sub(1, #directory + 1) == directory .. "/"
end

local function get_data_dir()
    local DataStorage = require("datastorage")
    return DataStorage:getFullDataDir() or DataStorage:getDataDir()
end

local function absolute_data_path(path)
    if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/" then
        return path
    end
    path = path:gsub("^%./", "")
    return get_data_dir() .. "/" .. path
end

function M.isChapterFile(path)
    if type(path) ~= "string" then
        logger.dbg("zen-ui rakuyomi-return: chapter detection rejected non-string path")
        return false
    end
    local lower_path = path:lower()
    if lower_path:sub(-4) ~= ".cbz" and lower_path:sub(-5) ~= ".epub" then
        logger.dbg("zen-ui rakuyomi-return: chapter detection rejected extension:", path)
        return false
    end

    local home = get_data_dir() .. "/rakuyomi"
    local storage = home .. "/downloads"
    local content = require("util").readFromFile(home .. "/settings.json", "rb")
    if content then
        local ok_json, rapidjson = pcall(require, "rapidjson")
        local ok_decode, settings = false, nil
        if ok_json then
            ok_decode, settings = pcall(rapidjson.decode, content)
        end
        if ok_decode and type(settings) == "table"
                and type(settings.storage_path) == "string"
                and settings.storage_path ~= "" then
            storage = absolute_data_path(settings.storage_path)
        end
    end

    local parent = normalize_path(storage):match("^(.*)/[^/]+$")
    local tmpfs = parent ~= nil
        and (parent == "" and "/" or parent .. "/") .. "tmpfs" or nil
    local in_storage = path_is_inside(path, storage) == true
    local in_tmpfs = path_is_inside(path, tmpfs) == true
    logger.dbg(
        "zen-ui rakuyomi-return: chapter detection:",
        "path=", path,
        "storage=", storage,
        "tmpfs=", tostring(tmpfs),
        "in_storage=", tostring(in_storage),
        "in_tmpfs=", tostring(in_tmpfs))
    return in_storage or in_tmpfs
end

local function chapter_filename(source_id, manga_id, chapter_id)
    local sha = require("ffi/sha2")
    local digest = sha.hex_to_bin(sha.sha256(source_id .. manga_id .. chapter_id))
    return sha.bin_to_base64(digest)
        :gsub("%+", "-")
        :gsub("/", "_")
        :gsub("=+$", "")
end

function M.resolveChapterFile(path)
    if not M.isChapterFile(path) then
        logger.warn("zen-ui rakuyomi-return: resolver rejected path:", tostring(path))
        return nil
    end

    local basename = path:match("([^/]+)%.[^./]+$")
    if not basename then
        logger.warn("zen-ui rakuyomi-return: resolver could not parse filename:", path)
        return nil
    end

    local db = require("common/db_connection")
    local db_path = get_data_dir() .. "/rakuyomi/database.db"
    local conn, db_err = db.open(db_path)
    if not conn then
        logger.warn(
            "zen-ui rakuyomi-return: resolver could not open database:",
            db_path, tostring(db_err))
        return nil
    end

    local ok, rows = pcall(conn.exec, conn, [[
        SELECT ci.source_id, ci.manga_id, ci.chapter_id, mi.title
        FROM chapter_informations ci
        LEFT JOIN manga_informations mi
          ON mi.source_id = ci.source_id AND mi.manga_id = ci.manga_id
        LEFT JOIN chapter_state cs
          ON cs.source_id = ci.source_id
         AND cs.manga_id = ci.manga_id
         AND cs.chapter_id = ci.chapter_id
        ORDER BY CASE WHEN cs.last_read IS NULL THEN 1 ELSE 0 END,
                 cs.last_read DESC
    ]])
    pcall(conn.close, conn)
    if not ok or type(rows) ~= "table" then
        logger.warn(
            "zen-ui rakuyomi-return: resolver query failed:",
            "ok=", tostring(ok),
            "result=", tostring(rows))
        return nil
    end

    local source_ids = rows[1] or {}
    local manga_ids = rows[2] or {}
    local chapter_ids = rows[3] or {}
    local titles = rows[4] or {}
    logger.dbg(
        "zen-ui rakuyomi-return: resolver scanning:",
        "basename=", basename,
        "rows=", tostring(#source_ids))
    for i = 1, #source_ids do
        local source_id = source_ids[i]
        local manga_id = manga_ids[i]
        local chapter_id = chapter_ids[i]
        local modern_name = source_id and manga_id and chapter_id
            and chapter_filename(source_id, manga_id, chapter_id)
        local legacy_name = source_id and chapter_id and source_id .. "-" .. chapter_id
        if modern_name == basename or legacy_name == basename then
            logger.dbg(
                "zen-ui rakuyomi-return: resolver matched:",
                "source=", source_id,
                "manga=", manga_id,
                "chapter=", chapter_id,
                "legacy=", tostring(legacy_name == basename))
            return {
                id = manga_id,
                title = titles[i],
                source = { id = source_id },
            }
        end
    end
    logger.warn(
        "zen-ui rakuyomi-return: resolver found no database match:",
        "basename=", basename,
        "rows=", tostring(#source_ids))
end

function M.openLibraryView(options)
    local fm = FileManager and FileManager.instance
    local rakuyomi = fm and fm.rakuyomi
    if rakuyomi then
        rakuyomi:openLibraryView(options or { hideTopClose = true })
        return true
    end

    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Rakuyomi plugin is not installed."),
    })
    return false
end

function M.openChapterList(manga)
    if type(manga) ~= "table" or type(manga.id) ~= "string"
            or type(manga.source) ~= "table"
            or type(manga.source.id) ~= "string" then
        logger.warn("zen-ui rakuyomi-return: invalid chapter-list target")
        return false
    end
    logger.dbg(
        "zen-ui rakuyomi-return: opening chapter list:",
        "source=", manga.source.id,
        "manga=", manga.id)
    if not M.openLibraryView({ hideTopClose = true }) then
        logger.warn("zen-ui rakuyomi-return: could not open Rakuyomi library")
        return false
    end

    local stack = UIManager._window_stack
    local top = type(stack) == "table" and stack[#stack]
    local library_view = top and top.widget
    if not is_library_view(library_view) then
        logger.warn(
            "zen-ui rakuyomi-return: library did not become top widget:",
            tostring(library_view and library_view.name))
        return false
    end

    for _i, candidate in ipairs(library_view.mangas or {}) do
        if candidate.id == manga.id and candidate.source
                and candidate.source.id == manga.source.id then
            manga = candidate
            break
        end
    end

    local ok_listing, ChapterListing = pcall(require, "ChapterListing")
    local ok_trapper, Trapper = pcall(require, "ui/trapper")
    if not (ok_listing and ok_trapper) then
        logger.warn(
            "zen-ui rakuyomi-return: chapter-list dependencies unavailable:",
            "listing=", tostring(ok_listing),
            "trapper=", tostring(ok_trapper))
        return false
    end

    Trapper:wrap(function()
        local on_return = function()
            M.openLibraryView({ hideTopClose = true })
        end
        local opened = ChapterListing:fetchAndShow(manga, on_return, true)
        logger.dbg("zen-ui rakuyomi-return: ChapterListing result:", tostring(opened))
        if opened then
            M.closeLibraryView(library_view)
        end
    end)
    return true
end

function M.closeLibraryView(widget)
    if not (is_library_view(widget) and type(widget.onClose) == "function") then
        return false
    end
    if widget._zen_rakuyomi_onclose_running then
        return false
    end
    widget._zen_rakuyomi_onclose_running = true
    local ok, err = pcall(widget.onClose, widget)
    widget._zen_rakuyomi_onclose_running = nil
    if not ok then error(err) end
    return true
end

local function openTopMenuFromSwipe(ges)
    if not (ges and ges.direction == "south" and ges.pos
            and ges.pos.y < Screen:getHeight() * 0.05) then
        return false
    end
    local fm = FileManager.instance
    local fm_menu = fm and fm.menu
    if fm_menu and fm_menu.activation_menu ~= "tap" then
        local tab_index = fm_menu:_getTabIndexFromLocation(ges)
        fm_menu:onShowMenu(tab_index)
        return true
    end
    local ok_rui, RUI = pcall(require, "apps/reader/readerui")
    local reader_menu = ok_rui and RUI and RUI.instance and RUI.instance.menu
    if reader_menu and reader_menu.activation_menu ~= "tap" then
        local tab_index = reader_menu:_getTabIndexFromLocation(ges)
        reader_menu:onShowMenu(tab_index)
        return true
    end
    return false
end

function M.patchTopSwipe(widget)
    if not is_library_view(widget) or widget._zen_top_swipe_patched then return end
    widget._zen_top_swipe_patched = true
    local orig_onSwipe = widget.onSwipe
    widget.onSwipe = function(self, arg, ges)
        if openTopMenuFromSwipe(ges) then
            return true
        end
        if orig_onSwipe then return orig_onSwipe(self, arg, ges) end
        return false
    end
end

local function isTransientCover(widget, library_view)
    if not widget or widget == library_view then return true end
    if widget.show_parent == library_view then return true end
    local fm = FileManager.instance
    local fm_menu = fm and fm.menu
    if fm_menu and (widget == fm_menu or widget == fm_menu.menu_container) then
        return true
    end
    return widget.is_popout == true
end

local function closeCoveredLibraryView()
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return end
    local library_view, library_index
    for i = #stack, 1, -1 do
        local widget = stack[i] and stack[i].widget
        if is_library_view(widget) then
            library_view = widget
            library_index = i
            break
        end
    end
    if not library_view or library_index == #stack then return end
    local top_widget = stack[#stack] and stack[#stack].widget
    if isTransientCover(top_widget, library_view) then
        return
    end
    if type(is_real_exit_target) == "function" and is_real_exit_target(top_widget) then
        M.closeLibraryView(library_view)
    end
end

local function isTopWidget(widget)
    local stack = UIManager._window_stack
    return type(stack) == "table" and stack[#stack] and stack[#stack].widget == widget
end

local function scheduleStackCleanup()
    if UIManager._zen_rakuyomi_stack_cleanup_pending then return end
    UIManager._zen_rakuyomi_stack_cleanup_pending = true
    UIManager:nextTick(function()
        UIManager._zen_rakuyomi_stack_cleanup_pending = nil
        closeCoveredLibraryView()
    end)
end

function M.installCloseGuard(exit_target_predicate)
    if type(exit_target_predicate) == "function" then
        is_real_exit_target = exit_target_predicate
    end
    if UIManager._zen_rakuyomi_close_guard_patched then return end
    UIManager._zen_rakuyomi_close_guard_patched = true
    local orig_show = UIManager.show
    UIManager.show = function(self, ...)
        local result = orig_show(self, ...)
        scheduleStackCleanup()
        return result
    end
    local orig_close = UIManager.close
    UIManager.close = function(self, widget, ...)
        if is_library_view(widget)
                and not widget._zen_rakuyomi_onclose_running
                and type(widget.onClose) == "function" then
            if not isTopWidget(widget) then
                local result = orig_close(self, widget, ...)
                scheduleStackCleanup()
                return result
            end
            return M.closeLibraryView(widget)
        end
        local result = orig_close(self, widget, ...)
        scheduleStackCleanup()
        return result
    end
end

function M.onStandaloneNavbarInjected(widget, exit_target_predicate)
    if not is_library_view(widget) then return end
    M.patchTopSwipe(widget)
    M.installCloseGuard(exit_target_predicate)
end

function M.refreshAfterResize(widget)
    if is_library_view(widget) and type(widget.updateItems) == "function"
            and widget.item_group and widget.content_group then
        widget:updateItems(widget.itemnumber)
        return true
    end
    return false
end

function M.configureScrollBarFooter(widget)
    if not M.isScrollBarMenu(widget) or not widget.page_return_arrow then
        return false
    end
    widget.onReturn = false
    widget.page_return_arrow:hide()
    widget.page_return_arrow.show = function() end
    widget.page_return_arrow.showHide = function() end
    widget.page_return_arrow.callback = nil
    widget.page_return_arrow.hold_callback = nil
    widget.page_return_arrow.dimen = Geom:new{ w = 0, h = 0 }
    widget.page_return_arrow.getSize = function()
        return widget.page_return_arrow.dimen
    end
    return true
end

local function apply_rakuyomi()
    if rawget(_G, "__ZEN_UI_RAKUYOMI") == M then
        return
    end

    FileManager = require("apps/filemanager/filemanager")
    Geom = require("ui/geometry")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
    logger = require("logger")
    _ = require("gettext")

    _G.__ZEN_UI_RAKUYOMI = M
end

return apply_rakuyomi
