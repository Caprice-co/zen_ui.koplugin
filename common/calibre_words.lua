--[[
    calibre_words.lua

    Purpose
    -------
    Zen UI's browser_page_count.lua / browser_list_item_layout.lua can only
    show a page count for a book once it has a) been opened at least once
    (sidecar/.sdr) or b) been indexed by BookInfoManager's SQLite cache,
    which only stores an accurate page count for fixed-layout formats
    (PDF/CBZ) — for reflowable formats (EPUB/FB2) it is nil until the book
    is opened.

    This module fills that gap for unopened EPUB/FB2 books, trying three
    sources in order of how close they get to KOReader's own "stable page"
    number, cheapest/best first:

      1. #words custom column in metadata.calibre
         Real word count, synced back from a source like the "Kobo
         Utilities" Calibre plugin. Converted into an estimated stable
         page count using the same chars-per-synthetic-page divisor
         KOReader itself uses (default 1500). This is the closest
         approximation to what you'll see once you open the book, but
         it's still an estimate (word count -> character count uses an
         average word length, not the real text).

      2. #pages custom column in metadata.calibre
         Used only if there's no #words column to work with. This is
         someone else's page count (often the source device's own
         pagination, e.g. Kobo Nickel's), not derived from KOReader's
         chars-per-page setting at all, so treat it as a rougher
         approximation than option 1.

      3. Embedded #pages custom column inside the book file's own OPF
         Last resort, used only if metadata.calibre has neither column
         (or isn't found at all). Some Calibre setups embed custom-column
         metadata into the file itself when sending/converting a book
         (this is the same place Project: Title reads its page count
         from). Requires unzipping the book to peek at its internal .opf,
         so it's the most expensive of the three and only applies to
         EPUB.

      If none of the three produce a number, no page count is shown --
      same as today.

    Usage
    -----
        local CalibreWords = require("common/calibre_words")
        local pages = CalibreWords.getPageEstimate(filepath)
]]

local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local CalibreWords = {
    -- cache[root_dir] = { mtime = <metadata.calibre mtime>, by_lpath = { [lpath] = {words=?, pages=?} } }
    cache = {},
}

-- Average characters per word, including the trailing space. This is the
-- conventional rough estimate (~5 letters + 1 space) used when only a word
-- count is available. It will not exactly match any given book's real
-- character density (which varies with markup, dialogue, paragraphing,
-- etc.), so the resulting page estimate from #words is approximate.
local CHARS_PER_WORD = 6

