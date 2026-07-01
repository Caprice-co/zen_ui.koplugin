local M = {}

local LEGACY_NEW_MTIME_KEY = "zen_auto_tbr_mtime"
local NEW_MTIME_KEY = "zen_new_mtime"

local function is_explicit_status(status)
    return status == "reading" or status == "complete" or status == "abandoned"
end

function M.isNewStatus(status, percent_finished)
    return percent_finished == nil and not is_explicit_status(status)
end

function M.getEffectiveStatus(status, percent_finished)
    if is_explicit_status(status) then
        return status
    end
    if M.isNewStatus(status, percent_finished) then
        return "new"
    end
    return "reading"
end

function M.includeNewInTBREnabled()
    local ok, ConfigManager = pcall(require, "config/manager")
    if not ok then return false end
    local cfg = ConfigManager.get()
    return cfg and cfg.group_view
        and cfg.group_view.include_new_in_tbr == true
end

local IMAGE_EXTS = {
    jpg = true, jpeg = true, png = true, gif = true, bmp = true,
    tiff = true, tif = true, webp = true, svg = true, ico = true,
    heic = true, heif = true, avif = true,
}

function M.isImageFile(file_path)
    if not file_path then return false end
    local ext = file_path:match("^.+%.([^%.]+)$")
    if not ext then return false end
    return IMAGE_EXTS[ext:lower()] == true
end

local function flushDocSettings(doc_settings)
    if type(doc_settings.flush) == "function" then
        pcall(doc_settings.flush, doc_settings)
    end
end

local function getSidecarMtime(DocSettings, file_path, lfs)
    if type(DocSettings.findSidecarFile) ~= "function" then return nil end
    local ok, sidecar_file = pcall(DocSettings.findSidecarFile, DocSettings, file_path)
    if not ok or not sidecar_file then return nil end
    return lfs.attributes(sidecar_file, "modification")
end

local function getFileContext(file_path, doc_settings)
    if not file_path or M.isImageFile(file_path) then return end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs then return end
    local attr = lfs.attributes(file_path)
    if not attr or attr.mode ~= "file" then return end

    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds or not DocSettings then return end
    if not doc_settings then
        if not DocSettings:hasSidecarFile(file_path) then return end
        local ok_doc, doc = pcall(DocSettings.open, DocSettings, file_path)
        if not ok_doc or not doc then return end
        doc_settings = doc
    end
    return lfs, DocSettings, doc_settings, attr.modification
end

function M.getComputedStatus(file_path, status, percent_finished, doc_settings)
    local effective_status = M.getEffectiveStatus(status, percent_finished)
    if effective_status == "new" or M.isImageFile(file_path) then
        return effective_status
    end

    local lfs, DocSettings, doc, current_mtime = getFileContext(file_path, doc_settings)
    if not doc or current_mtime == nil then return effective_status end

    local stored_mtime = tonumber(doc:readSetting(NEW_MTIME_KEY))
    if stored_mtime ~= nil then
        if current_mtime ~= stored_mtime then
            doc:saveSetting(NEW_MTIME_KEY, current_mtime)
            flushDocSettings(doc)
        end
        return "new"
    end

    local sidecar_mtime = getSidecarMtime(DocSettings, file_path, lfs)
    if sidecar_mtime ~= nil and current_mtime > sidecar_mtime then
        doc:saveSetting(NEW_MTIME_KEY, current_mtime)
        flushDocSettings(doc)
        return "new"
    end
    return effective_status
end

function M.acknowledgeNewVersion(doc_settings)
    if not doc_settings then return false end
    local changed = doc_settings:readSetting(NEW_MTIME_KEY) ~= nil
        or doc_settings:readSetting(LEGACY_NEW_MTIME_KEY) ~= nil
    if changed then
        doc_settings:delSetting(NEW_MTIME_KEY)
        doc_settings:delSetting(LEGACY_NEW_MTIME_KEY)
    end
    return changed
end

function M.migrateLegacyMarker(file_path, status, doc_settings)
    if not doc_settings then return status, false end
    local legacy_mtime = tonumber(doc_settings:readSetting(LEGACY_NEW_MTIME_KEY))
    if legacy_mtime == nil then return status, false end

    local lfs = require("libs/libkoreader-lfs")
    local current_mtime = lfs.attributes(file_path, "modification")
    local summary_changed = status == "abandoned"
    doc_settings:delSetting(LEGACY_NEW_MTIME_KEY)

    if summary_changed then
        local summary = doc_settings:readSetting("summary") or {}
        summary.status = nil
        if current_mtime ~= nil then
            doc_settings:saveSetting(NEW_MTIME_KEY, current_mtime)
        end
        require("apps/filemanager/filemanagerutil").saveSummary(doc_settings, summary)
        require("ui/widget/booklist").setBookInfoCacheProperty(file_path, "status", nil)
        return nil, true
    end

    if current_mtime ~= nil and current_mtime ~= legacy_mtime then
        doc_settings:saveSetting(NEW_MTIME_KEY, current_mtime)
    end
    flushDocSettings(doc_settings)
    return status, true
end

function M.getEffectiveStatusFromInfo(book_info)
    if type(book_info) ~= "table" then
        return "new"
    end
    return M.getEffectiveStatus(book_info.status, book_info.percent_finished)
end

function M.getEffectiveStatusFromFile(file_path)
    local ok_bl, BookList = pcall(require, "ui/widget/booklist")
    local book_info
    if ok_bl and type(BookList) == "table" and type(BookList.getBookInfo) == "function" then
        book_info = BookList.getBookInfo(file_path)
    end

    local status = book_info and book_info.status
    local percent_finished = book_info and book_info.percent_finished
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if ok_ds and DocSettings and DocSettings:hasSidecarFile(file_path) then
        local ok_doc, doc = pcall(DocSettings.open, DocSettings, file_path)
        if ok_doc and doc then
            local summary = doc:readSetting("summary")
            status = summary and summary.status
            percent_finished = doc:readSetting("percent_finished")
            return M.getComputedStatus(file_path, status, percent_finished, doc)
        end
    end
    return M.getComputedStatus(file_path, status, percent_finished)
end

return M
