local M = {}

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

function M.getEffectiveStatusFromInfo(book_info)
    if type(book_info) ~= "table" then
        return "new"
    end
    return M.getEffectiveStatus(book_info.status, book_info.percent_finished)
end

function M.getEffectiveStatusFromFile(file_path)
    local ok_bl, BookList = pcall(require, "ui/widget/booklist")
    if not ok_bl or type(BookList) ~= "table" or type(BookList.getBookInfo) ~= "function" then
        return "new"
    end
    local book_info = BookList.getBookInfo(file_path)
    if book_info
            and book_info.status == "reading"
            and book_info.percent_finished == nil then
        local ok_ds, DocSettings = pcall(require, "docsettings")
        if ok_ds and DocSettings and DocSettings:hasSidecarFile(file_path) then
            local ok_doc, doc = pcall(DocSettings.open, DocSettings, file_path)
            if ok_doc and doc then
                local summary = doc:readSetting("summary")
                return M.getEffectiveStatus(
                    summary and summary.status,
                    doc:readSetting("percent_finished")
                )
            end
        end
    end
    return M.getEffectiveStatusFromInfo(book_info)
end

return M
