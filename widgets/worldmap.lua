-- World map with two kinds of markers:
--   ◆ VICTIM  name, age, date of birth, date of death, ip, address, anything else
--   ● PLACE   name and a description
-- Pick a tool, click the map to drop a marker, then fill in its details below the map.
-- Drag to pan, mouse wheel to zoom, drag a marker to move it. Markers save automatically.
local world = require("src.world")
local markers = require("src.markers")
local util = require("src.util")

local ASPECT = 360 / (world.LAT_MAX - world.LAT_MIN)

local DOT_SHADER = [[
extern number sweep;
extern vec2 mouse;
extern vec4 base;
extern vec4 hot;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    float d = sc.x - sweep;
    float trail = d < 0.0 ? exp(d / 140.0) : exp(-d / 5.0);
    float m = 1.0 - clamp(distance(sc, mouse) / 150.0, 0.0, 1.0);
    float k = clamp(trail * 0.75 + m * m * 0.8, 0.0, 1.0);
    return mix(base, hot, k);
}
]]

local function bounce(t)
    if t < 1 / 2.75 then return 7.5625 * t * t
    elseif t < 2 / 2.75 then t = t - 1.5 / 2.75; return 7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75 then t = t - 2.25 / 2.75; return 7.5625 * t * t + 0.9375
    else t = t - 2.625 / 2.75; return 7.5625 * t * t + 0.984375 end
end

-- view helpers ------------------------------------------------------------------

local function to_screen(w, nx, ny)
    local r = w.rect
    return r.x + r.w / 2 + (nx - w.cx) * r.w * w.zoom, r.y + r.h / 2 + (ny - w.cy) * r.h * w.zoom
end

local function to_norm(w, sx, sy)
    local r = w.rect
    return w.cx + (sx - r.x - r.w / 2) / (r.w * w.zoom), w.cy + (sy - r.y - r.h / 2) / (r.h * w.zoom)
end

local function clamp_view(w)
    local hx = 0.5 / w.tz
    w.tcx = util.clamp(w.tcx, hx, 1 - hx)
    w.tcy = util.clamp(w.tcy, hx, 1 - hx)
end

local function in_rect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function zoom_at(w, factor, sx, sy)
    local r = w.rect
    local nx, ny = to_norm(w, sx, sy)
    w.tz = util.clamp(w.tz * factor, 1, 28)
    w.tcx = nx - (sx - r.x - r.w / 2) / (r.w * w.tz)
    w.tcy = ny - (sy - r.y - r.h / 2) / (r.h * w.tz)
    clamp_view(w)
end

local function fly_to(w, m, zoom)
    local nx, ny = world.to_norm(m.lat, m.lon)
    w.tz = math.max(w.tz, zoom or 4)
    w.tcx, w.tcy = nx, ny
    clamp_view(w)
end

-- drawing helpers ------------------------------------------------------------------

local function draw_victim(x, y, s, a, time, id, selected)
    local acc, bg, white = util.palette.accent, util.palette.bg, util.palette.white
    local pulse = (time * 0.65 + id * 0.37) % 1
    love.graphics.setLineWidth(1)
    love.graphics.setColor(acc[1], acc[2], acc[3], (1 - pulse) * 0.75 * a)
    love.graphics.circle("line", x, y, s + pulse * 20)
    love.graphics.setColor(acc[1], acc[2], acc[3], a)
    love.graphics.polygon("fill", x, y - s, x + s, y, x, y + s, x - s, y)
    love.graphics.setColor(bg[1], bg[2], bg[3], a)
    love.graphics.polygon("fill", x, y - s * 0.4, x + s * 0.4, y, x, y + s * 0.4, x - s * 0.4, y)
    if selected then
        love.graphics.setColor(white[1], white[2], white[3], a)
        love.graphics.polygon("line", x, y - s - 2, x + s + 2, y, x, y + s + 2, x - s - 2, y)
    end
end

local function draw_place(x, y, s, a, selected)
    local c, bg = util.palette.white, util.palette.bg
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(bg[1], bg[2], bg[3], a)
    love.graphics.circle("fill", x, y, s)
    love.graphics.setColor(c[1], c[2], c[3], a)
    love.graphics.circle("line", x, y, s)
    love.graphics.circle("fill", x, y, 1.8)
    if selected then
        local acc = util.palette.accent
        love.graphics.setColor(acc[1], acc[2], acc[3], a)
        love.graphics.circle("line", x, y, s + 3)
    end
end

