-- Dashboard layout + a tiny immediate-mode UI toolkit for widgets.
--
-- Widgets live in widgets/*.lua. Inside a widget's draw() you can write things like
--     if ui.button("scan", "SCAN", x, y, 80, 26) then ui.run("scan") end
-- and the button handles its own hover/press animation, sound and sparks.
local util = require("src.util")
local fx = require("src.fx")
local sound = require("src.sound")
local images = require("src.images")

local viewer_step, draw_viewer -- defined further down

local ui = {
    widgets = {},
    errors = {},
    anim = {},
    mouse = { x = 0, y = 0 },
    press = nil,          -- {x, y, button} for this frame
    show_panels = true,
    tooltip_text = nil,
    focus = nil,          -- the text field receiving keyboard input
    field_order = {},
    born = 0,             -- when the dashboard appeared (for the slide-in)
}

local GAP = 16
local PANEL_W = 350
local TITLE_H = 26

function ui.init(T, cfg)
    ui.T = T
    ui.cfg = cfg
    ui.font = T.font_small
    ui.font_mid = T.font
    ui.font_bold = love.graphics.newFont("assets/fonts/JetBrainsMono-Bold.ttf", math.max(10, (cfg.font_size or 15) - 3))
    ui.term_panel = { title = "TERMINAL", born = 0 }
    ui.load_widgets()
end

-- loading ----------------------------------------------------------------------

function ui.load_widgets()
    ui.widgets, ui.errors = {}, {}
    local files = love.filesystem.getDirectoryItems("widgets")
    table.sort(files)
    for _, f in ipairs(files) do
        if f:match("%.lua$") and not f:match("^_") then
            local ok, chunk = pcall(love.filesystem.load, "widgets/" .. f)
            local ok2, def
            if ok and chunk then ok2, def = pcall(chunk) end
            if ok and ok2 and type(def) == "table" and def.draw then
                def.file = f
                def.born = ui.time() + #ui.widgets * 0.09 + 0.1
                def.collapse = 0
                ui.widgets[#ui.widgets + 1] = def
                if def.load then
                    local okl, err = pcall(def.load, def, ui)
                    if not okl then ui.errors[#ui.errors + 1] = f .. ": " .. tostring(err) end
                end
            else
                ui.errors[#ui.errors + 1] = f .. ": " .. tostring(not ok and chunk or (not ok2 and def) or "widget must return { title = ..., draw = function(w, ui, x, y, width, height) end }")
            end
        end
    end
    table.sort(ui.widgets, function(a, b) return (a.order or 50) < (b.order or 50) end)
    return #ui.widgets
end

-- helpers widgets can use ----------------------------------------------------

function ui.time() return ui.T and ui.T.time or 0 end
function ui.color(name) return util.color(name) end
function ui.run(line) ui.T.request(line) end
function ui.print(text, color) ui.T.add(text, color) end
function ui.busy() return ui.T.task ~= nil end
ui.sound = sound.play
ui.util = util
ui.fx = fx

function ui.set_color(name, a)
    local c = util.color(name)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function ui.hover(x, y, w, h)
    local m = ui.mouse
    return m.x >= x and m.x < x + w and m.y >= y and m.y < y + h
end

-- true if the mouse was pressed inside this rectangle this frame
function ui.clicked(x, y, w, h, button)
    local p = ui.press
    if not p or p.used then return false end
    if (button or 1) ~= p.button then return false end
    if p.x >= x and p.x < x + w and p.y >= y and p.y < y + h then
        p.used = true
        return true
    end
    return false
end

-- eases a value towards target, per id; returns the current value
function ui.ease(id, target, speed)
    local v = ui.anim[id] or target
    v = v + (target - v) * math.min(1, love.timer.getDelta() * (speed or 14))
    ui.anim[id] = v
    return v
end

function ui.text(str, x, y, color, font, a)
    love.graphics.setFont(font or ui.font)
    ui.set_color(color or "text", a)
    love.graphics.print(str, math.floor(x), math.floor(y))
end

function ui.text_center(str, x, y, w, color, font, a)
    font = font or ui.font
    ui.text(str, x + (w - font:getWidth(str)) / 2, y, color, font, a)
end

function ui.tooltip(text)
    ui.tooltip_text = text
end

-- A button. Returns true on the frame it is clicked.
--   opts.color  accent colour name   opts.small  smaller text
function ui.button(id, label, x, y, w, h, opts)
    opts = opts or {}
    local hov = ui.hover(x, y, w, h)
    local hv = ui.ease("btn_h_" .. id, hov and 1 or 0, 16)
    local clicked = ui.clicked(x, y, w, h)
    if clicked then
        ui.anim["btn_p_" .. id] = 1
        sound.play("beep", { pitch = 1.1 + math.random() * 0.2, volume = 0.45 })
        fx.sparks(x + w / 2, y + h / 2, 8, opts.color or "accent", 90)
        fx.ripple(x + w / 2, y + h / 2, 0.8)
    end
    local pv = ui.anim["btn_p_" .. id] or 0
    ui.anim["btn_p_" .. id] = math.max(0, pv - love.timer.getDelta() * 3)

    local acc = util.color(opts.color or "accent")
    local faint = util.palette.faint
    local lift = hv * 1.5
    local act = ui.ease("btn_a_" .. id, opts.active and 1 or 0, 14)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.04 + hv * 0.1 + pv * 0.35 + act * 0.2)
    love.graphics.rectangle("fill", x, y - lift, w, h, 4, 4)
    local bc = util.mix(faint, acc, math.max(0.15 + hv * 0.85, act))
    love.graphics.setColor(bc[1], bc[2], bc[3], 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5 - lift, w - 1, h - 1, 4, 4)
    -- little accent tick on the left that grows on hover
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.6 + hv * 0.4)
    local th = 6 + hv * (h - 12)
    love.graphics.rectangle("fill", x + 4, y + (h - th) / 2 - lift, 2, th)
    local font = opts.bold ~= false and ui.font_bold or ui.font
    local tc = util.mix(util.palette.text, util.palette.white, math.max(hv, act))
    love.graphics.setFont(font)
    love.graphics.setColor(tc[1], tc[2], tc[3], 1)
    love.graphics.print(label, math.floor(x + (w - font:getWidth(label)) / 2 + 3), math.floor(y + (h - font:getHeight()) / 2 - lift))
    if hov and opts.tip then ui.tooltip(opts.tip) end
    return clicked
end

-- A switch. Returns the (possibly flipped) value.
function ui.toggle(id, label, value, x, y, w)
    local h = 20
    local hov = ui.hover(x, y, w, h)
    if ui.clicked(x, y, w, h) then
        value = not value
        sound.play(value and "beep" or "back", { pitch = value and 1.5 or 0.8, volume = 0.5 })
        fx.sparks(x + w - 18, y + h / 2, value and 8 or 3, value and "accent" or "dim", 60)
    end
    local k = ui.ease("tg_" .. id, value and 1 or 0, 18)
    local hv = ui.ease("tg_h_" .. id, hov and 1 or 0, 16)
    ui.text(label, x, y + 2, hov and "white" or "text")
    local sw, sh = 34, 16
    local sx, sy = x + w - sw, y + 2
    local acc, faint = util.palette.accent, util.palette.faint
    local track = util.mix(faint, acc, k * 0.45)
    love.graphics.setColor(track[1], track[2], track[3], 1)
    love.graphics.rectangle("fill", sx, sy, sw, sh, sh / 2, sh / 2)
    local knob = util.mix(util.palette.dim, acc, k)
    love.graphics.setColor(knob[1], knob[2], knob[3], 1)
    love.graphics.circle("fill", sx + sh / 2 + k * (sw - sh), sy + sh / 2, sh / 2 - 3 + hv)
    return value
end

-- Text input. Returns the (possibly edited) value.
--   opts.multiline   Enter adds a new line, text wraps
--   opts.label       small caption above the box
--   opts.placeholder grey hint when empty
function ui.textfield(id, value, x, y, w, h, opts)
    opts = opts or {}
    value = tostring(value or "")
    local font = ui.font
    if opts.label then
        ui.text(opts.label, x, y, "dim", ui.font)
        y = y + font:getHeight() + 3
        h = h - font:getHeight() - 3
    end
    ui.field_order[#ui.field_order + 1] = id
    local hov = ui.hover(x, y, w, h)
    if ui.clicked(x, y, w, h) then
        ui.focus_field(id)
        ui.focus.caret = util.ulen(value)
        ui.focus_from_click = true
    end
    local f = ui.focus
    local focused = f and f.id == id
    if focused then
        -- apply queued keyboard edits
        local chars = util.chars(value)
        f.caret = util.clamp(f.caret or #chars, 0, #chars)
        for _, op in ipairs(f.ops) do
            if op[1] == "text" then
                if f.select_all then chars = {}; f.caret = 0; f.select_all = nil end
                for _, ch in ipairs(util.chars(op[2])) do
                    if ch ~= "\n" or opts.multiline then
                        f.caret = f.caret + 1
                        table.insert(chars, f.caret, ch)
                    end
                end
                f.typed = ui.time()
            elseif op[1] == "back" and f.select_all then
                chars = {}; f.caret = 0; f.select_all = nil
            elseif op[1] == "back" and f.caret > 0 then
                table.remove(chars, f.caret)
                f.caret = f.caret - 1
            elseif op[1] == "delete" and f.caret < #chars then
                table.remove(chars, f.caret + 1)
            elseif op[1] == "left" then f.caret = math.max(0, f.caret - 1)
            elseif op[1] == "right" then f.caret = math.min(#chars, f.caret + 1)
            elseif op[1] == "home" then f.caret = 0
            elseif op[1] == "end" then f.caret = #chars
            elseif op[1] == "return" then
                if opts.multiline then
                    f.caret = f.caret + 1
                    table.insert(chars, f.caret, "\n")
                else
                    ui.focus_next = (ui.focus_next or 0) + 1
                end
            end
        end
        f.ops = {}
        if opts.max then while #chars > opts.max do table.remove(chars) end; f.caret = math.min(f.caret, #chars) end
        value = table.concat(chars)
    end

    local fv = ui.ease("tf_" .. id, focused and 1 or 0, 16)
    local hv = ui.ease("tf_h_" .. id, hov and 1 or 0, 16)
    local acc, faint, bg = util.palette.accent, util.palette.faint, util.palette.bg
    love.graphics.setColor(bg[1], bg[2], bg[3], 0.7)
    love.graphics.rectangle("fill", x, y, w, h, 3, 3)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.05 * fv)
    love.graphics.rectangle("fill", x, y, w, h, 3, 3)
    local bc = util.mix(faint, acc, math.max(fv, hv * 0.4))
    love.graphics.setColor(bc[1], bc[2], bc[3], 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
    -- focus underline grows from the left
    love.graphics.setColor(acc[1], acc[2], acc[3], fv)
    love.graphics.rectangle("fill", x, y + h - 1, w * fv, 1)

    love.graphics.setScissor()
    local px, py = x + 7, y + (opts.multiline and 5 or (h - font:getHeight()) / 2)
    local inner = w - 14
    love.graphics.setFont(font)
    if value == "" and not focused and opts.placeholder then
        ui.text(opts.placeholder, px, py, "dim", nil, 0.7)
    end
    local tc = util.palette.white
    love.graphics.setColor(tc[1], tc[2], tc[3], 1)
    local caret_x, caret_y = px, py
    if opts.multiline then
        -- wrap each paragraph, keeping track of where the caret lands
        local before = focused and util.usub(value, 1, f.caret) or value
        local ly = py
        local lh = font:getHeight() + 2
        local max_lines = math.max(1, math.floor((h - 8) / lh))
        -- wrap paragraph by paragraph so empty lines survive
        local all = {}
        for para in (value .. "\n"):gmatch("(.-)\n") do
            local _, wl = font:getWrap(para, inner)
            if #wl == 0 then wl = { "" } end
            for _, l in ipairs(wl) do all[#all + 1] = l end
        end
        local bl = {}
        for para in (before .. "\n"):gmatch("(.-)\n") do
            local _, wl = font:getWrap(para, inner)
            if #wl == 0 then wl = { "" } end
            for _, l in ipairs(wl) do bl[#bl + 1] = l end
        end
        local caret_line = #bl
        local scroll = math.max(0, caret_line - max_lines)
        for i = scroll + 1, math.min(#all, scroll + max_lines) do
            love.graphics.print(all[i], px, ly)
            ly = ly + lh
        end
        caret_x = px + font:getWidth(bl[#bl] or "")
        caret_y = py + (caret_line - 1 - scroll) * lh
    else
        local shown = opts.mask and string.rep("•", util.ulen(value)) or value
        local before = shown
        if focused then before = opts.mask and string.rep("•", f.caret) or util.usub(value, 1, f.caret) end
        local offset = focused and math.max(0, font:getWidth(before) - inner + 4) or 0
        love.graphics.setScissor(x + 2, y, w - 4, h)
        love.graphics.print(shown, px - offset, py)
        love.graphics.setScissor()
        caret_x = px - offset + font:getWidth(before)
    end
    if focused and f.select_all and value ~= "" then
        ui.set_color("accent", 0.22)
        love.graphics.rectangle("fill", px - 2, py - 1, math.min(inner + 4, font:getWidth(value) + 4), font:getHeight() + 2)
    end
    if focused then
        local idle = ui.time() - (f.typed or 0)
        local a = idle < 0.5 and 1 or (0.5 + 0.5 * math.cos((idle - 0.5) * 5))
        love.graphics.setColor(acc[1], acc[2], acc[3], a)
        love.graphics.rectangle("fill", caret_x, caret_y, 2, font:getHeight())
        f.caret_x, f.caret_y = caret_x, caret_y
    end
    if ui.clip then love.graphics.setScissor(unpack(ui.clip)) end
    return value
end

function ui.focus_field_all(id)
    ui.focus_field(id)
    ui.focus.select_all = true
    ui.focus.caret = math.huge
end

function ui.focus_field(id)
    if ui.focus and ui.focus.id == id then return end
    ui.focus = { id = id, ops = {}, typed = ui.time() }
    sound.play("tick", { pitch = 1.2, volume = 0.6 })
end

function ui.unfocus()
    ui.focus = nil
end

-- keyboard routing (called from main) -------------------------------------------

function ui.textinput(t)
    if ui.viewer then return true end
    if not ui.focus then return false end
    table.insert(ui.focus.ops, { "text", t })
    sound.play("key", { pitch = 0.95 + math.random() * 0.2, volume = 0.8 })
    if ui.focus.caret_x then fx.sparks(ui.focus.caret_x, ui.focus.caret_y + 8, 2, "accent", 45) end
    return true
end

function ui.keypressed(key)
    if ui.viewer then
        if key == "left" then viewer_step(-1)
        elseif key == "right" then viewer_step(1)
        elseif key == "escape" or key == "return" or key == "space" then ui.close_viewer() end
        return true
    end
    local f = ui.focus
    if f then
        local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
        if key == "escape" then
            ui.unfocus()
        elseif key == "tab" then
            ui.focus_next = (ui.focus_next or 0) + 1
        elseif key == "v" and ctrl then
            table.insert(f.ops, { "text", love.system.getClipboardText() or "" })
        elseif key == "backspace" or key == "delete" then
            table.insert(f.ops, { key == "backspace" and "back" or "delete" })
            sound.play("back", { pitch = 0.9 + math.random() * 0.2 })
        elseif key == "return" or key == "kpenter" or key == "left" or key == "right" or key == "home" or key == "end" then
            table.insert(f.ops, { key == "kpenter" and "return" or key })
        end
        return true
    end
    for _, w in ipairs(ui.widgets) do
        if w.keypressed then
            local ok, used = pcall(w.keypressed, w, ui, key)
            if ok and used then return true end
        end
    end
    return false
end

-- Filled line graph of a list of numbers.
function ui.graph(values, x, y, w, h, color, max)
    local n = #values
    if n < 2 then return end
    max = max or 1
    local c = util.color(color or "accent")
    local pts = {}
    for i, v in ipairs(values) do
        pts[#pts + 1] = x + (i - 1) / (n - 1) * w
        pts[#pts + 1] = y + h - util.clamp(v / max, 0, 1) * h
    end
    for i = 1, n - 1 do
        local x1, y1, x2, y2 = pts[i * 2 - 1], pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 2]
        love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.08 * (i / n))
        love.graphics.polygon("fill", x1, y + h, x1, y1, x2, y2, x2, y + h)
    end
    love.graphics.setColor(c[1], c[2], c[3], 0.95)
    love.graphics.setLineWidth(1.2)
    love.graphics.setLineJoin("bevel")
    love.graphics.line(pts)
    love.graphics.circle("fill", pts[#pts - 1], pts[#pts], 2.2)
end

-- panels ---------------------------------------------------------------------

local function draw_panel(x, y, w, h, title, appear, extra)
    local acc, faint = util.palette.accent, util.palette.faint
    local bg = util.palette.bg2
    love.graphics.setColor(bg[1], bg[2], bg[3], 0.82 * appear)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    love.graphics.setColor(faint[1], faint[2], faint[3], appear)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
    -- corner ticks
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.7 * appear)
    local L = 8
    love.graphics.rectangle("fill", x, y + 6, 1, L)
    love.graphics.rectangle("fill", x + w - 1, y + h - 6 - L, 1, L)
    -- title
    if title then
        love.graphics.setColor(acc[1], acc[2], acc[3], appear)
        love.graphics.rectangle("fill", x + 12, y + TITLE_H / 2 - 2, 4, 4)
        love.graphics.setFont(ui.font_bold)
        local d = util.palette.text
        love.graphics.setColor(d[1], d[2], d[3], appear)
        love.graphics.print(title, x + 24, y + (TITLE_H - ui.font_bold:getHeight()) / 2 + 1)
        if extra then
            local dm = util.palette.dim
            love.graphics.setFont(ui.font)
            love.graphics.setColor(dm[1], dm[2], dm[3], appear)
            love.graphics.print(extra, x + w - 12 - ui.font:getWidth(extra), y + (TITLE_H - ui.font:getHeight()) / 2 + 1)
        end
        love.graphics.setColor(faint[1], faint[2], faint[3], appear)
        love.graphics.rectangle("fill", x + 10, y + TITLE_H, w - 20, 1)
    end
end

-- widgets with a `tab` label share one panel; only the active tab is shown
local function visible(wdg)
    return not wdg.tab or wdg.tab == ui.active_tab
end

function ui.tabs()
    local out = {}
    for _, w in ipairs(ui.widgets) do
        if w.tab then out[#out + 1] = w end
    end
    if #out > 0 then
        local ok = false
        for _, w in ipairs(out) do if w.tab == ui.active_tab then ok = true end end
        if not ok then ui.active_tab = out[1].tab end
    end
    return out
end

-- switch the tabbed panel, e.g. ui.show_tab("FILES")
function ui.show_tab(label)
    for _, w in ipairs(ui.widgets) do
        if w.tab and w.tab:lower() == label:lower() then
            if ui.active_tab ~= w.tab then
                ui.active_tab = w.tab
                ui.unfocus()
                sound.play("whoosh", { volume = 0.35 })
                w.tab_born = ui.time()
            end
            ui.show_panels = true
            return true
        end
    end
    return false
end

-- clickable tab labels in a panel's title bar
function ui.draw_tabs(x, y, appear)
    local tx = x + 12
    local f = ui.font_bold
    for _, w in ipairs(ui.tabs()) do
        local label = w.tab
        local tw = f:getWidth(label) + 18
        local active = w.tab == ui.active_tab
        local hov = ui.hover(tx, y, tw, TITLE_H)
        local a = ui.ease("tab_" .. label, active and 1 or (hov and 0.5 or 0), 14)
        if active then
            ui.set_color("accent", appear)
            love.graphics.rectangle("fill", tx, y + TITLE_H / 2 - 2, 4, 4)
        end
        local c = util.mix(util.palette.dim, util.palette.white, a)
        love.graphics.setFont(f)
        love.graphics.setColor(c[1], c[2], c[3], appear)
        love.graphics.print(label, tx + 10, y + (TITLE_H - f:getHeight()) / 2 + 1)
        ui.set_color("accent", a * appear)
        love.graphics.rectangle("fill", tx + 10, y + TITLE_H - 2, (tw - 18) * a, 2)
        if ui.clicked(tx, y, tw, TITLE_H) and not active then ui.show_tab(label) end
        tx = tx + tw + 8
    end
end

-- works out where the terminal and every widget go
function ui.layout()
    local W, H = love.graphics.getDimensions()
    local top, bottom, side = 50, 16, 22
    local panels = ui.show_panels and W >= 900 and #ui.widgets > 0
    -- column width: the widest request among widgets (numbers <= 1 are a fraction of the window)
    local pw = 0
    if panels then
        for _, wdg in ipairs(ui.widgets) do
            local want = wdg.width or PANEL_W
            if want <= 1 then want = (W - side * 2) * want end
            pw = math.max(pw, want)
        end
        pw = math.floor(math.min(pw, W - side * 2 - GAP - 420))
    end
    local tx, ty = side, top
    local tw = W - side * 2 - (panels and (pw + GAP) or 0)
    local th = H - top - bottom
    ui.term_rect = { tx, ty, tw, th }
    ui.T.set_area(tx + 18, ty + TITLE_H + 12, tw - 36, th - TITLE_H - 22)

    ui.rects = {}
    if not panels then return end
    local px = tx + tw + GAP
    ui.tabs()
    local fixed, fills, count = 0, 0, 0
    for _, wdg in ipairs(ui.widgets) do
        if not visible(wdg) then goto continue end
        count = count + 1
        local full = (wdg.height == "fill") and 0 or (wdg.height or 160)
        local hh = TITLE_H + (1 - wdg.collapse) * (full + 8)
        if wdg.height == "fill" and wdg.collapse < 1 then fills = fills + 1 end
        fixed = fixed + (wdg.height == "fill" and TITLE_H or hh)
        ::continue::
    end
    local free = math.max(0, th - fixed - GAP * (count - 1))
    local y = ty
    for i, wdg in ipairs(ui.widgets) do
        if not visible(wdg) then goto skip end
        local hh
        if wdg.height == "fill" then
            hh = TITLE_H + (fills > 0 and (1 - wdg.collapse) * free / fills or 0)
        else
            hh = TITLE_H + (1 - wdg.collapse) * ((wdg.height or 160) + 8)
        end
        ui.rects[i] = { px, y, pw, hh }
        y = y + hh + GAP
        ::skip::
    end
end

function ui.update(dt)
    local mx, my = love.mouse.getPosition()
    ui.mouse.dx, ui.mouse.dy = mx - ui.mouse.x, my - ui.mouse.y
    ui.mouse.x, ui.mouse.y = mx, my
    ui.mouse.down = love.mouse.isDown(1)
    for _, w in ipairs(ui.widgets) do
        local target = w.collapsed and 1 or 0
        w.collapse = w.collapse + (target - w.collapse) * math.min(1, dt * 12)
        if math.abs(target - w.collapse) < 0.002 then w.collapse = target end
        if w.update then
            local ok, err = pcall(w.update, w, dt, ui)
            if not ok then w.draw = nil; w.update = nil; ui.T.add("widget " .. w.file .. ": " .. tostring(err), "err", { raw = true }) end
        end
    end
    ui.layout()
end

function ui.draw()
    local now = ui.time()
    ui.tooltip_text = nil
    if ui.viewer and ui.press then
        ui.viewer_press, ui.press = ui.press, nil
    end
    ui.last_field_order = ui.field_order
    ui.field_order = {}
    local r = ui.term_rect
    local busy = ui.T.task and ("● " .. tostring(ui.T.task.name)) or "idle"
    local tappear = util.ease_out(util.clamp((now - ui.born) / 0.5, 0, 1))
    love.graphics.push()
    love.graphics.translate(-(1 - tappear) * 40, 0)
    draw_panel(r[1], r[2], r[3], r[4], "TERMINAL", tappear, busy)
    love.graphics.pop()

    for i, w in ipairs(ui.widgets) do
        local rect = ui.rects[i]
        if rect and w.draw then
            local x, y, pw, ph = rect[1], rect[2], rect[3], rect[4]
            local appear = util.ease_out(util.clamp((now - math.max(w.born, ui.born + 0.15 + i * 0.1)) / 0.45, 0, 1))
            love.graphics.push()
            love.graphics.translate((1 - appear) * 30, 0)
            -- clicking the title bar collapses the panel
            local title_hover = w.collapsible ~= false and ui.hover(x, y, pw - 90, TITLE_H)
            if w.collapsible ~= false and ui.clicked(x, y, pw - 90, TITLE_H) then
                w.collapsed = not w.collapsed
                sound.play("tick", { pitch = w.collapsed and 0.8 or 1.3 })
            end
            local extra = w.status and w.status(w, ui) or (w.collapsed and "+" or nil)
            if w.tab then
                draw_panel(x, y, pw, ph, nil, appear, extra)
                ui.draw_tabs(x, y, appear)
            else
                draw_panel(x, y, pw, ph, (w.title or w.file) .. (title_hover and "  ·" or ""), appear, extra)
            end
            if w.collapse < 0.98 then
                local cx, cy, cw, ch = x + 12, y + TITLE_H + 10, pw - 24, ph - TITLE_H - 18
                ui.clip = { x, y + TITLE_H + 1, pw, math.max(0, ph - TITLE_H - 2) }
                love.graphics.setScissor(unpack(ui.clip))
                local ok, err = pcall(w.draw, w, ui, cx, cy, cw, ch)
                love.graphics.setScissor()
                ui.clip = nil
                if not ok then
                    w.draw = nil
                    ui.T.add("widget " .. w.file .. ": " .. tostring(err), "err", { raw = true })
                end
            end
            love.graphics.pop()
        end
    end

    love.graphics.setFont(ui.T.font)
end

-- full-screen image viewer --------------------------------------------------------

-- ui.open_viewer({ "photos/a.png", "vault/b.jpg" }, 1, "caption")
function ui.open_viewer(paths, index, caption)
    if #paths == 0 then return end
    ui.viewer = { paths = paths, index = index or 1, caption = caption, born = ui.time() }
    ui.unfocus()
    sound.play("whoosh", { volume = 0.5 })
end

function ui.close_viewer()
    if ui.viewer then sound.play("back") end
    ui.viewer = nil
end

viewer_step = function(d)
    local v = ui.viewer
    v.index = (v.index - 1 + d) % #v.paths + 1
    v.switched = ui.time()
    sound.play("tick", { pitch = d > 0 and 1.2 or 0.9 })
end

draw_viewer = function()
    local v = ui.viewer
    local W, H = love.graphics.getDimensions()
    local a = util.ease_out(util.clamp((ui.time() - v.born) / 0.25, 0, 1))
    ui.set_color("bg", 0.94 * a)
    love.graphics.rectangle("fill", 0, 0, W, H)
    local path = v.paths[v.index]
    local img = images.get(path)
    local bw, bh = W * 0.86, H * 0.76
    local s = 0.94 + 0.06 * a
    local bx, by = (W - bw * s) / 2, (H - bh * s) / 2 - 10
    if img then
        local k = util.ease_out(util.clamp((ui.time() - (v.switched or v.born)) / 0.25, 0, 1))
        local x, y, dw, dh = images.draw_fit(img, bx, by, bw * s, bh * s, false, a * k)
        ui.set_color("accent", 0.6 * a)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x - 0.5, y - 0.5, dw + 1, dh + 1)
        local iw, ih = img:getDimensions()
        local info = (v.caption and (v.caption .. "   ·   ") or "") .. iw .. "×" .. ih
        ui.text_center(info, 0, y + dh + 14, W, "text", ui.font, a)
    else
        ui.text_center("could not load " .. path, 0, H / 2, W, "err", ui.font, a)
    end
    local nav = (#v.paths > 1 and ("‹  " .. v.index .. " / " .. #v.paths .. "  ›     ") or "") .. "esc or click to close"
    ui.text_center(nav, 0, H - 40, W, "dim", ui.font, a)
    local p = ui.viewer_press
    ui.viewer_press = nil
    if p then
        if #v.paths > 1 and p.x < W * 0.2 then viewer_step(-1)
        elseif #v.paths > 1 and p.x > W * 0.8 then viewer_step(1)
        else ui.close_viewer() end
    end
end

-- drag & drop ---------------------------------------------------------------------

-- offers a dropped file to widgets: the one under the mouse first, then the rest
function ui.filedropped(file)
    local order = {}
    for i, w in ipairs(ui.widgets) do
        local r = ui.rects[i]
        if r and ui.hover(r[1], r[2], r[3], r[4]) then table.insert(order, 1, w) else order[#order + 1] = w end
    end
    for _, w in ipairs(order) do
        if w.filedropped then
            local ok, used = pcall(w.filedropped, w, ui, file)
            if not ok then ui.T.add("drop failed: " .. tostring(used), "err", { raw = true })
            elseif used then return true end
        end
    end
    return false
end

function ui.directorydropped(path)
    for _, w in ipairs(ui.widgets) do
        if w.directorydropped then
            local ok, used = pcall(w.directorydropped, w, ui, path)
            if ok and used then return true end
        end
    end
    return false
end

-- drawn after the terminal text so tooltips sit on top
function ui.draw_overlay()
    -- tab / enter in a single-line field moves to the next field
    if ui.focus_next and ui.focus then
        local order = ui.field_order
        for i, id in ipairs(order) do
            if id == ui.focus.id then
                local nxt = order[i + ui.focus_next]
                if nxt then ui.focus_field(nxt) else ui.unfocus() end
                break
            end
        end
    end
    ui.focus_next = nil
    -- clicking anywhere that isn't a field drops the focus
    if ui.press and ui.focus and not ui.focus_from_click then ui.unfocus() end
    ui.focus_from_click = nil
    if ui.tooltip_text then
        local f = ui.font
        local tw, th = f:getWidth(ui.tooltip_text) + 16, f:getHeight() + 10
        local tx, ty = ui.mouse.x + 14, ui.mouse.y + 14
        local W, H = love.graphics.getDimensions()
        if tx + tw > W - 4 then tx = ui.mouse.x - tw - 8 end
        if ty + th > H - 4 then ty = ui.mouse.y - th - 8 end
        ui.set_color("bg", 0.96)
        love.graphics.rectangle("fill", tx, ty, tw, th, 4, 4)
        ui.set_color("accent", 0.8)
        love.graphics.rectangle("line", tx + 0.5, ty + 0.5, tw - 1, th - 1, 4, 4)
        ui.text(ui.tooltip_text, tx + 8, ty + 5, "white")
    end
    if ui.viewer then draw_viewer() end
    ui.press = nil
    love.graphics.setFont(ui.T.font)
end

function ui.mousepressed(x, y, button)
    ui.press = { x = x, y = y, button = button }
    ui.mouse.x, ui.mouse.y = x, y
    ui.mouse.down = button == 1
end

-- returns true if the wheel event was over a widget
function ui.wheelmoved(dx, dy)
    for i, w in ipairs(ui.widgets) do
        local r = ui.rects[i]
        if r and ui.hover(r[1], r[2], r[3], r[4]) then
            if w.wheelmoved then pcall(w.wheelmoved, w, ui, dx, dy) end
            return true
        end
    end
    return false
end

return ui
