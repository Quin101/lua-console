-- Loads every .lua file in the commands/ folder.
-- Files in the save folder's commands/ (%APPDATA%/LOVE/qrawller/commands on Windows)
-- are picked up as well, so you can add commands without rebuilding the .exe.
local commands = { list = {}, by_name = {}, errors = {} }

local function register(def, file)
    if type(def) ~= "table" or type(def.name) ~= "string" or type(def.run) ~= "function" then
        commands.errors[#commands.errors + 1] = file .. ": must return { name = ..., run = function(t, args) end }"
        return
    end
    def.name = def.name:lower()
    def.file = file
    if not commands.by_name[def.name] then commands.list[#commands.list + 1] = def end
    commands.by_name[def.name] = def
    for _, a in ipairs(def.aliases or {}) do commands.by_name[a:lower()] = def end
end

function commands.load()
    commands.list, commands.by_name, commands.errors = {}, {}, {}
    local files = love.filesystem.getDirectoryItems("commands")
    table.sort(files)
    for _, f in ipairs(files) do
        if f:match("%.lua$") and not f:match("^_") then
            local path = "commands/" .. f
            local ok, chunk = pcall(love.filesystem.load, path)
            local ok2, def
            if ok and chunk then ok2, def = pcall(chunk) end
            if not ok then
                commands.errors[#commands.errors + 1] = tostring(chunk)
            elseif not ok2 then
                commands.errors[#commands.errors + 1] = f .. ": " .. tostring(def)
            elseif type(def) == "table" and def.name == nil and #def > 0 then
                for _, d in ipairs(def) do register(d, f) end   -- a file can return several commands
            else
                register(def, f)
            end
        end
    end
    table.sort(commands.list, function(a, b) return a.name < b.name end)
    return #commands.list
end

function commands.find(name)
    return commands.by_name[name]
end

function commands.complete(prefix)
    local out = {}
    for _, c in ipairs(commands.list) do
        if not c.hidden and c.name:sub(1, #prefix) == prefix then out[#out + 1] = c.name end
    end
    return out
end

local function distance(a, b)
    local la, lb = #a, #b
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = { [0] = i }
        for j = 1, lb do
            local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[lb]
end

-- closest command name for "did you mean ...?"
function commands.suggest(name)
    local best, bd = nil, 3
    for n in pairs(commands.by_name) do
        local d = distance(name, n)
        if d < bd then best, bd = n, d end
    end
    return best
end

return commands
