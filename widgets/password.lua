-- PASSWORD FORGE: generate strong passwords and measure the strength of any
-- password you type. Everything happens locally; nothing is sent anywhere.
local util = require("src.util")

local LOWER = "abcdefghijkmnpqrstuvwxyz"       -- no l
local LOWER_ALL = "abcdefghijklmnopqrstuvwxyz"
local UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ"        -- no I, O
local UPPER_ALL = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local DIGITS = "23456789"                       -- no 0, 1
local DIGITS_ALL = "0123456789"
local SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?/"

local W = {
    title = "PASSWORD FORGE",
    tab = "KEYS",
    order = 4,
    height = "fill",
    width = 0.42,
    collapsible = false,
}

-- strength from Shannon-style entropy over the character classes present ------

local function class_pool(s, exact)
    local pool, classes = 0, {}
    if s:find("[a-z]") then pool = pool + 26; classes[#classes + 1] = "lower" end
    if s:find("[A-Z]") then pool = pool + 26; classes[#classes + 1] = "upper" end
    if s:find("%d") then pool = pool + 10; classes[#classes + 1] = "digit" end
    if s:find("[^%w]") then pool = pool + 32; classes[#classes + 1] = "symbol" end
    return pool, classes
end

-- a light penalty for obvious patterns so "aaaaaaaa"/"123456" don't read strong
local function pattern_factor(s)
    local f = 1
    local lower = s:lower()
    -- long runs of one character
    if lower:find("(.)%1%1%1") then f = f * 0.55 end
    -- simple sequences
    local seqs = { "abcdefghijklmnopqrstuvwxyz", "0123456789", "qwertyuiop", "password", "qwerty" }
    for _, seq in ipairs(seqs) do
        for i = 1, #seq - 3 do
            if lower:find(seq:sub(i, i + 3), 1, true) then f = f * 0.6; break end
        end
    end
    return f
end

-- returns bits, label, color(0..1 index), crack-time string
local function strength(s)
    if s == "" then return 0, "—", 0, "" end
    local pool = class_pool(s)
    if pool == 0 then pool = 1 end
    local bits = #s * (math.log(pool) / math.log(2)) * pattern_factor(s)
    local label, k
    if bits < 28 then label, k = "very weak", 0
    elseif bits < 40 then label, k = "weak", 0.25
    elseif bits < 60 then label, k = "fair", 0.5
    elseif bits < 80 then label, k = "strong", 0.75
    else label, k = "very strong", 1 end
    -- crack time at 1e11 guesses/sec (offline, fast hardware); halve the space on average
    local secs = (2 ^ bits) / 2 / 1e11
    local function human(t)
        if t < 1 then return "instantly" end
        local units = { { 60, "second" }, { 60, "minute" }, { 24, "hour" }, { 365, "day" }, { 100, "year" }, { math.huge, "century" } }
        local v = t
        for _, u in ipairs(units) do
            if v < u[1] then
                if u[2] == "century" and v > 1e7 then return "trillions of years" end
                local n = math.floor(v + 0.5)
                if n == 1 then return "1 " .. u[2] end
                return n .. " " .. (u[2] == "century" and "centuries" or (u[2] .. "s"))
            end
            v = v / u[1]
        end
        return "eons"
    end
    return bits, label, k, human(secs)
end

local STR_COLORS = { [0] = "err", "warn", "info", "ok", "accent" }

local function strength_color(k)
    local idx = math.min(4, math.floor(k * 4 + 0.001))
    return STR_COLORS[idx] or "warn"
end

local function draw_meter(ui, bits, k, x, y, mw)
    local h = 8
    ui.set_color("faint", 1)
    love.graphics.rectangle("fill", x, y, mw, h, 3, 3)
    local col = strength_color(k)
    local fillw = mw * util.clamp(bits / 100, 0.02, 1)
    local c = util.color(col)
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.rectangle("fill", x, y, fillw, h, 3, 3)
    -- segment ticks at the rating boundaries
    for _, b in ipairs({ 28, 40, 60, 80 }) do
        local tx = x + mw * b / 100
        ui.set_color("bg", 0.8)
        love.graphics.rectangle("fill", tx, y, 1, h)
    end
end

-- generation -----------------------------------------------------------------

local function build_pool(w)
    local p = ""
    if w.use_lower then p = p .. (w.avoid and LOWER or LOWER_ALL) end
    if w.use_upper then p = p .. (w.avoid and UPPER or UPPER_ALL) end
    if w.use_digit then p = p .. (w.avoid and DIGITS or DIGITS_ALL) end
    if w.use_symbol then p = p .. SYMBOLS end
    return p
end

local function generate(w)
    local pool = build_pool(w)
    if pool == "" then w.use_lower = true; pool = LOWER_ALL end
    local chars, n = {}, #pool
    for i = 1, w.length do
        local idx = love.math.random(1, n)
        chars[i] = pool:sub(idx, idx)
    end
    -- make sure at least one of each enabled class is present
    local function ensure(set, patt)
        if set and not table.concat(chars):find(patt) then
            local i = love.math.random(1, w.length)
            local j = love.math.random(1, #set)
            chars[i] = set:sub(j, j)
        end
    end
    ensure(w.use_lower, "[a-z]")
    ensure(w.use_upper, "[A-Z]")
    ensure(w.use_digit, "%d")
    ensure(w.use_symbol, "[^%w]")
    w.password = table.concat(chars)
    w.gen_flash = love.timer.getTime()
end

function W.load(w, ui)
    w.length = 18
    w.use_lower, w.use_upper, w.use_digit, w.use_symbol = true, true, true, true
    w.avoid = true   -- skip look-alike characters (l, 1, O, 0, I)
    w.custom = ""
    w.reveal = true
    generate(w)
end

function W.status(w)
    local bits = select(1, strength(w.password))
    return ("%d-char  ·  %d bits"):format(#(w.password or ""), math.floor(bits))
end

local function copy(ui, text, label)
    love.system.setClipboardText(text)
    ui.sound("beep", { pitch = 1.3, volume = 0.5 })
    ui.print("{accent}+{} " .. (label or "copied") .. " to clipboard")
end

function W.draw(w, ui, x, y, width, height)
    local pad = 2
    -- generated password display
    local boxh = 46
    ui.set_color("bg", 0.8)
    love.graphics.rectangle("fill", x, y, width, boxh, 4, 4)
    local flash = w.gen_flash and util.clamp(1 - (ui.time() - w.gen_flash) / 0.4, 0, 1) or 0
    local bc = util.mix(util.palette.faint, util.palette.accent, 0.4 + flash * 0.6)
    love.graphics.setColor(bc[1], bc[2], bc[3], 1); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, boxh - 1, 4, 4)
    local shown = w.reveal and w.password or string.rep("•", #w.password)
    -- fit the font: use bold, shrink if long
    local pf = ui.font_bold
    love.graphics.setFont(pf)
    local scale = math.min(1.35, (width - 24) / math.max(1, pf:getWidth(shown)))
    scale = math.max(0.7, scale)
    local c = util.mix(util.palette.white, util.palette.accent, flash)
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.print(shown, x + 12, y + (boxh - pf:getHeight() * scale) / 2, 0, scale, scale)

    -- strength of the generated password
    local gy = y + boxh + 8
    local bits, label, k, crack = strength(w.password)
    draw_meter(ui, bits, k, x, gy, width)
    ui.text(label, x, gy + 12, strength_color(k), ui.font_bold)
    ui.text(("%d bits entropy"):format(math.floor(bits)), x, gy + 26, "dim")
    local crackt = "cracks in " .. crack
    ui.text(crackt, x + width - ui.font:getWidth(crackt), gy + 26, "dim")

    -- action buttons
    local by = gy + 44
    local bw = (width - 16) / 3
    if ui.button("pw_regen", "GENERATE", x, by, bw, 26, { tip = "make a new password" }) then
        generate(w); ui.sound("beep", { pitch = 1.1, volume = 0.5 }); ui.fx.sparks(x + bw / 2, by + 13, 10, "accent", 70)
    end
    if ui.button("pw_copy", "COPY", x + bw + 8, by, bw, 26, { tip = "copy to clipboard" }) then
        copy(ui, w.password, "password")
    end
    if ui.button("pw_reveal", w.reveal and "HIDE" or "SHOW", x + (bw + 8) * 2, by, bw, 26) then
        w.reveal = not w.reveal; ui.sound("tick")
    end

    -- length control
    local ly = by + 38
    ui.text("length", x, ly, "dim")
    ui.text(tostring(w.length), x + width - ui.font_bold:getWidth(tostring(w.length)), ly - 1, "white", ui.font_bold)
    local sly = ly + 16
    -- slider
    local sx, sw = x, width
    ui.set_color("faint", 1); love.graphics.rectangle("fill", sx, sly + 4, sw, 4, 2, 2)
    local t = (w.length - 4) / (64 - 4)
    ui.set_color("accent", 1); love.graphics.rectangle("fill", sx, sly + 4, sw * t, 4, 2, 2)
    local knobx = sx + sw * t
    local khov = ui.hover(knobx - 8, sly - 2, 16, 16) or w.len_drag
    ui.set_color(khov and "white" or "accent", 1)
    love.graphics.circle("fill", knobx, sly + 6, khov and 7 or 5)
    if ui.clicked(sx - 4, sly - 4, sw + 8, 18) then w.len_drag = true end
    if w.len_drag then
        if ui.mouse.down then
            w.length = math.floor(util.clamp((ui.mouse.x - sx) / sw, 0, 1) * (64 - 4) + 4 + 0.5)
            generate(w)
        else w.len_drag = nil end
    end

    -- character set toggles
    local ty = sly + 24
    local half = (width - 16) / 2
    w.use_lower = ui.toggle("pw_lower", "a-z  lowercase", w.use_lower, x, ty, half)
    w.use_upper = ui.toggle("pw_upper", "A-Z  uppercase", w.use_upper, x + half + 16, ty, half)
    w.use_digit = ui.toggle("pw_digit", "0-9  digits", w.use_digit, x, ty + 26, half)
    w.use_symbol = ui.toggle("pw_symbol", "!@#  symbols", w.use_symbol, x + half + 16, ty + 26, half)
    local avoid2 = ui.toggle("pw_avoid", "avoid look-alikes (l 1 I O 0)", w.avoid, x, ty + 52, width)
    if avoid2 ~= w.avoid then w.avoid = avoid2; generate(w) end
    -- regenerate when a class toggle changes
    local sig = tostring(w.use_lower) .. tostring(w.use_upper) .. tostring(w.use_digit) .. tostring(w.use_symbol)
    if sig ~= w.last_sig then
        if w.last_sig ~= nil then generate(w) end
        w.last_sig = sig
    end

    -- custom password tester
    local cy = ty + 84
    ui.set_color("faint", 1); love.graphics.rectangle("fill", x, cy - 8, width, 1)
    ui.text("TEST YOUR OWN PASSWORD", x, cy, "text", ui.font_bold)
    w.custom = ui.textfield("pw_custom", w.custom, x, cy + 20, width, 26, { placeholder = "type a password to rate it…", max = 128 })
    local cbits, clabel, ck, ccrack = strength(w.custom)
    local cmy = cy + 54
    draw_meter(ui, cbits, ck, x, cmy, width)
    if w.custom ~= "" then
        ui.text(clabel, x, cmy + 12, strength_color(ck), ui.font_bold)
        local pool, classes = class_pool(w.custom)
        ui.text(("%d bits  ·  %d chars  ·  %s"):format(math.floor(cbits), #w.custom,
            #classes > 0 and table.concat(classes, "+") or "—"), x, cmy + 26, "dim")
        local ct = "cracks in " .. ccrack
        ui.text(ct, x + width - ui.font:getWidth(ct), cmy + 12, strength_color(ck))
    else
        ui.text("entropy, character mix and estimated crack time appear here", x, cmy + 14, "faint")
    end
end

return W
