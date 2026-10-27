-- The case board's own data: free-form note cards joined by string.
-- Completely separate from the map markers. Saved to board.lua in the save folder.
local images = require("src.images")

local board = { cards = {}, links = {}, selected = nil, dirty_at = nil }

local FILE = "board.lua"
board.PHOTO_DIR = "board_photos"

-- note colours (name -> palette colour used to draw the card)
board.COLORS = { "accent", "warn", "info", "ok", "white", "dim" }

local KEYS = { "id", "x", "y", "title", "body", "color", "photo" }

local function q(v)
    return type(v) == "number" and tostring(v) or ("%q"):format(tostring(v))
end

function board.load()
    board.cards, board.links = {}, {}
    if not love.filesystem.getInfo(FILE) then return 0 end
    local ok, chunk = pcall(love.filesystem.load, FILE)
    if not ok or not chunk then return 0 end
    setfenv(chunk, {})
    local ok2, data = pcall(chunk)
    if ok2 and type(data) == "table" then
        for _, c in ipairs(data.cards or {}) do
            if type(c) == "table" and tonumber(c.x) and tonumber(c.y) then
                board.cards[#board.cards + 1] = c
            end
        end
        for _, l in ipairs(data.links or {}) do
            if type(l) == "table" and l.a and l.b then
                board.links[#board.links + 1] = { a = l.a, b = l.b, label = l.label }
            end
        end
    end
    return #board.cards
end

function board.save()
    local out = { "-- Qrawller case board\nreturn {\n    cards = {\n" }
    for _, c in ipairs(board.cards) do
        local parts = {}
        for _, k in ipairs(KEYS) do
            local v = c[k]
            if v ~= nil and v ~= "" then parts[#parts + 1] = k .. " = " .. q(v) end
        end
        out[#out + 1] = "        { " .. table.concat(parts, ", ") .. " },\n"
    end
    out[#out + 1] = "    },\n    links = {\n"
    for _, l in ipairs(board.links) do
        local parts = { "a = " .. l.a, "b = " .. l.b }
        if l.label and l.label ~= "" then parts[#parts + 1] = "label = " .. q(l.label) end
        out[#out + 1] = "        { " .. table.concat(parts, ", ") .. " },\n"
    end
    out[#out + 1] = "    },\n}\n"
    love.filesystem.write(FILE, table.concat(out))
    board.dirty_at = nil
end

function board.touch() board.dirty_at = love.timer.getTime() end

function board.update()
    if board.dirty_at and love.timer.getTime() - board.dirty_at > 0.6 then board.save() end
end

local function next_id()
    local id = 0
    for _, c in ipairs(board.cards) do id = math.max(id, c.id or 0) end
    return id + 1
end

function board.add(x, y)
    local c = { id = next_id(), x = x, y = y, title = "", body = "", color = "accent" }
    board.cards[#board.cards + 1] = c
    board.selected = c.id
    board.save()
    return c
end

function board.get(id)
    for _, c in ipairs(board.cards) do if c.id == id then return c end end
end

function board.remove(id)
    for i, c in ipairs(board.cards) do
        if c.id == id then
            if c.photo then love.filesystem.remove(c.photo); images.forget(c.photo) end
            for j = #board.links, 1, -1 do
                if board.links[j].a == id or board.links[j].b == id then table.remove(board.links, j) end
            end
            table.remove(board.cards, i)
            if board.selected == id then board.selected = nil end
            board.save()
            return true
        end
    end
    return false
end

-- photos ---------------------------------------------------------------------

function board.set_photo(c, name, data)
    if not images.valid(name, data) then return nil, "not a supported image (png, jpg, bmp, tga)" end
    if c.photo then love.filesystem.remove(c.photo); images.forget(c.photo) end
    love.filesystem.createDirectory(board.PHOTO_DIR)
    local ext = (name:match("%.([%w]+)$") or "png"):lower()
    local path = ("%s/c%d_%d.%s"):format(board.PHOTO_DIR, c.id, os.time(), ext)
    love.filesystem.write(path, data)
    c.photo = path
    board.save()
    return path
end

function board.clear_photo(c)
    if c.photo then love.filesystem.remove(c.photo); images.forget(c.photo); c.photo = nil; board.save() end
end

-- links ----------------------------------------------------------------------

function board.link(a, b, label)
    if a == b then return nil end
    for _, l in ipairs(board.links) do
        if (l.a == a and l.b == b) or (l.a == b and l.b == a) then
            l.label = label or l.label
            board.save()
            return l
        end
    end
    local l = { a = a, b = b, label = label }
    board.links[#board.links + 1] = l
    board.save()
    return l
end

function board.unlink(a, b)
    for i, l in ipairs(board.links) do
        if (l.a == a and l.b == b) or (l.a == b and l.b == a) then
            table.remove(board.links, i)
            board.save()
            return true
        end
    end
    return false
end

function board.are_linked(a, b)
    for _, l in ipairs(board.links) do
        if (l.a == a and l.b == b) or (l.a == b and l.b == a) then return l end
    end
end

function board.title(c)
    return (c.title and c.title ~= "") and c.title or ("card #" .. c.id)
end

return board
