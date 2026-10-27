local utf8 = require("utf8")

local util = {}

-- UTF-8 aware string helpers ------------------------------------------------

function util.chars(s)
    local out = {}
    for _, code in utf8.codes(s) do
        out[#out + 1] = utf8.char(code)
    end
    return out
end

function util.ulen(s)
    return utf8.len(s) or #s
end

function util.usub(s, i, j)
    local n = util.ulen(s)
    j = j or n
    if i < 1 then i = 1 end
    if j > n then j = n end
    if i > j then return "" end
    local a = utf8.offset(s, i)
    local b = utf8.offset(s, j + 1)
    return b and s:sub(a, b - 1) or s:sub(a)
end

function util.pad(s, width, char)
    local n = util.ulen(s)
    if n >= width then return s end
    return s .. string.rep(char or " ", width - n)
end

function util.lpad(s, width, char)
    local n = util.ulen(s)
    if n >= width then return s end
    return string.rep(char or " ", width - n) .. s
end

function util.split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
        out[#out + 1] = part
    end
    return out
end

function util.words(s)
    local out = {}
    for w in s:gmatch("%S+") do out[#out + 1] = w end
    return out
end

function util.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Colours ---------------------------------------------------------------------

local function hex(h)
    h = h:gsub("#", "")
    return {
        tonumber(h:sub(1, 2), 16) / 255,
        tonumber(h:sub(3, 4), 16) / 255,
        tonumber(h:sub(5, 6), 16) / 255,
    }
end
util.hex = hex

-- Each theme sets the accent colour plus tinted text colours.
util.themes = {
    red    = { accent = hex("ff3347"), text = hex("e4626d"), dim = hex("6e2c33"), faint = hex("2a1316"), white = hex("ffd9dc"), ok = hex("f5c4c8") },
    mint   = { accent = hex("7cf5c2"), text = hex("c9ced6"), dim = hex("5d646e"), faint = hex("2a2e35"), white = hex("f4f6f8"), ok = hex("7cf5a0") },
    cyan   = { accent = hex("6fd3ff"), text = hex("c9ced6"), dim = hex("5d646e"), faint = hex("2a2e35"), white = hex("f4f6f8"), ok = hex("7cf5a0") },
    violet = { accent = hex("b49cff"), text = hex("c9ced6"), dim = hex("5d646e"), faint = hex("2a2e35"), white = hex("f4f6f8"), ok = hex("7cf5a0") },
    amber  = { accent = hex("ffb347"), text = hex("e0b07a"), dim = hex("6b5233"), faint = hex("2a2116"), white = hex("fff1dc"), ok = hex("7cf5a0") },
    ice    = { accent = hex("cfe6ff"), text = hex("aebccc"), dim = hex("4f5966"), faint = hex("252a31"), white = hex("ffffff"), ok = hex("7cf5a0") },
    mono   = { accent = hex("ffffff"), text = hex("b8bcc2"), dim = hex("55595f"), faint = hex("26282b"), white = hex("ffffff"), ok = hex("7cf5a0") },
}
util.theme_order = { "red", "mint", "cyan", "violet", "amber", "ice", "mono" }

-- Base palette. accent/text/dim/faint/white are filled in from the active theme.
util.palette = {
    bg     = hex("09090a"),
    bg2    = hex("120d0e"),
    text   = hex("e4626d"),
    dim    = hex("6e2c33"),
    faint  = hex("2a1316"),
    white  = hex("ffd9dc"),
    ok     = hex("7cf5a0"),
    warn   = hex("ffc66d"),
    err    = hex("ff2a3d"),
    info   = hex("7aa2ff"),
    accent = hex("ff3347"),
}

function util.set_theme(name)
    local th = util.themes[name]
    if not th then return false end
    for k, c in pairs(th) do util.palette[k] = { c[1], c[2], c[3] } end
    util.theme = name
    return true
end

function util.color(name)
    if type(name) == "table" then return name end
    return util.palette[name or "text"] or util.palette.text
end

function util.lerp(a, b, t) return a + (b - a) * t end

function util.mix(c1, c2, t)
    return { util.lerp(c1[1], c2[1], t), util.lerp(c1[2], c2[2], t), util.lerp(c1[3], c2[3], t) }
end

function util.clamp(x, a, b) return math.max(a, math.min(b, x)) end

function util.ease_out(t) return 1 - (1 - t) ^ 3 end

-- Markup ----------------------------------------------------------------------
-- "{accent}ACCESS{} granted"  ->  segments with colours.
-- {name} switches colour, {} goes back to the line's base colour, {{ is a literal {.

function util.markup(text, base)
    base = base or "text"
    local segs = {}
    local color = base
    local buf = {}
    local i = 1
    local function flush()
        if #buf > 0 then
            segs[#segs + 1] = { text = table.concat(buf), color = color }
            buf = {}
        end
    end
    while i <= #text do
        local c = text:sub(i, i)
        if c == "{" and text:sub(i + 1, i + 1) == "{" then
            buf[#buf + 1] = "{"
            i = i + 2
        elseif c == "{" then
            local close = text:find("}", i + 1, true)
            local name = close and text:sub(i + 1, close - 1)
            if name and (name == "" or util.palette[name]) then
                flush()
                color = name == "" and base or name
                i = close + 1
            else
                buf[#buf + 1] = c
                i = i + 1
            end
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    flush()
    return segs
end

function util.plain(segs)
    local t = {}
    for i, s in ipairs(segs) do t[i] = s.text end
    return table.concat(t)
end

-- Splits segments into lines at most `width` characters wide, breaking at spaces when possible.
function util.wrap(segs, width)
    local chars, colors = {}, {}
    for _, seg in ipairs(segs) do
        for _, ch in ipairs(util.chars(seg.text)) do
            chars[#chars + 1] = ch
            colors[#colors + 1] = seg.color
        end
    end
    local function build(a, b)
        local line, cur = {}, nil
        for i = a, b do
            if cur and cur.color == colors[i] then
                cur.parts[#cur.parts + 1] = chars[i]
            else
                cur = { color = colors[i], parts = { chars[i] } }
                line[#line + 1] = cur
            end
        end
        for i, c in ipairs(line) do line[i] = { text = table.concat(c.parts), color = c.color } end
        return line
    end
    local lines = {}
    local start = 1
    while #chars - start + 1 > width do
        local cut = start + width - 1
        for i = cut + 1, start + 1, -1 do
            if chars[i] == " " then cut = i - 1; break end
        end
        lines[#lines + 1] = build(start, cut)
        start = cut + 1
        while chars[start] == " " do start = start + 1 end
    end
    lines[#lines + 1] = build(start, #chars)
    return lines
end

-- Fake-data helpers (handy inside commands) ----------------------------------

local HEXCH = "0123456789abcdef"

function util.hexstr(n)
    local t = {}
    for i = 1, n do
        local k = math.random(1, 16)
        t[i] = HEXCH:sub(k, k)
    end
    return table.concat(t)
end

function util.ip()
    return ("%d.%d.%d.%d"):format(math.random(11, 223), math.random(0, 255), math.random(0, 255), math.random(1, 254))
end

function util.pick(list)
    return list[math.random(1, #list)]
end

util.GLYPHS = util.chars("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$%&*+=<>/\\|?!@^~")

function util.glyph()
    return util.GLYPHS[math.random(1, #util.GLYPHS)]
end

return util
