local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")

local M = {}

local ROOT_DIR = DataStorage:getSettingsDir() .. "/Zen UI"
local PRESETS_DIR = ROOT_DIR .. "/presets"

local function ensure_dir(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    return lfs.mkdir(path) == true or lfs.attributes(path, "mode") == "directory"
end

local function ensure_presets_dir(kind)
    ensure_dir(ROOT_DIR)
    ensure_dir(PRESETS_DIR)
    local dir = PRESETS_DIR .. "/" .. kind
    ensure_dir(dir)
    return dir
end

local function sanitize_filename(name)
    local s = tostring(name or ""):match("^%s*(.-)%s*$") or ""
    s = s:gsub("[/\\:]+", "-")
    s = s:gsub("[^%w%._%- ]+", "_")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s*(.-)%s*$", "%1")
    if s == "" or s == "." or s == ".." then s = "preset" end
    return s .. ".lua"
end

local function preset_path(kind, name)
    return ensure_presets_dir(kind) .. "/" .. sanitize_filename(name)
end

function M.rootDir()
    ensure_dir(ROOT_DIR)
    return ROOT_DIR
end

function M.presetsDir(kind)
    return ensure_presets_dir(kind)
end

function M.list(kind)
    local dir = ensure_presets_dir(kind)
    local out = {}
    for file in lfs.dir(dir) do
        if file ~= "." and file ~= ".." and file:sub(-4) == ".lua" then
            local settings = LuaSettings:open(dir .. "/" .. file)
            local preset = settings.data
            if type(preset) == "table" then
                if type(preset.name) ~= "string" or preset.name == "" then
                    preset.name = file:gsub("%.lua$", "")
                end
                preset._filename = file
                out[#out + 1] = preset
            end
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    return out
end

function M.find(kind, name)
    for _i, preset in ipairs(M.list(kind)) do
        if preset.name == name then return preset end
    end
end

function M.save(kind, name, preset)
    if type(preset) ~= "table" then return false end
    local copy = {}
    for key, value in pairs(preset) do
        if key ~= "_filename" then copy[key] = value end
    end
    copy.name = name
    local settings = LuaSettings:open(preset_path(kind, name))
    settings.data = copy
    settings:flush()
    return true
end

function M.delete(kind, name)
    local preset = M.find(kind, name)
    local file = preset and preset._filename or sanitize_filename(name)
    return pcall(os.remove, ensure_presets_dir(kind) .. "/" .. file)
end

local function remove_tree(path)
    local mode = lfs.attributes(path, "mode")
    if mode == "file" then
        pcall(os.remove, path)
        return
    end
    if mode ~= "directory" then return end
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            remove_tree(path .. "/" .. entry)
        end
    end
    pcall(lfs.rmdir, path)
end

function M.removeAll()
    remove_tree(ROOT_DIR)
end

return M
