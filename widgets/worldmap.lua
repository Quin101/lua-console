-- World map with two kinds of markers:
--   ◆ VICTIM  name, age, date of birth, date of death, ip, address, anything else
--   ● PLACE   name and a description
-- Pick a tool, click the map to drop a marker, then fill in its details below the map.
-- Drag to pan, mouse wheel to zoom, drag a marker to move it. Markers save automatically.
local world = require("src.world")
local markers = require("src.markers")
local util = require("src.util")
local images = require("src.images")

local ASPECT = 360 / (world.LAT_MAX - world.LAT_MIN)
local draw_evidence_picker  -- defined before W.draw

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

-- the colour a marker is drawn in: its tag colour, else the kind default
local function marker_color(m)
    local t = markers.tag_info(m.tag)
    if t[1] ~= "" then return util.color(t[3]) end
    return m.kind == "victim" and util.palette.accent or util.palette.white
end

local function draw_victim(x, y, s, a, time, id, selected, col)
    local c, bg, white = col or util.palette.accent, util.palette.bg, util.palette.white
    local pulse = (time * 0.65 + id * 0.37) % 1
    love.graphics.setLineWidth(1)
    love.graphics.setColor(c[1], c[2], c[3], (1 - pulse) * 0.75 * a)
    love.graphics.circle("line", x, y, s + pulse * 20)
    love.graphics.setColor(c[1], c[2], c[3], a)
    love.graphics.polygon("fill", x, y - s, x + s, y, x, y + s, x - s, y)
    love.graphics.setColor(bg[1], bg[2], bg[3], a)
    love.graphics.polygon("fill", x, y - s * 0.4, x + s * 0.4, y, x, y + s * 0.4, x - s * 0.4, y)
    if selected then
        love.graphics.setColor(white[1], white[2], white[3], a)
        love.graphics.polygon("line", x, y - s - 2, x + s + 2, y, x, y + s + 2, x - s - 2, y)
    end
end

local function draw_place(x, y, s, a, selected, col)
    local c, bg = col or util.palette.white, util.palette.bg
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

-- a connection line between two markers, with flowing dashes and a label
local function draw_link(ui, x1, y1, x2, y2, label, time, strong)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local acc = util.palette.accent
    local a = strong and 0.9 or 0.4
    love.graphics.setColor(acc[1], acc[2], acc[3], a * 0.4)
    love.graphics.setLineWidth(strong and 1.6 or 1)
    love.graphics.line(x1, y1, x2, y2)
    -- flowing dashes
    local ux, uy = dx / len, dy / len
    local gap = 14
    local off = (time * 40) % gap
    love.graphics.setColor(acc[1], acc[2], acc[3], a)
    for d = off, len, gap do
        love.graphics.line(x1 + ux * d, y1 + uy * d, x1 + ux * math.min(d + 5, len), y1 + uy * math.min(d + 5, len))
    end
    if label and label ~= "" and len > 50 then
        local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        local tw = ui.font:getWidth(label) + 8
        ui.set_color("bg", 0.8)
        love.graphics.rectangle("fill", mx - tw / 2, my - 8, tw, 15, 2, 2)
        ui.text(label, mx - tw / 2 + 4, my - 6, strong and "white" or "dim")
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
    tab = "MAP",
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
    w.link_mode = false
    w.link_from = nil
    w.filter = "all"
    w.search = ""
    w.list_scroll = 0
    w.drops = {}
    w.shader = love.graphics.newShader(DOT_SHADER)
    if #markers.list == 0 and #markers.links == 0 then markers.load() end
end

function W.status(w)
    local v, p = markers.count()
    local l = #markers.links
    return v .. " victims  ·  " .. p .. " places" .. (l > 0 and ("  ·  " .. l .. " links") or "")
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
        if w.link_mode or w.link_from then w.link_mode, w.link_from = false, nil; ui.sound("back"); return true end
        if w.tool then w.tool = nil; ui.sound("back"); return true end
        if w.evidence_pick then w.evidence_pick = nil; ui.sound("back"); return true end
        if markers.selected then markers.selected = nil; return true end
    end
    return false
end