-------------------------------------------------------------------------------
-- Source 1 & 2: metadata.calibre (#words and #pages custom columns)
-------------------------------------------------------------------------------

-- Walk upward from `dir` looking for a metadata.calibre file. Returns the
-- full path to metadata.calibre and the directory it lives in (the
-- "device root" that lpath entries inside metadata.calibre are relative
-- to), or nil if none is found within `max_levels` parent directories.
local function findMetadataCalibre(dir, max_levels)
    max_levels = max_levels or 6
    local cur = dir
    for _ = 1, max_levels do
        local candidate = cur .. "/metadata.calibre"
        if lfs.attributes(candidate, "mode") == "file" then
            return candidate, cur
        end
        local parent = cur:match("^(.*)/[^/]+$")
        if not parent or parent == cur then break end
        cur = parent
    end
    return nil, nil
end

-- Pull a numeric value out of a metadata.calibre entry's user_metadata for
-- a given custom column name (e.g. "#words", "#pages"), or nil.
local function readCustomColumn(entry, column)
    local um = entry.user_metadata
    if type(um) == "table" and type(um[column]) == "table" then
        local v = um[column]["#value#"]
        if type(v) == "number" then
            return v
        end
    end
    return nil
end

-- Build (or refresh, if the file's mtime changed since last time) the
-- lpath -> {words, pages} index for a given metadata.calibre file. Cached
-- per device root so a whole-library scroll only parses the JSON once.
local function loadIndex(meta_path, root)
    local attr = lfs.attributes(meta_path)
    local mtime = attr and attr.modification
    local cached = CalibreWords.cache[root]
    if cached and cached.mtime == mtime then
        return cached.by_lpath
    end

    local f = io.open(meta_path, "r")
    if not f then
        logger.warn("zen-ui:calibre_words: could not open", meta_path)
        return nil
    end
    local content = f:read("*a")
    f:close()

    local ok, data = pcall(json.decode, content)
    if not ok or type(data) ~= "table" then
        logger.warn("zen-ui:calibre_words: failed to parse", meta_path)
        return nil
    end

    local by_lpath = {}
    for _, entry in ipairs(data) do
        local lpath = entry.lpath
        if lpath then
            by_lpath[lpath] = {
                words = readCustomColumn(entry, "#words"),
                pages = readCustomColumn(entry, "#pages"),
            }
        end
    end

    CalibreWords.cache[root] = { mtime = mtime, by_lpath = by_lpath }
    return by_lpath
end

-- Return { words = n|nil, pages = n|nil } as recorded in Calibre's
-- metadata.calibre for `filepath`, or nil if no metadata.calibre could be
-- found for it at all.
local function getCalibreColumns(filepath)
    local dir = filepath:match("^(.*)/[^/]+$")
    if not dir then return nil end

    local meta_path, root = findMetadataCalibre(dir)
    if not meta_path then return nil end

    local by_lpath = loadIndex(meta_path, root)
    if not by_lpath then return nil end

    -- lpath entries in metadata.calibre are relative to `root`, using "/"
    -- as the separator (this matches KOReader's own path separators).
    local lpath = filepath:sub(#root + 2) -- strip "root/"
    return by_lpath[lpath]
end

-- Return the Calibre-recorded word count for `filepath`, or nil.
-- (Kept as its own function for backwards compatibility / direct use.)
function CalibreWords.getWordCount(filepath)
    local cols = getCalibreColumns(filepath)
    return cols and cols.words or nil
end

-- Return the Calibre-recorded #pages custom-column value for `filepath`,
-- or nil. Note this is *not* KOReader's stable page count -- it's whatever
-- your #pages column holds (often a source device's own pagination), used
-- here only as a fallback when there's no #words column to estimate from.
function CalibreWords.getPagesColumn(filepath)
    local cols = getCalibreColumns(filepath)
    return cols and cols.pages or nil
end

-- Convert a word count into an estimated "stable page" count using the
-- given chars-per-synthetic-page divisor (defaults to 1500, KOReader's
-- own default for the stable page number mode).
function CalibreWords.estimatePages(words, chars_per_page)
    if not words or words <= 0 then return nil end
    chars_per_page = chars_per_page or 1500
    local est_chars = words * CHARS_PER_WORD
    local pages = math.floor(est_chars / chars_per_page + 0.5)
    if pages < 1 then pages = 1 end
    return pages
end

-------------------------------------------------------------------------------
-- Source 3: #pages custom column embedded inside the book's own OPF
-- (last resort, EPUB only -- same place Project: Title reads its count
-- from). Requires shelling out to `unzip`, so this is the slow path.
-------------------------------------------------------------------------------

local function getEmbeddedOpfPages(filepath)
    if not filepath:lower():match("%.epub$") and not filepath:lower():match("%.kepub%.epub$") then
        return nil
    end

    -- Locate the .opf file inside the archive.
    local locate_cmd = "unzip -lqq \"" .. filepath .. "\" \"*.opf\""
    local opf_file = nil
    local list_out = io.popen(locate_cmd)
    if list_out then
        local line = list_out:read()
        if line then
            opf_file = line:match("(%S+%.opf)%s*$")
        end
        list_out:close()
    end
    if not opf_file then return nil end

    -- Dump the .opf and scan for the #pages custom column's value. Calibre
    -- embeds custom-column metadata as a JSON blob (sometimes HTML-entity
    -- escaped) inside a <meta> tag; the #value# key can land on the same
    -- line as "#pages" or a following line depending on how it was
    -- serialized, so check both.
    local expand_cmd = "unzip -p \"" .. filepath .. "\" \"" .. opf_file .. "\""
    local dump = io.popen(expand_cmd)
    if not dump then return nil end

    local found_pages_key = false
    local found_value = nil
    for line in dump:lines() do
        if found_pages_key then
            found_value = line:match("\"#value#\": (%d+),")
            if found_value then break end
            -- "category_sort" is always present and comes after #value# in
            -- Calibre's alphabetical serialization -- if we hit it first,
            -- this column had no value.
            if line:match("\"category_sort\":") then break end
        else
            if line:match("#pages") then
                found_pages_key = true
                found_value = line:match("&quot;#value#&quot;: (%d+),")
                if found_value then break end
            end
        end
    end
    dump:close()

    local n = found_value and tonumber(found_value)
    if n and n > 0 then return n end
    return nil
end

-------------------------------------------------------------------------------
-- Combined entry point
-------------------------------------------------------------------------------

-- Try, in order: #words (estimated via chars-per-page) -> #pages column
-- (used as-is) -> embedded OPF #pages (used as-is). Returns the first hit,
-- or nil if none of the three have anything for this book.
function CalibreWords.getPageEstimate(filepath)
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local chars_per_page = plugin and type(plugin.config) == "table"
        and type(plugin.config.browser_page_count) == "table"
        and plugin.config.browser_page_count.calibre_chars_per_page

    local cols = getCalibreColumns(filepath)

    if cols and cols.words then
        local est = CalibreWords.estimatePages(cols.words, chars_per_page)
        if est then return est end
    end

    if cols and cols.pages and cols.pages > 0 then
        return cols.pages
    end

    local ok, embedded = pcall(getEmbeddedOpfPages, filepath)
    if ok and embedded then
        return embedded
    end

    return nil
end

return CalibreWords
