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
        and (path == directory or path:sub(1, #directory + 1) == directory .. "/")
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

local storage_path_loaded = false
local storage_path_cache

local function get_storage_path()
    if storage_path_loaded then
        return storage_path_cache
    end
    storage_path_loaded = true
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
    storage_path_cache = normalize_path(storage)
    logger.dbg("zen-ui rakuyomi-return: cached storage path:", tostring(storage_path_cache))
    return storage_path_cache
end

function M.isChapterFile(path)
    if type(path) ~= "string" then
        logger.dbg("zen-ui rakuyomi-return: chapter detection rejected non-string path")
        return false
    end

    local storage = get_storage_path()
    local in_storage = path_is_inside(path, storage) == true
    logger.dbg(
        "zen-ui rakuyomi-return: chapter detection:",
        "path=", path,
        "storage=", tostring(storage),
        "in_storage=", tostring(in_storage))
    return in_storage
end

local function target_from_origin(origin)
    if type(origin) == "table" and origin.type == "SUCCESS" then
        origin = origin.body
    end
    if type(origin) == "table" and origin.type == "ERROR" then
        logger.warn(
            "zen-ui rakuyomi-return: getOrigin error response:",
            tostring(origin.status), tostring(origin.message))
        return nil
    end
    if origin == nil then
        -- No embedded origin comment: legacy chapter downloaded before rakuyomi's
        -- ZIP-comment origin feature. Unrecoverable; expected, not an error.
        logger.dbg("zen-ui rakuyomi-return: getOrigin has no origin comment (legacy chapter)")
        return nil
    end
    if type(origin) ~= "table" or type(origin.manga_id) ~= "table" then
        local manga_id_type = "nil"
        if type(origin) == "table" then
            manga_id_type = type(origin.manga_id)
        end
        logger.warn(
            "zen-ui rakuyomi-return: getOrigin unexpected response:",
            "type=", type(origin),
            "manga_id_type=", manga_id_type)
        return nil
    end
    local manga_id = origin.manga_id.manga_id
    local source_id = origin.manga_id.source_id
    if type(manga_id) ~= "string" or type(source_id) ~= "string" then
        logger.warn(
            "zen-ui rakuyomi-return: getOrigin missing ids:",
            "source=", tostring(source_id),
            "manga=", tostring(manga_id),
            "chapter=", tostring(origin.chapter_id))
        return nil
    end
    return {
        id = manga_id,
        chapter_id = origin.chapter_id,
        source = { id = source_id },
    }
end

local function append_origin_candidate(candidates, label, object, call_style)
    if type(object) == "table" and type(object.getOrigin) == "function" then
        candidates[#candidates + 1] = {
            label = label,
            object = object,
            call_style = call_style or "method",
        }
    end
end

local function append_origin_candidates(candidates, label, object)
    -- RakuyomiShared:getOrigin is a colon method; function-style call passes the
    -- path as self, leaving filepath nil and crashing io.open. Method style only.
    append_origin_candidate(candidates, label .. " method", object, "method")
end

local function call_origin_candidate(candidate, path)
    logger.dbg(
        "zen-ui rakuyomi-return: trying getOrigin:",
        candidate.label,
        "style=", candidate.call_style)
    if candidate.call_style == "function" then
        return pcall(candidate.object.getOrigin, path)
    end
    return pcall(candidate.object.getOrigin, candidate.object, path)
end

local function get_origin_from_document(path)
    local ok_registry, DocumentRegistry = pcall(require, "document/documentregistry")
    if not ok_registry then
        return false, DocumentRegistry
    end

    local refcount = 0
    if type(DocumentRegistry.getReferenceCount) == "function" then
        refcount = DocumentRegistry:getReferenceCount(path) or 0
    end

    local doc = DocumentRegistry:openDocument(path)
    if type(doc) ~= "table" or type(doc.getOrigin) ~= "function" then
        if doc and refcount > 0 then
            pcall(DocumentRegistry.closeDocument, DocumentRegistry, path)
        elseif doc and type(doc.close) == "function" then
            pcall(doc.close, doc)
        end
        return false, "document has no getOrigin"
    end

    local ok_origin, origin = pcall(doc.getOrigin, doc, path)
    if ok_origin and origin == nil then
        ok_origin, origin = pcall(doc.getOrigin, doc)
    end

    if refcount > 0 then
        pcall(DocumentRegistry.closeDocument, DocumentRegistry, path)
    elseif type(doc.close) == "function" then
        pcall(doc.close, doc)
    else
        pcall(DocumentRegistry.closeDocument, DocumentRegistry, path)
    end

    return ok_origin, origin
end

local function resolve_origin_target(path)
    local candidates = {}

    append_origin_candidates(candidates, "global RakuyomiShared", rawget(_G, "RakuyomiShared"))
    append_origin_candidates(candidates, "package.loaded RakuyomiShared", package.loaded.RakuyomiShared)

    local ok_shared, RakuyomiShared = pcall(require, "RakuyomiShared")
    if ok_shared then
        append_origin_candidates(candidates, "require RakuyomiShared", RakuyomiShared)
    else
        logger.dbg("zen-ui rakuyomi-return: require RakuyomiShared failed:", tostring(RakuyomiShared))
    end

    local ok_backend, Backend = pcall(require, "Backend")
    if ok_backend then
        append_origin_candidate(candidates, "require Backend", Backend, "function")
    else
        logger.dbg("zen-ui rakuyomi-return: require Backend failed:", tostring(Backend))
    end

    local fm = FileManager and FileManager.instance
    local rakuyomi = fm and fm.rakuyomi
    append_origin_candidates(candidates, "FileManager.rakuyomi", rakuyomi)
    append_origin_candidates(candidates, "FileManager.rakuyomi.shared", rakuyomi and rakuyomi.shared)
    append_origin_candidates(
        candidates,
        "FileManager.rakuyomi.RakuyomiShared",
        rakuyomi and rakuyomi.RakuyomiShared)

    for _i, candidate in ipairs(candidates) do
        local ok_origin, origin = call_origin_candidate(candidate, path)
        if ok_origin then
            logger.dbg("zen-ui rakuyomi-return: getOrigin returned:", candidate.label)
            local target = target_from_origin(origin)
            if target then
                return target, candidate.label
            end
        else
            logger.warn(
                "zen-ui rakuyomi-return: getOrigin failed:",
                candidate.label,
                tostring(origin))
        end
    end

    if #candidates == 0 then
        logger.dbg("zen-ui rakuyomi-return: no module getOrigin candidates")
    end
    logger.dbg("zen-ui rakuyomi-return: trying getOrigin: document")
    local ok_doc_origin, doc_origin = get_origin_from_document(path)
    if ok_doc_origin then
        logger.dbg("zen-ui rakuyomi-return: getOrigin returned: document")
        local target = target_from_origin(doc_origin)
        if target then
            return target, "document"
        end
    else
        logger.warn("zen-ui rakuyomi-return: getOrigin failed: document", tostring(doc_origin))
    end

    return nil, "all Rakuyomi getOrigin candidates failed or returned no target"
end

function M.resolveChapterFile(path)
    if not M.isChapterFile(path) then
        logger.warn("zen-ui rakuyomi-return: resolver rejected path:", tostring(path))
        return nil
    end

    local target, origin_source = resolve_origin_target(path)
    if not target then
        logger.warn("zen-ui rakuyomi-return: getOrigin unavailable:", tostring(origin_source))
        return nil
    end
    logger.dbg(
        "zen-ui rakuyomi-return: resolver matched:",
        "origin=", tostring(origin_source),
        "source=", target.source.id,
        "manga=", target.id,
        "chapter=", tostring(target.chapter_id))
    return target
end

function M.resolveTarget(file, reason)
    if type(file) ~= "string" or file == "" then return nil end
    local has_detector = type(M.isChapterFile) == "function"
    local is_chapter = has_detector and M.isChapterFile(file) == true
    local has_resolver = type(M.resolveChapterFile) == "function"
    logger.dbg(
        "zen-ui rakuyomi-return: target resolve:",
        "reason=", tostring(reason),
        "file=", file,
        "has_detector=", tostring(has_detector),
        "is_chapter=", tostring(is_chapter),
        "has_resolver=", tostring(has_resolver))
    if not (is_chapter and has_resolver) then return nil end

    local target = M.resolveChapterFile(file)
    if target then
        logger.dbg(
            "zen-ui rakuyomi-return: target resolved:",
            "reason=", tostring(reason),
            "target_source=", tostring(target.source and target.source.id),
            "target_manga=", tostring(target.id))
    else
        logger.warn(
            "zen-ui rakuyomi-return: owned file without target:",
            "reason=", tostring(reason),
            "file=", file)
    end
    return target
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

-- Capture the Rakuyomi return target for *any* book open, not only the
-- Continue-tab resume. showReader is the single choke point every open flows
-- through, and it broadcasts "ShowingReader" (→ onShowingReader, which persists
-- the target) before opening. Detect chapter files here so opening from a file
-- list / history / etc. still returns to the chapter list.
function M.installShowReaderCapture()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._zen_rakuyomi_showReader_patched then return end
    ReaderUI._zen_rakuyomi_showReader_patched = true
    local orig_reader_showReader = ReaderUI.showReader
    function ReaderUI:showReader(file, ...)
        if type(file) == "string"
                and rawget(_G, "__ZEN_UI_RAKUYOMI_RETURN_TARGET") == nil then
            local target = M.resolveTarget(file, "showReader")
            if target then
                _G.__ZEN_UI_LIBRARY_SOURCE_TAB = "manga"
                _G.__ZEN_UI_FORCE_SOURCE_TAB_RESTORE = true
                _G.__ZEN_UI_RAKUYOMI_RETURN_TARGET = target
            end
        end
        return orig_reader_showReader(self, file, ...)
    end
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
    M.installShowReaderCapture()
end

return apply_rakuyomi