local function brackets(x, y, r, time)
    local acc = util.palette.accent
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(time * 1.2)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.9)
    love.graphics.setLineWidth(1.5)
    for k = 0, 3 do
        love.graphics.push()
        love.graphics.rotate(k * math.pi / 2)
        love.graphics.line(r - 5, -r, r, -r, r, -r + 5)
        love.graphics.pop()
    end
    love.graphics.pop()
end

local function plate(ui, text, x, y, color, font)
    font = font or ui.font
    local tw, th = font:getWidth(text) + 10, font:getHeight() + 4
    ui.set_color("bg", 0.85)
    love.graphics.rectangle("fill", x, y, tw, th, 2, 2)
    ui.text(text, x + 5, y + 2, color or "text", font)
    return tw
end

-- the widget ------------------------------------------------------------------

local W = {
    title = "WORLD MAP",
    order = 1,
    height = "fill",
    width = 0.6,
    collapsible = false,
}

function W.load(w, ui)
    w.zoom, w.tz = 1, 1
    w.cx, w.cy, w.tcx, w.tcy = 0.5, 0.5, 0.5, 0.5
    w.vx, w.vy = 0, 0
    w.tool = nil
    w.filter = "all"
    w.search = ""
    w.list_scroll = 0
    w.drops = {}
    w.shader = love.graphics.newShader(DOT_SHADER)
    if #markers.list == 0 then markers.load() end
end

function W.status(w)
    local v, p = markers.count()
    return v .. " victims  ·  " .. p .. " places"
end

function W.update(w, dt, ui)
    markers.update()
    if markers.fly and w.rect then
        local m = markers.get(markers.fly)
        if m then fly_to(w, m, 5) end
        markers.fly = nil
    end
    -- glide after a drag
    if not w.drag and (math.abs(w.vx) > 1e-5 or math.abs(w.vy) > 1e-5) then
        w.tcx, w.tcy = w.tcx - w.vx * dt, w.tcy - w.vy * dt
        w.vx, w.vy = w.vx * (1 - math.min(1, dt * 5)), w.vy * (1 - math.min(1, dt * 5))
        clamp_view(w)
    end
    local k = math.min(1, dt * 10)
    w.zoom = w.zoom + (w.tz - w.zoom) * k
    w.cx = w.cx + (w.tcx - w.cx) * k
    w.cy = w.cy + (w.tcy - w.cy) * k
end

function W.keypressed(w, ui, key)
    if key == "escape" then
        if w.tool then w.tool = nil; ui.sound("back"); return true end
        if markers.selected then markers.selected = nil; return true end
    end
    return false
end

function W.wheelmoved(w, ui, dx, dy)
    local mx, my = ui.mouse.x, ui.mouse.y
    if in_rect(w.rect, mx, my) then
        zoom_at(w, 1.25 ^ dy, mx, my)
        ui.sound("tick", { pitch = dy > 0 and 1.2 or 0.8, volume = 0.5 })
    elseif in_rect(w.list_rect, mx, my) then
        w.list_scroll = math.max(0, w.list_scroll - dy * 2)
    end
end

-- map -------------------------------------------------------------------------

local function place_marker(w, ui, sx, sy)
    local nx, ny = to_norm(w, sx, sy)
    local lat, lon = world.from_norm(util.clamp(nx, 0, 1), util.clamp(ny, 0, 1))
    local m = markers.add(w.tool, lat, lon)
    w.drops[m.id] = ui.time()
    ui.sound("place")
    ui.sound("lock", { volume = 0.6 })
    ui.fx.ripple(sx, sy, 1.5)
    ui.fx.sparks(sx, sy, 24, "accent", 140)
    ui.fx.do_shake(4)
    if not love.keyboard.isDown("lshift", "rshift") then w.tool = nil end
    ui.focus_field("mk_name_" .. m.id)
    ui.focus_from_click = true
end

