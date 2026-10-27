-- Terminal access to the file vault (the FILES panel).
local vault = require("src.vault")

local function esc(s) return (tostring(s or ""):gsub("{", "{{")) end

-- resolve a path argument against the vault root
local function resolve(rest)
    rest = (rest or ""):gsub("^/+", ""):gsub("/+$", "")
    if rest == "" or rest == "vault" then return vault.ROOT end
    if rest:sub(1, 6) == "vault/" then return rest end
    return vault.join(vault.ROOT, rest)
end

return {
    {
        name = "files",
        aliases = { "vault" },
        help = "open the files panel",
        category = "files",
        run = function(t)
            t.ui.show_tab("FILES")
            t.print("{accent}▸{} files panel  ·  " .. vault.size_str(vault.total(vault.ROOT)) .. " stored")
        end,
    },
    {
        name = "ls",
        aliases = { "dir" },
        help = "list files in the vault",
        usage = "ls [folder]",
        category = "files",
        run = function(t, args, rest)
            local dir = resolve(rest)
            if not vault.exists(dir) then return t.print("no such folder: " .. esc(rest), "err") end
            local items = vault.list(dir)
            t.print("{dim}" .. vault.pretty(dir) .. "{}")
            if #items == 0 then return t.print("  {dim}(empty)") end
            for _, it in ipairs(items) do
                local icon = it.kind == "folder" and "{accent}⊞" or (it.kind == "image" and "{info}■" or (it.kind == "text" and "{white}≡" or "{dim}□"))
                local meta = it.kind == "folder" and (vault.count(it.path) .. " items") or vault.size_str(it.size)
                t.print(icon .. " {}" .. t.pad(esc(it.name), 28) .. "{dim}" .. meta)
                t.sound("tick", { pitch = 1.3, volume = 0.3 })
                t.wait(0.015)
            end
        end,
    },
    {
        name = "cat",
        aliases = { "read" },
        help = "print a text file from the vault",
        usage = "cat <file>",
        category = "files",
        run = function(t, args, rest)
            local path = resolve(rest)
            local info = love.filesystem.getInfo(path)
            if not info then return t.print("no such file: " .. esc(rest), "err") end
            if info.type == "directory" then return t.print("that's a folder — try {accent}ls " .. esc(rest), "warn") end
            if vault.kind(path) == "image" then return t.print("that's an image (" .. vault.size_str(info.size) .. ") — open it in the files panel", "warn") end
            local data = vault.read(path)
            t.print("{dim}── " .. esc(vault.basename(path)) .. " " .. string.rep("─", 30))
            if data == "" then t.print("{dim}(empty)") else t.type(esc(data), "text", 400) end
            t.print("{dim}" .. string.rep("─", 40))
        end,
    },
    {
        name = "mkdir",
        help = "make a folder in the vault",
        usage = "mkdir <name>",
        category = "files",
        run = function(t, args, rest)
            if rest == "" then return t.print("usage: mkdir <name>", "dim") end
            local p = vault.mkdir(vault.ROOT, rest)
            t.print("{accent}⊞{} created " .. esc(vault.pretty(p)))
            t.sound("place", { volume = 0.5 })
        end,
    },
    {
        name = "write",
        aliases = { "save" },
        help = "write text to a vault file",
        usage = "write <file> <text>",
        category = "files",
        run = function(t, args, rest)
            local name = args[1]
            if not name then return t.print("usage: write <file> <text>", "dim") end
            local text = rest:sub(#name + 1):gsub("^%s+", "")
            local path = resolve(name)
            if vault.ext(path) == "" then path = path .. ".txt" end
            vault.write(path, text)
            t.print("{accent}≡{} saved " .. esc(vault.basename(path)) .. "  {dim}" .. vault.size_str(#text))
            t.sound("beep", { volume = 0.4 })
        end,
    },
}