-- dropping a file onto the window: images become photos, anything else becomes
-- evidence (imported into the vault's evidence/ folder and referenced)
function W.filedropped(w, ui, file)
    local m = markers.selected and markers.get(markers.selected)
    if not m or ui.active_tab ~= W.tab then return false end
    local name = file:getFilename():match("([^/\\]+)$") or "file"
    file:open("r")
    local data = file:read()
    file:close()
    if images.is_image_name(name) then
        local path, err = markers.add_photo(m, name, data)
        if path then
            w.photo_i = w.photo_i or {}
            w.photo_i[m.id] = #markers.photo_list(m)
            w.drop_flash = ui.time()
            ui.sound("place")
            ui.fx.flash("accent", 0.12)
            ui.print("{accent}◆{} photo attached to {white}" .. markers.label(m):gsub("{", "{{") .. "{}  {dim}" .. name:gsub("{", "{{"))
        else
            ui.sound("err")
            ui.print("{err}✗{} " .. name:gsub("{", "{{") .. ": " .. err)
        end
    else
        local vault = require("src.vault")
        vault.init()
        love.filesystem.createDirectory(vault.join(vault.ROOT, "evidence"))
        local path = vault.import(vault.join(vault.ROOT, "evidence"), name, data)
        markers.add_evidence(m, path)
        w.drop_flash = ui.time()
        ui.sound("place"); ui.fx.flash("accent", 0.12)
        ui.print("{accent}≡{} evidence attached to {white}" .. markers.label(m):gsub("{", "{{") .. "{}  {dim}" .. name:gsub("{", "{{"))
    end
    return true
end

function W.wheelmoved(w, ui, dx, dy)
    local mx, my = ui.mouse.x, ui.mouse.y
    if w.evidence_pick then
        w.evidence_pick.scroll = math.max(0, w.evidence_pick.scroll - dy * 2)
        return
    end
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
    local hover_map = in_rect(r, mx, my) and not w.evidence_pick
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
        if hover_map and math.abs(mx - sx) < 10 and math.abs(my - sy) < 10 then hovered = m end
    end

    -- connection lines (under the markers)
    for _, l in ipairs(markers.links) do
        local pa, pb = pos[l.a], pos[l.b]
        if pa and pb then
            local strong = markers.selected == l.a or markers.selected == l.b
            draw_link(ui, pa[1], pa[2], pb[1], pb[2], l.label, time, strong)
        end
    end
    -- rubber-band while linking
    if w.link_from and pos[w.link_from] then
        local pa = pos[w.link_from]
        local tx, ty = (hovered and hovered.id ~= w.link_from) and pos[hovered.id][1] or mx, (hovered and hovered.id ~= w.link_from) and pos[hovered.id][2] or my
        draw_link(ui, pa[1], pa[2], tx, ty, nil, time, true)
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
            local col = marker_color(m)
            if w.link_from == m.id then col = util.palette.white end
            if m.kind == "victim" then
                draw_victim(p[1], p[2], s, 1, time, m.id, selected, col)
            else
                draw_place(p[1], p[2], s - 1, 1, selected, col)
            end
            if p[3] < 1 then
                ui.set_color("white", 1 - p[3])
                love.graphics.circle("line", p[1], p[2] + (1 - bounce(p[3])) * 46, 4 + p[3] * 40)
            end
            if selected then
                brackets(p[1], p[2], 15, time)
                local ph = markers.photo_list(m)
                local img = ph[1] and images.get(ph[#ph])
                if img then
                    local tx = p[1] - 64
                    if tx < r.x + 4 then tx = p[1] + 20 end
                    local ty = p[2] - 24
                    ui.set_color("bg", 0.9)
                    love.graphics.rectangle("fill", tx - 2, ty - 2, 48, 48)
                    images.draw_fit(img, tx, ty, 44, 44, true)
                    ui.set_color("accent", 0.9)
                    love.graphics.rectangle("line", tx - 2.5, ty - 2.5, 49, 49)
                end
            end
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
        local tip = markers.label(hovered) .. "  ·  " .. markers.coords(hovered.lat, hovered.lon)
        if w.link_mode then tip = w.link_from and "click to link to " .. markers.label(hovered) or "click to start a link from " .. markers.label(hovered) end
        ui.tooltip(tip)
        if ui.clicked(pos[hovered.id][1] - 10, pos[hovered.id][2] - 10, 20, 20) then
            if w.link_mode then
                if not w.link_from then
                    w.link_from = hovered.id
                    ui.sound("beep", { pitch = 1.3, volume = 0.5 })
                elseif w.link_from ~= hovered.id then
                    local existed = markers.are_linked(w.link_from, hovered.id)
                    markers.link(w.link_from, hovered.id)
                    ui.sound("lock", { volume = 0.7 })
                    ui.fx.sparks(pos[hovered.id][1], pos[hovered.id][2], 14, "accent", 90)
                    ui.print("{accent}↔{} linked {white}" .. markers.label(markers.get(w.link_from)):gsub("{", "{{") ..
                        "{} ↔ {white}" .. markers.label(hovered):gsub("{", "{{"))
                    markers.select(hovered.id)
                    if not love.keyboard.isDown("lshift", "rshift") then w.link_mode, w.link_from = false, nil else w.link_from = hovered.id end
                end
            else
                markers.select(hovered.id)
                w.mdrag = { id = hovered.id, x = mx, y = my, moved = false }
                ui.sound("beep", { pitch = 1.1, volume = 0.5 })
            end
        end
    end
    if hover_map and ui.clicked(r.x, r.y, r.w, r.h) then
        if w.tool then
            place_marker(w, ui, mx, my)
        elseif not w.link_mode then
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
    local hint
    if w.tool then
        hint = "click to drop a " .. w.tool .. " marker   ·   shift = keep tool   ·   esc = cancel"
    elseif w.link_mode then
        hint = w.link_from and ("click another marker to link it   ·   shift = keep linking   ·   esc = cancel")
            or "click a marker to start a link   ·   esc = cancel"
    end
    if hint then plate(ui, hint, r.x + (r.w - f:getWidth(hint)) / 2 - 5, r.y + 8, "accent") end

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

-- photo box: shows the current photo, arrows to flip through, × to remove, click to enlarge
local function draw_photos(w, ui, m, x, y, pw, ph)
    local list = markers.photo_list(m)
    local hov = ui.hover(x, y, pw, ph)
    ui.text("photos" .. (#list > 0 and ("  " .. #list) or ""), x, y, "dim")
    y, ph = y + ui.font:getHeight() + 3, ph - ui.font:getHeight() - 3
    ui.set_color("bg", 0.7)
    love.graphics.rectangle("fill", x, y, pw, ph, 3, 3)
    local drop_glow = ui.ease("wm_drop_" .. m.id, (w.drop_flash and ui.time() - w.drop_flash < 0.6) and 1 or 0, 8)
    if #list == 0 then
        -- dashed outline + hint
        ui.set_color(hov and "accent" or "faint", 1)
        local dash = 6
        for i = 0, math.floor((pw + ph) * 2 / (dash * 2)) do
            local d = i * dash * 2 + (ui.time() * 12) % (dash * 2)
            local function pt(t)
                if t < pw then return x + t, y end
                t = t - pw; if t < ph then return x + pw, y + t end
                t = t - ph; if t < pw then return x + pw - t, y + ph end
                t = t - pw; return x, y + ph - math.min(t, ph)
            end
            local x1, y1 = pt(d % ((pw + ph) * 2))
            local x2, y2 = pt((d + dash) % ((pw + ph) * 2))
            if math.abs(x1 - x2) + math.abs(y1 - y2) <= dash + 0.5 then love.graphics.line(x1, y1, x2, y2) end
        end
        local lines = { "drag an image", "onto the window", "to attach it" }
        for i, l in ipairs(lines) do
            ui.text_center(l, x, y + ph / 2 - 26 + (i - 1) * 17, pw, hov and "text" or "dim")
        end
        return
    end
    w.photo_i = w.photo_i or {}
    local idx = util.clamp(w.photo_i[m.id] or #list, 1, #list)
    w.photo_i[m.id] = idx
    local img = images.get(list[idx])
    if img then images.draw_fit(img, x + 2, y + 2, pw - 4, ph - 4, true) end
    ui.set_color(hov and "accent" or "faint", 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, pw - 1, ph - 1, 3, 3)
    if drop_glow > 0.01 then
        ui.set_color("white", drop_glow * 0.5)
        love.graphics.rectangle("line", x - 2, y - 2, pw + 4, ph + 4, 4, 4)
    end
    if hov then
        -- controls appear on hover
        if #list > 1 then
            if ui.button("wm_ph_prev", "‹", x + 4, y + ph / 2 - 12, 22, 24) then w.photo_i[m.id] = (idx - 2) % #list + 1 end
            if ui.button("wm_ph_next", "›", x + pw - 26, y + ph / 2 - 12, 22, 24) then w.photo_i[m.id] = idx % #list + 1 end
        end
        local confirming = w.confirm_photo == list[idx] and ui.time() - (w.confirm_photo_at or 0) < 3
        if ui.button("wm_ph_del", confirming and "sure?" or "×", x + pw - (confirming and 58 or 26), y + 4,
            confirming and 54 or 22, 22, { active = confirming, tip = "remove this photo" }) then
            if confirming then
                markers.remove_photo(m, list[idx])
                w.confirm_photo = nil
                ui.sound("back")
            else
                w.confirm_photo, w.confirm_photo_at = list[idx], ui.time()
            end
        end
        ui.text(idx .. "/" .. #list, x + 6, y + ph - 20, "white")
        if ui.clicked(x, y, pw, ph) then
            ui.open_viewer(list, idx, markers.label(m))
        end
        ui.tooltip("click to enlarge  ·  drop more images to add")
    end
end

-- a coloured, clickable chip; returns true if its body was clicked and
-- sets removed=true via the returned second value if its × was clicked
local function chip(ui, label, x, y, color, removable)
    local tw = ui.font:getWidth(label) + 14 + (removable and 14 or 0)
    local hov = ui.hover(x, y, tw, 18)
    local c = util.color(color)
    love.graphics.setColor(c[1], c[2], c[3], hov and 0.26 or 0.16)
    love.graphics.rectangle("fill", x, y, tw, 18, 9, 9)
    love.graphics.setColor(c[1], c[2], c[3], hov and 1 or 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, tw - 1, 17, 9, 9)
    ui.text(label, x + 8, y + 1, hov and "white" or color)
    local removed = false
    if removable then
        local rx = x + tw - 15
        local rhov = ui.hover(rx, y, 15, 18)
        ui.text("×", rx + 2, y + 1, rhov and "err" or "dim")
        if ui.clicked(rx, y, 15, 18) then removed = true end
    end
    local clicked = ui.clicked(x, y, tw - (removable and 15 or 0), 18)
    return tw, clicked, removed
end

local function draw_tag_row(ui, m, x, y, ew)
    ui.text("tag", x, y + 1, "dim")
    local cx = x + 32
    for _, t in ipairs(markers.TAGS) do
        local label = t[1] == "" and "none" or t[2]
        local active = (m.tag or "") == t[1]
        local tw = ui.font:getWidth(label) + 14
        if cx + tw > x + ew then break end
        local c = util.color(t[3])
        love.graphics.setColor(c[1], c[2], c[3], active and 0.3 or (ui.hover(cx, y, tw, 18) and 0.14 or 0.05))
        love.graphics.rectangle("fill", cx, y, tw, 18, 9, 9)
        if active then
            love.graphics.setColor(c[1], c[2], c[3], 1); love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", cx + 0.5, y + 0.5, tw - 1, 17, 9, 9)
        end
        ui.text(label, cx + 7, y + 1, active and t[3] or "dim")
        if ui.clicked(cx, y, tw, 18) then
            m.tag = t[1] ~= "" and t[1] or nil
            markers.touch(); ui.sound("tick", { pitch = 1.1, volume = 0.5 })
        end
        cx = cx + tw + 5
    end
end

-- links + evidence chips
local function draw_connections(w, ui, m, x, y, ew, ch)
    if ui.button("wm_link_add", "↔ LINK", x, y, 70, 20, { active = w.link_mode, bold = false, tip = "connect to another marker" }) then
        w.link_mode = not w.link_mode; w.link_from = w.link_mode and m.id or nil
        if w.link_mode then ui.sound("beep", { pitch = 1.2 }) else ui.sound("back") end
    end
    if ui.button("wm_evid_add", "+ FILE", x + 76, y, 70, 20, { bold = false, tip = "attach a file from the vault as evidence" }) then
        w.evidence_pick = { marker = m.id, scroll = 0 }
        ui.sound("beep", { pitch = 1.1 })
    end
    ui.text("drop a file on the window to attach it", x + 152, y + 2, "dim")

    -- chips: links first (click to jump), then evidence (click to open)
    local cx, cy = x, y + 26
    local rowh = 22
    local vault = require("src.vault")
    for _, e in ipairs(markers.links_of(m.id)) do
        local other = e.other
        local label = (other.kind == "victim" and "◆ " or "○ ") .. markers.label(other) .. (e.link.label and e.link.label ~= "" and ("  (" .. e.link.label .. ")") or "")
        local tw, clicked, removed = chip(ui, label, cx, cy, "accent", true)
        if clicked then markers.select(other.id, true); ui.sound("beep", { pitch = 1.05 }) end
        if removed then markers.unlink(m.id, other.id); ui.sound("back") end
        cx = cx + tw + 6
        if cx > x + ew - 80 then cx = x; cy = cy + rowh end
        if cy > y + ch - rowh then break end
    end
    for _, path in ipairs(markers.evidence_list(m)) do
        local nm = vault.basename(path)
        local tw, clicked, removed = chip(ui, "≡ " .. nm, cx, cy, "info", true)
        if clicked then
            if vault.kind(path) == "image" then ui.open_viewer({ path }, 1, nm)
            else ui.run("cat " .. path:gsub("^vault/", "")) end
        end
        if removed then markers.remove_evidence(m, path); ui.sound("back") end
        cx = cx + tw + 6
        if cx > x + ew - 80 then cx = x; cy = cy + rowh end
        if cy > y + ch - rowh then break end
    end
    if #markers.links_of(m.id) == 0 and #markers.evidence_list(m) == 0 then
        ui.text("no connections yet", x, cy + 1, "faint")
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

    draw_tag_row(ui, m, x, y + 24, ew)

    local fy = y + 48
    local col = (ew - 10) / 2
    local rowh = 44
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
    local conn_h = 50
    local notes_h = y + eh - fy - 36 - conn_h - 6
    if notes_h > 36 then
        local photo_w = math.floor(math.min(170, ew * 0.34))
        field(ui, m, "notes", victim and "anything else" or "description", x, fy, ew - photo_w - 10, notes_h, true)
        draw_photos(w, ui, m, x + ew - photo_w, fy, photo_w, notes_h)
        fy = fy + notes_h + 6
    end
    draw_connections(w, ui, m, x, fy, ew, conn_h)

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
        "↔ LINK  connect two markers with a labelled line",
        "tag markers, and attach photos / evidence files",
        "drop files onto the window: images = photos, else evidence",
        "drag the map to pan  ·  mouse wheel to zoom",
        "",
        ("on file: %d victims, %d places"):format(v, p),
    }
    for i, l in ipairs(lines) do ui.text(l, x, y + 28 + (i - 1) * 18, i <= 2 and "text" or "dim") end
end

-- modal list of every vault file; click one to attach it as evidence
local function gather_vault(dir, out, depth)
    local vault = require("src.vault")
    for _, it in ipairs(vault.list(dir)) do
        if it.kind == "folder" then
            if depth < 4 then gather_vault(it.path, out, depth + 1) end
        else
            out[#out + 1] = it
        end
    end
end

draw_evidence_picker = function(w, ui, x, y, width, height)
    local vault = require("src.vault")
    local pick = w.evidence_pick
    local m = markers.get(pick.marker)
    if not m then w.evidence_pick = nil; return end
    -- dim the panel
    ui.set_color("bg", 0.8)
    love.graphics.rectangle("fill", x - 12, y - 30, width + 24, height + 44)
    local pw, phh = math.min(width - 20, 420), math.min(height - 20, 360)
    local px, py = x + (width - pw) / 2, y + (height - phh) / 2
    ui.set_color("bg2", 0.98); love.graphics.rectangle("fill", px, py, pw, phh, 5, 5)
    ui.set_color("accent", 0.8); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, phh - 1, 5, 5)
    ui.text("ATTACH EVIDENCE  →  " .. markers.label(m), px + 12, py + 10, "white", ui.font_bold)
    if ui.button("wm_evpick_close", "✕", px + pw - 32, py + 8, 24, 20) then w.evidence_pick = nil; return end

    local all = {}
    gather_vault(vault.ROOT, all, 1)
    local already = {}
    for _, e in ipairs(markers.evidence_list(m)) do already[e] = true end

    local lx, ly = px + 12, py + 38
    local lw, lh = pw - 24, phh - 50
    local rh = 22
    local visible = math.floor(lh / rh)
    pick.scroll = util.clamp(pick.scroll, 0, math.max(0, #all - visible))
    if #all == 0 then ui.text("the vault is empty — import files in the FILES panel first", lx, ly + 4, "dim") end
    local first = math.floor(pick.scroll) + 1
    for i = first, math.min(#all, first + visible - 1) do
        local it = all[i]
        local ry = ly + (i - first) * rh
        local has = already[it.path]
        local hov = ui.hover(lx, ry, lw, rh)
        ui.set_color("accent", (hov and not has) and 0.1 or 0.03)
        love.graphics.rectangle("fill", lx, ry + 1, lw, rh - 2, 2, 2)
        local icon = it.kind == "image" and "■" or (it.kind == "text" and "≡" or "□")
        ui.text(icon, lx + 6, ry + 3, it.kind == "image" and "info" or "dim")
        ui.text(vault.pretty(it.path):gsub("^vault / ", ""), lx + 22, ry + 3, has and "dim" or "text")
        ui.text(has and "attached" or vault.size_str(it.size), lx + lw - ui.font:getWidth(has and "attached" or vault.size_str(it.size)) - 2, ry + 3, has and "accent" or "dim")
        if not has and ui.clicked(lx, ry, lw, rh) then
            markers.add_evidence(m, it.path)
            ui.sound("place", { volume = 0.6 })
            ui.print("{info}≡{} attached {white}" .. vault.basename(it.path):gsub("{", "{{") .. "{} to " .. markers.label(m):gsub("{", "{{"))
        end
    end
    -- block clicks from reaching the map underneath
    if ui.press and not ui.press.used and not ui.hover(px, py, pw, phh) then w.evidence_pick = nil end
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
    if ui.button("wm_tool_link", "↔ LINK", x + 222, y, 90, bh, { active = w.link_mode, tip = "connect two markers" }) then
        w.link_mode = not w.link_mode
        w.link_from = nil
        w.tool = nil
        if w.link_mode then ui.sound("beep", { pitch = 1.2 }) else ui.sound("back") end
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
    local details_min = markers.selected and 326 or 250
    local mh = math.floor(math.min(width / ASPECT, height - bh - 10 - details_min - 12))
    mh = math.max(120, mh)
    local mw = math.floor(math.min(width, mh * ASPECT))
    w.rect = { x = x + (width - mw) / 2, y = my, w = mw, h = mh }
    draw_map(w, ui, w.rect)

    local dy = my + mh + 12
    local dh = y + height - dy
    if dh < 60 then return end
    local lw = math.floor(width * 0.34)
    draw_list(w, ui, x, dy, lw, dh)
    ui.set_color("faint", 1)
    love.graphics.rectangle("fill", x + lw + 12, dy, 1, dh)
    local ex, ew = x + lw + 26, width - lw - 26
    local m = markers.selected and markers.get(markers.selected)
    if m then draw_editor(w, ui, m, ex, dy, ew, dh) else draw_empty(w, ui, ex, dy, ew, dh) end

    if w.evidence_pick then draw_evidence_picker(w, ui, x, y, width, height) end
end

return W