local function draw_map(w, ui, r)
    local time = ui.time()
    local mx, my = ui.mouse.x, ui.mouse.y
    local hover_map = in_rect(r, mx, my)
    local dpi = love.graphics.getDPIScale()

    ui.set_color("bg", 0.92)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    love.graphics.intersectScissor(r.x, r.y, r.w, r.h)

    -- graticule
    love.graphics.setLineWidth(1)
    for lon = -150, 150, 30 do
        local sx = to_screen(w, world.to_norm(0, lon))
        ui.set_color("faint", lon == 0 and 0.9 or 0.45)
        love.graphics.line(sx, r.y, sx, r.y + r.h)
    end
    for lat = -30, 60, 30 do
        local _, sy = to_screen(w, world.to_norm(lat, 0))
        ui.set_color("faint", lat == 0 and 0.9 or 0.45)
        love.graphics.line(r.x, sy, r.x + r.w, sy)
    end

    -- land dots (pick a density that keeps them ~4px apart)
    local s1 = r.w * w.zoom / 720
    local every = s1 >= 3.4 and 1 or (s1 * 2 >= 3.4 and 2 or 4)
    local spacing = s1 * every
    local sweep_x = r.x + (((time * 0.11) % 1.25) - 0.1) * r.w
    local base = util.mix(util.palette.faint, util.palette.accent, 0.38)
    local hot = util.palette.accent
    w.shader:send("sweep", sweep_x * dpi)
    w.shader:send("mouse", { mx * dpi, my * dpi })
    w.shader:send("base", { base[1], base[2], base[3], 0.85 })
    w.shader:send("hot", { hot[1], hot[2], hot[3], 1 })
    love.graphics.setShader(w.shader)
    love.graphics.setPointSize(util.clamp(spacing * 0.5, 1.4, 3.2) * dpi)
    love.graphics.push()
    love.graphics.translate(r.x + r.w / 2 - w.cx * r.w * w.zoom, r.y + r.h / 2 - w.cy * r.h * w.zoom)
    love.graphics.scale(r.w * w.zoom, r.h * w.zoom)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(world.dots(every))
    love.graphics.pop()
    love.graphics.setShader()

    -- scan line
    ui.set_color("accent", 0.22)
    love.graphics.rectangle("fill", sweep_x, r.y, 1, r.h)
    for i = 1, 12 do
        ui.set_color("accent", 0.018 * (12 - i) / 12)
        love.graphics.rectangle("fill", sweep_x - i * 8, r.y, 8, r.h)
    end

    -- markers: hit-test first, then draw
    local hovered
    local pos = {}
    for _, m in ipairs(markers.list) do
        local sx, sy = to_screen(w, world.to_norm(m.lat, m.lon))
        local drop = w.drops[m.id] and util.clamp((time - w.drops[m.id]) / 0.55, 0, 1) or 1
        sy = sy - (1 - bounce(drop)) * 46
        pos[m.id] = { sx, sy, drop }
        if not w.tool and hover_map and math.abs(mx - sx) < 10 and math.abs(my - sy) < 10 then hovered = m end
    end

    -- crosshair on the selected marker
    local sel = markers.selected and markers.get(markers.selected)
    if sel and pos[sel.id] then
        local p = pos[sel.id]
        ui.set_color("accent", 0.18)
        love.graphics.line(r.x, p[2], r.x + r.w, p[2])
        love.graphics.line(p[1], r.y, p[1], r.y + r.h)
    end

    for _, m in ipairs(markers.list) do
        local p = pos[m.id]
        if p[1] > r.x - 30 and p[1] < r.x + r.w + 30 and p[2] > r.y - 30 and p[2] < r.y + r.h + 30 then
            local hov = hovered == m
            local s = ui.ease("mk_s_" .. m.id, hov and 8.5 or 6, 16)
            local selected = markers.selected == m.id
            if m.kind == "victim" then
                draw_victim(p[1], p[2], s, 1, time, m.id, selected)
            else
                draw_place(p[1], p[2], s - 1, 1, selected)
            end
            if p[3] < 1 then
                ui.set_color("white", 1 - p[3])
                love.graphics.circle("line", p[1], p[2] + (1 - bounce(p[3])) * 46, 4 + p[3] * 40)
            end
            if selected then brackets(p[1], p[2], 15, time) end
            if w.zoom > 1.6 or hov or selected then
                local label = markers.label(m)
                local font = selected and ui.font_bold or ui.font
                local lx = p[1] + 12
                if lx + font:getWidth(label) > r.x + r.w - 4 then lx = p[1] - 12 - font:getWidth(label) end
                ui.text(label, lx, p[2] - 18, m.kind == "victim" and "white" or "text", font)
            end
        end
    end

    -- placing: crosshair + ghost marker
    if w.tool and hover_map then
        ui.set_color("accent", 0.35)
        love.graphics.line(r.x, my, r.x + r.w, my)
        love.graphics.line(mx, r.y, mx, r.y + r.h)
        if w.tool == "victim" then draw_victim(mx, my, 6, 0.6, time, 0, false) else draw_place(mx, my, 5, 0.6, false) end
    end

    -- mouse interaction
    if hovered then
        ui.tooltip(markers.label(hovered) .. "  ·  " .. markers.coords(hovered.lat, hovered.lon))
        if ui.clicked(pos[hovered.id][1] - 10, pos[hovered.id][2] - 10, 20, 20) then
            markers.select(hovered.id)
            w.mdrag = { id = hovered.id, x = mx, y = my, moved = false }
            ui.sound("beep", { pitch = 1.1, volume = 0.5 })
        end
    end
    if hover_map and ui.clicked(r.x, r.y, r.w, r.h) then
        if w.tool then
            place_marker(w, ui, mx, my)
        else
            w.drag = { x = mx, y = my, moved = false }
            w.vx, w.vy = 0, 0
        end
    end
    if w.drag then
        if ui.mouse.down then
            local dx, dy = ui.mouse.dx or 0, ui.mouse.dy or 0
            if math.abs(mx - w.drag.x) + math.abs(my - w.drag.y) > 3 then w.drag.moved = true end
            local ux, uy = dx / (r.w * w.zoom), dy / (r.h * w.zoom)
            w.tcx, w.tcy = w.tcx - ux, w.tcy - uy
            clamp_view(w)
            w.cx, w.cy = w.tcx, w.tcy
            local dt = math.max(1 / 240, love.timer.getDelta())
            w.vx, w.vy = ux / dt * 0.6, uy / dt * 0.6
        else
            if not w.drag.moved then markers.selected = nil end
            w.drag = nil
        end
    end
    if w.mdrag then
        local m = markers.get(w.mdrag.id)
        if ui.mouse.down and m then
            if math.abs(mx - w.mdrag.x) + math.abs(my - w.mdrag.y) > 4 then w.mdrag.moved = true end
            if w.mdrag.moved then
                local nx, ny = to_norm(w, util.clamp(mx, r.x, r.x + r.w), util.clamp(my, r.y, r.y + r.h))
                m.lat, m.lon = world.from_norm(util.clamp(nx, 0, 1), util.clamp(ny, 0, 1))
            end
        else
            if w.mdrag.moved then
                markers.touch()
                ui.sound("lock", { volume = 0.6 })
            end
            w.mdrag = nil
        end
    end

    -- readouts
    local f = ui.font
    if hover_map then
        local nx, ny = to_norm(w, mx, my)
        local lat, lon = world.from_norm(nx, ny)
        plate(ui, markers.coords(lat, lon) .. (world.is_land(lat, lon) and "   land" or "   ocean"), r.x + 8, r.y + r.h - f:getHeight() - 12, "text")
    end
    local z = ("×%.1f"):format(w.zoom)
    plate(ui, z, r.x + r.w - f:getWidth(z) - 18, r.y + r.h - f:getHeight() - 12, "dim")
    if w.tool then
        local hint = "click to drop a " .. w.tool .. " marker   ·   shift = keep tool   ·   esc = cancel"
        plate(ui, hint, r.x + (r.w - f:getWidth(hint)) / 2 - 5, r.y + 8, "accent")
    end

    if ui.clip then love.graphics.setScissor(unpack(ui.clip)) else love.graphics.setScissor() end
    -- frame + corner ticks
    ui.set_color("faint", 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    ui.set_color("accent", 0.8)
    for _, c in ipairs({ { r.x, r.y, 1, 1 }, { r.x + r.w, r.y, -1, 1 }, { r.x, r.y + r.h, 1, -1 }, { r.x + r.w, r.y + r.h, -1, -1 } }) do
        love.graphics.rectangle("fill", c[1] - (c[3] < 0 and 10 or 0), c[2] - (c[4] < 0 and 1 or 0), 10, 1)
        love.graphics.rectangle("fill", c[1] - (c[3] < 0 and 1 or 0), c[2] - (c[4] < 0 and 10 or 0), 1, 10)
    end
end

-- marker list -----------------------------------------------------------------------

local function draw_list(w, ui, x, y, lw, lh)
    local tabs = { { "all", "ALL" }, { "victim", "VICTIMS" }, { "place", "PLACES" } }
    local tw = (lw - 8) / 3
    for i, t in ipairs(tabs) do
        if ui.button("wm_tab_" .. t[1], t[2], x + (i - 1) * (tw + 4), y, tw, 22, { active = w.filter == t[1], bold = true }) then
            w.filter = t[1]
            w.list_scroll = 0
        end
    end
    w.search = ui.textfield("wm_search", w.search, x, y + 28, lw, 24, { placeholder = "search markers…" })

    local ly = y + 58
    local rh = 22
    w.list_rect = { x = x, y = ly, w = lw, h = lh - 58 }
    local rows = {}
    local q = w.search:lower()
    for _, m in ipairs(markers.list) do
        if (w.filter == "all" or m.kind == w.filter) and (q == "" or markers.label(m):lower():find(q, 1, true)) then
            rows[#rows + 1] = m
        end
    end
    local visible = math.max(1, math.floor((lh - 58) / rh))
    w.list_scroll = util.clamp(w.list_scroll, 0, math.max(0, #rows - visible))
    local first = math.floor(w.list_scroll) + 1
    if #rows == 0 then
        ui.text(#markers.list == 0 and "no markers yet" or "nothing matches", x + 4, ly + 4, "dim")
    end
    for i = first, math.min(#rows, first + visible - 1) do
        local m = rows[i]
        local ry = ly + (i - first) * rh
        local hov = ui.hover(x, ry, lw, rh)
        local sel = markers.selected == m.id
        local hv = ui.ease("wm_row_" .. m.id, (hov or sel) and 1 or 0, 16)
        ui.set_color("accent", 0.04 + hv * 0.08)
        love.graphics.rectangle("fill", x, ry + 1, lw, rh - 2, 2, 2)
        if sel then
            ui.set_color("accent", 1)
            love.graphics.rectangle("fill", x, ry + 1, 2, rh - 2)
        end
        local icon = m.kind == "victim" and "◆" or "○"
        ui.text(icon, x + 8, ry + 3, m.kind == "victim" and "accent" or "white")
        local name = markers.label(m)
        local maxw = lw - 34
        while ui.font:getWidth(name) > maxw and #name > 3 do name = name:sub(1, -5) .. "…" end
        ui.text(name, x + 24 + hv * 3, ry + 3, sel and "white" or "text")
        if ui.clicked(x, ry, lw, rh) then
            markers.select(m.id, true)
            ui.sound("beep", { pitch = 1.05, volume = 0.5 })
        end
    end
    if #rows > visible then
        local bar_h = (lh - 58) * visible / #rows
        local bar_y = ly + (lh - 58 - bar_h) * (w.list_scroll / math.max(1, #rows - visible))
        ui.set_color("accent", 0.5)
        love.graphics.rectangle("fill", x + lw - 2, bar_y, 2, bar_h)
    end
end

-- marker editor -----------------------------------------------------------------------

local function field(ui, m, key, label, x, y, w, h, multiline)
    local id = "mk_" .. key .. "_" .. m.id
    local v = ui.textfield(id, m[key] or "", x, y, w, h, {
        label = label, multiline = multiline, placeholder = multiline and "type anything…" or "",
    })
    if v ~= (m[key] or "") then
        m[key] = v
        markers.touch()
    end
end

local function draw_editor(w, ui, m, x, y, ew, eh)
    local time = ui.time()
    local victim = m.kind == "victim"
    -- header
    local tag = victim and "◆ VICTIM" or "○ PLACE"
    ui.set_color(victim and "accent" or "white", 0.14)
    local tw = ui.font_bold:getWidth(tag) + 14
    love.graphics.rectangle("fill", x, y, tw, 20, 3, 3)
    ui.text(tag, x + 7, y + 3, victim and "accent" or "white", ui.font_bold)
    ui.text("#" .. m.id .. "   " .. markers.coords(m.lat, m.lon), x + tw + 10, y + 3, "dim")

    local fy = y + 30
    local col = (ew - 10) / 2
    local rowh = 46
    if victim then
        field(ui, m, "name", "name", x, fy, col, rowh - 4)
        field(ui, m, "age", "age", x + col + 10, fy, col, rowh - 4)
        field(ui, m, "dob", "date of birth", x, fy + rowh, col, rowh - 4)
        field(ui, m, "dod", "date of death", x + col + 10, fy + rowh, col, rowh - 4)
        field(ui, m, "ip", "ip address", x, fy + rowh * 2, col, rowh - 4)
        field(ui, m, "address", "address", x + col + 10, fy + rowh * 2, col, rowh - 4)
        fy = fy + rowh * 3
    else
        field(ui, m, "name", "name", x, fy, ew, rowh - 4)
        fy = fy + rowh
    end
    local notes_h = y + eh - fy - 36
    if notes_h > 40 then
        field(ui, m, "notes", victim and "anything else" or "description", x, fy, ew, notes_h, true)
    end

    -- actions
    local by = y + eh - 26
    local bw = (ew - 18) / 4
    if ui.button("wm_locate", "LOCATE", x, by, bw, 26, { tip = "zoom the map to this marker" }) then
        fly_to(w, m, 6)
        ui.sound("whoosh", { volume = 0.5 })
    end
    if victim then
        if ui.button("wm_trace", "TRACE IP", x + bw + 6, by, bw, 26, { tip = "trace this ip in the terminal" }) then
            ui.run("trace " .. ((m.ip and m.ip ~= "") and m.ip or "unknown"))
        end
    else
        if ui.button("wm_scan", "SCAN AREA", x + bw + 6, by, bw, 26, { tip = "scan the area in the terminal" }) then
            ui.run("scan")
        end
    end
    if ui.button("wm_dossier", "DOSSIER", x + (bw + 6) * 2, by, bw, 26, { tip = "print everything in the terminal" }) then
        ui.run("dossier " .. m.id)
    end
    local confirming = w.confirm_delete == m.id and time - (w.confirm_at or 0) < 3
    if ui.button("wm_delete", confirming and "CONFIRM?" or "DELETE", x + (bw + 6) * 3, by, bw, 26,
        { active = confirming, tip = confirming and "click again to delete" or "remove this marker" }) then
        if confirming then
            markers.remove(m.id)
            w.confirm_delete = nil
            ui.unfocus()
            ui.sound("err", { volume = 0.7 })
            ui.fx.glitch(0.3, 0.6)
        else
            w.confirm_delete, w.confirm_at = m.id, time
        end
    end
end

local function draw_empty(w, ui, x, y, ew, eh)
    local v, p = markers.count()
    ui.text("NO MARKER SELECTED", x, y + 4, "text", ui.font_bold)
    local lines = {
        "◆ VICTIM   drop a person: name, age, dates, ip, address, notes",
        "○ PLACE    drop a location with a description",
        "",
        "click a marker to edit it  ·  drag it to move it",
        "drag the map to pan  ·  mouse wheel to zoom",
        "",
        ("on file: %d victims, %d places"):format(v, p),
    }
    for i, l in ipairs(lines) do ui.text(l, x, y + 28 + (i - 1) * 18, i <= 2 and "text" or "dim") end
end

function W.draw(w, ui, x, y, width, height)
    -- toolbar
    local bh = 26
    if ui.button("wm_tool_victim", "◆ VICTIM", x, y, 110, bh, { active = w.tool == "victim", tip = "drop a victim marker" }) then
        w.tool = w.tool ~= "victim" and "victim" or nil
    end
    if ui.button("wm_tool_place", "○ PLACE", x + 116, y, 100, bh, { active = w.tool == "place", tip = "drop a place marker" }) then
        w.tool = w.tool ~= "place" and "place" or nil
    end
    local zx = x + width - 3 * 34 - 52
    if ui.button("wm_zoom_out", "−", zx, y, 30, bh) then
        zoom_at(w, 1 / 1.6, w.rect.x + w.rect.w / 2, w.rect.y + w.rect.h / 2)
    end
    if ui.button("wm_zoom_in", "+", zx + 34, y, 30, bh) then
        zoom_at(w, 1.6, w.rect.x + w.rect.w / 2, w.rect.y + w.rect.h / 2)
    end
    if ui.button("wm_zoom_reset", "FIT", zx + 68, y, 82, bh, { tip = "show the whole world" }) then
        w.tz, w.tcx, w.tcy = 1, 0.5, 0.5
        ui.sound("whoosh", { volume = 0.4 })
    end

    -- map keeps the world's proportions; the rest goes to the list + editor
    local my = y + bh + 10
    local details_min = 250
    local mh = math.floor(math.min(width / ASPECT, height - bh - 10 - details_min - 12))
    mh = math.max(120, mh)
    local mw = math.floor(math.min(width, mh * ASPECT))
    w.rect = { x = x + (width - mw) / 2, y = my, w = mw, h = mh }
    draw_map(w, ui, w.rect)

    local dy = my + mh + 14
    local dh = y + height - dy
    if dh < 60 then return end
    local lw = math.floor(width * 0.34)
    draw_list(w, ui, x, dy, lw, dh)
    ui.set_color("faint", 1)
    love.graphics.rectangle("fill", x + lw + 12, dy, 1, dh)
    local ex, ew = x + lw + 26, width - lw - 26
    local m = markers.selected and markers.get(markers.selected)
    if m then draw_editor(w, ui, m, ex, dy, ew, dh) else draw_empty(w, ui, ex, dy, ew, dh) end
end

return W
