-- The file vault: real folders and files inside the save folder (…/qrawller/vault).
-- Used by the FILES widget and the ls / cat terminal commands.
local images = require("src.images")

local vault = { ROOT = "vault", pending = {} }

local TEXT_EXT = {
    txt = true, md = true, log = true, csv = true, json = true, lua = true, ini = true,
    cfg = true, xml = true, html = true, yml = true, yaml = true, nfo = true,
}

function vault.init()
    love.filesystem.createDirectory(vault.ROOT)
end

function vault.join(a, b) return a .. "/" .. b end

function vault.basename(path) return path:match("([^/\\]+)$") or path end

function vault.parent(path)
    local p = path:match("^(.*)/[^/]+$")
    return p or vault.ROOT
end

function vault.ext(name) return (name:match("%.([%w]+)$") or ""):lower() end

function vault.kind(path)
    local info = love.filesystem.getInfo(path)
    if info and info.type == "directory" then return "folder" end
    local ext = vault.ext(path)
    if TEXT_EXT[ext] then return "text" end
    if images.is_image_name(path) then return "image" end
    return "file"
end

function vault.clean_name(name)
    name = tostring(name or ""):gsub('[/\\:%*%?"<>|%c]', ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name == "." or name == ".." then return nil end
    return name
end

function vault.exists(path) return love.filesystem.getInfo(path) ~= nil end

-- "photo.png" -> "photo (2).png" if needed
function vault.unique(dir, name)
    if not vault.exists(vault.join(dir, name)) then return name end
    local stem, ext = name:match("^(.-)(%.[^.]*)$")
    if not stem or stem == "" then stem, ext = name, "" end
    local n = 2
    while vault.exists(vault.join(dir, stem .. " (" .. n .. ")" .. ext)) do n = n + 1 end
    return stem .. " (" .. n .. ")" .. ext
end

-- folders first, then files, alphabetical
function vault.list(dir)
    local out = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
        local path = vault.join(dir, name)
        local info = love.filesystem.getInfo(path)
        if info then
            out[#out + 1] = {
                name = name, path = path,
                kind = info.type == "directory" and "folder" or vault.kind(path),
                size = info.size or 0, modtime = info.modtime,
            }
        end
    end
    table.sort(out, function(a, b)
        if (a.kind == "folder") ~= (b.kind == "folder") then return a.kind == "folder" end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

function vault.count(dir)
    return #love.filesystem.getDirectoryItems(dir)
end

function vault.mkdir(dir, name)
    name = vault.unique(dir, vault.clean_name(name) or "new folder")
    love.filesystem.createDirectory(vault.join(dir, name))
    return vault.join(dir, name)
end

function vault.new_text(dir, name)
    name = vault.unique(dir, vault.clean_name(name) or "untitled.txt")
    love.filesystem.write(vault.join(dir, name), "")
    return vault.join(dir, name)
end

function vault.read(path)
    return love.filesystem.read(path) or ""
end

function vault.write(path, data)
    love.filesystem.write(path, data)
    images.forget(path)
end

-- text edits are saved a moment after typing stops
function vault.write_later(path, data)
    vault.pending[path] = { data = data, at = love.timer.getTime() }
end

function vault.flush(force)
    for path, p in pairs(vault.pending) do
        if force or love.timer.getTime() - p.at > 0.6 then
            if vault.exists(path) then love.filesystem.write(path, p.data) end
            vault.pending[path] = nil
        end
    end
end

function vault.is_saved(path) return vault.pending[path] == nil end

function vault.remove(path)
    local info = love.filesystem.getInfo(path)
    if not info then return end
    if info.type == "directory" then
        for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do
            vault.remove(vault.join(path, name))
        end
    end
    vault.pending[path] = nil
    images.forget(path)
    love.filesystem.remove(path)
end

function vault.copy(src, dst)
    local info = love.filesystem.getInfo(src)
    if not info then return end
    if info.type == "directory" then
        love.filesystem.createDirectory(dst)
        for _, name in ipairs(love.filesystem.getDirectoryItems(src)) do
            vault.copy(vault.join(src, name), vault.join(dst, name))
        end
    else
        love.filesystem.write(dst, love.filesystem.read(src) or "")
    end
end

-- love.filesystem has no rename, so copy then delete
function vault.rename(path, new_name)
    new_name = vault.clean_name(new_name)
    if not new_name or new_name == vault.basename(path) then return path end
    local dir = vault.parent(path)
    local target = vault.join(dir, vault.unique(dir, new_name))
    vault.flush(true)
    vault.copy(path, target)
    vault.remove(path)
    return target
end

-- bytes from a dropped file
function vault.import(dir, name, data)
    name = vault.unique(dir, vault.clean_name(name) or "file")
    love.filesystem.write(vault.join(dir, name), data)
    return vault.join(dir, name)
end

-- a whole folder dropped onto the window (real path on disk)
function vault.import_folder(dir, real_path)
    local mount = "_drop_" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
    if not love.filesystem.mount(real_path, mount) then return nil end
    local name = vault.unique(dir, vault.clean_name(vault.basename(real_path:gsub("[/\\]+$", ""))) or "folder")
    local target = vault.join(dir, name)
    vault.copy(mount, target)
    love.filesystem.unmount(real_path)
    return target
end

function vault.size_str(n)
    n = n or 0
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return ("%.1f KB"):format(n / 1024) end
    return ("%.1f MB"):format(n / 1024 / 1024)
end

-- folder size, recursively
function vault.total(path)
    local info = love.filesystem.getInfo(path)
    if not info then return 0 end
    if info.type ~= "directory" then return info.size or 0 end
    local sum = 0
    for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do sum = sum + vault.total(vault.join(path, name)) end
    return sum
end

-- opens a vault folder in Explorer / Finder
function vault.reveal(path)
    local base = love.filesystem.getSaveDirectory() .. "/" .. (path or vault.ROOT)
    base = base:gsub("\\", "/")
    if base:sub(1, 1) ~= "/" then base = "/" .. base end
    love.system.openURL("file://" .. base)
end

-- "vault/a/b" -> "vault / a / b"
function vault.pretty(path)
    return (path:gsub("/", " / "))
end

return vault
