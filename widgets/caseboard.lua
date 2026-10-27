-- CASE BOARD: a corkboard view of the markers as pinned cards joined by red string.
-- Drag cards to arrange them, drag the background to pan, wheel to zoom.
-- LINK mode connects two cards. Click a card to select it (the MAP editor follows).
local markers = require("src.markers")
local images = require("src.images")
local util = require("src.util")

local CARD_W, CARD_H = 208, 116

local W = {
    title = "CASE BOARD",
    tab = "BOARD",
    order = 3,
    height = "fill",
    width = 0.6,
    collapsible = false,
}

function W.load(w, ui)
    w.ox, w.oy = 0, 0          -- pan offset (board space -> screen)
    w.zoom, w.tz = 1, 1
    w.link_mode = false
    w.link_from = nil
    w.laid_out = false
    if #markers.list == 0 and #markers.links == 0 then markers.load() end
end

function W.status(w)
    return #markers.list .. " cards  ·  " .. #markers.links .. " links"
end

-- give any marker without a board position a spot (circular-ish spread)
local function ensure_layout(w)
    local need = {}
    for _, m in ipairs(markers.list) do
        if not (tonumber(m.bx) and tonumber(m.by)) then need[#need + 1] = m end
    end
    if #need == 0 then return end
    local n = #markers.list
    local i0 = n - #need
    for i, m in ipairs(need) do
        local idx = i0 + i - 1
        local cols = math.max(1, math.ceil(math.sqrt(n)))
        m.bx = 60 + (idx % cols) * (CARD_W + 50)
        m.by = 60 + math.floor(idx / cols) * (CARD_H + 70)
    end
    markers.touch()
end

function W.update(w, dt)
    markers.update()
    local k = math.min(1, dt * 10)
    w.zoom = w.zoom + (w.tz - w.zoom) * k
end

function W.keypressed(w, ui, key)
    if key == "escape" then
        if w.link_mode or w.link_from then w.link_mode, w.link_from = false, nil; ui.sound("back"); return true end
        if markers.selected then markers.selected = nil; return true end
    end
    return false
end

function W.wheelmoved(w, ui, dx, dy)
    local r = w.rect
    if not r or not ui.hover(r.x, r.y, r.w, r.h) then return end
    local mx, my = ui.mouse.x, ui.mouse.y
    -- zoom around the cursor
    local bx = (mx - r.x - w.ox) / w.zoom
    local by = (my - r.y - w.oy) / w.zoom
    w.tz = util.clamp(w.tz * 1.15 ^ dy, 0.4, 2.2)
    w.zoom = w.tz
    w.ox = mx - r.x - bx * w.zoom
    w.oy = my - r.y - by * w.zoom
    ui.sound("tick", { pitch = dy > 0 and 1.2 or 0.8, volume = 0.4 })
end

local function card_screen(w, r, m)
    return r.x + w.ox + (m.bx or 0) * w.zoom, r.y + w.oy + (m.by or 0) * w.zoom
end

-- the pin point (top centre) of a card, in screen space
local function pin_point(w, r, m)
    local sx, sy = card_screen(w, r, m)
    return sx + CARD_W * w.zoom / 2, sy + 8 * w.zoom
end

-- a sagging red string between two pins
local function draw_string(ui, x1, y1, x2, y2, label, time, strong, zoom)
    local acc = util.palette.accent
    local sag = math.min(40, math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * 0.18) * zoom
    local mx, my = (x1 + x2) / 2, (y1 + y2) / 2 + sag
    local pts = {}
    for i = 0, 16 do
        local t = i / 16
        local u = 1 - t
        local px = u * u * x1 + 2 * u * t * mx + t * t * x2
        local py = u * u * y1 + 2 * u * t * my + t * t * y2
        pts[#pts + 1] = px; pts[#pts + 1] = py
    end
    love.graphics.setColor(acc[1] * 0.5, acc[2] * 0.2, acc[3] * 0.2, strong and 0.9 or 0.55)
    love.graphics.setLineWidth((strong and 2 or 1.4) * util.clamp(zoom, 0.6, 1.4))
    love.graphics.line(pts)
    -- a brighter highlight
    love.graphics.setColor(acc[1], acc[2], acc[3], strong and 0.8 or 0.4)
    love.graphics.setLineWidth(0.8)
    love.graphics.line(pts)
    if label and label ~= "" and zoom > 0.6 then
        local tw = ui.font:getWidth(label) + 8
        ui.set_color("bg", 0.85)
        love.graphics.rectangle("fill", mx - tw / 2, my - 7, tw, 15, 2, 2)
        ui.text(label, mx - tw / 2 + 4, my - 6, strong and "white" or "dim")
    end
end

local function draw_card(w, ui, m, sx, sy, time)
    local z = w.zoom
    local cw, ch = CARD_W * z, CARD_H * z
    local selected = markers.selected == m.id
    local hov = ui.hover(sx, sy, cw, ch)
    local victim = m.kind == "victim"
    local tagc = markers.tag_info(m.tag)
    local accent = tagc[1] ~= "" and tagc[3] or (victim and "accent" or "white")
    local c = util.color(accent)

    -- shadow + card (drawn in screen space so photo scissors line up)
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", sx + 3, sy + 4, cw, ch, 3, 3)
    ui.set_color("bg2", 0.98)
    love.graphics.rectangle("fill", sx, sy, cw, ch, 3, 3)
    love.graphics.setColor(c[1], c[2], c[3], selected and 1 or (hov and 0.8 or 0.45))
    love.graphics.setLineWidth(selected and 2 or 1)
    love.graphics.rectangle("line", sx + 0.5, sy + 0.5, cw - 1, ch - 1, 3, 3)

    if z > 0.55 then
        local pad = 8 * z
        -- square photo thumbnail on the left
        local ph = markers.photo_list(m)
        local img = ph[1] and images.get(ph[#ph])
        local thumb = math.min(ch - pad * 2, 74 * z)
        local tyimg = sy + pad + 6 * z
        if img then
            images.draw_fit(img, sx + pad, tyimg, thumb, thumb, true)
            love.graphics.setColor(c[1], c[2], c[3], 0.7)
            love.graphics.rectangle("line", sx + pad, tyimg, thumb, thumb)
        else
            ui.set_color("faint", 1)
            love.graphics.rectangle("line", sx + pad, tyimg, thumb, thumb)
            love.graphics.setFont(ui.T.font)
            ui.text_center(victim and "◆" or "○", sx + pad, tyimg + thumb / 2 - 10, thumb, accent, ui.T.font)
        end
        if z > 0.7 then
            local tx = sx + pad + thumb + 8 * z
            local tw = sx + cw - pad - tx
            ui.text(victim and "◆ VICTIM" or "○ PLACE", tx, sy + pad, accent, ui.font)
            local name = markers.label(m)
            local _, lines = ui.font:getWrap(name, tw)
            ui.text(lines[1] or name, tx, sy + pad + 15, "white", ui.font_bold)
            local yy = sy + pad + 30
            if lines[2] then ui.text(lines[2], tx, yy, "white", ui.font_bold); yy = yy + 15 end
            if tagc[1] ~= "" then ui.text(tagc[2], tx, yy, tagc[3], ui.font); yy = yy + 14 end
            local extra = victim and (m.age and m.age ~= "" and ("age " .. m.age) or m.ip) or m.notes
            if extra and extra ~= "" and yy < sy + ch - 26 then
                local _, el = ui.font:getWrap(extra, tw)
                ui.text(el[1] or extra, tx, yy, "dim", ui.font)
            end
            local nl = #markers.links_of(m.id)
            local ne = #markers.evidence_list(m)
            local badge = (nl > 0 and ("↔" .. nl .. "  ") or "") .. (ne > 0 and ("≡" .. ne) or "")
            if badge ~= "" then ui.text(badge, tx, sy + ch - pad - 11, "dim", ui.font) end
        end
    end

    -- pushpin at the top centre
    local px, py = sx + cw / 2, sy + 8 * z
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.circle("fill", px + 1, py + 2, 4 * z)
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.circle("fill", px, py, 4 * z)
    ui.set_color("white", 0.8)
    love.graphics.circle("fill", px - 1 * z, py - 1 * z, 1.5 * z)
    return hov
end

function W.draw(w, ui, x, y, width, height)
    -- toolbar
    local bh = 26
    if ui.button("cb_link", "↔ LINK", x, y, 90, bh, { active = w.link_mode, tip = "connect two cards" }) then
        w.link_mode = not w.link_mode; w.link_from = nil
        ui.sound(w.link_mode and "beep" or "back", { pitch = 1.2 })
    end
    if ui.button("cb_arrange", "RE-ARRANGE", x + 96, y, 112, bh, { tip = "auto-lay-out the cards" }) then
        for _, m in ipairs(markers.list) do m.bx, m.by = nil, nil end
        w.laid_out = false
        ui.sound("whoosh", { volume = 0.4 })
    end
    local zx = x + width - 3 * 34 - 52
    if ui.button("cb_zoom_out", "−", zx, y, 30, bh) then w.tz = util.clamp(w.tz / 1.3, 0.4, 2.2) end
    if ui.button("cb_zoom_in", "+", zx + 34, y, 30, bh) then w.tz = util.clamp(w.tz * 1.3, 0.4, 2.2) end
    if ui.button("cb_fit", "FIT", zx + 68, y, 82, bh, { tip = "recentre the board" }) then
        w.ox, w.oy, w.tz = 0, 0, 1
        ui.sound("whoosh", { volume = 0.4 })
    end

    local r = { x = x, y = y + bh + 10, w = width, h = y + height - (y + bh + 10) }
    w.rect = r
    ensure_layout(w)
    local time = ui.time()

    -- corkboard backdrop
    ui.set_color("bg", 0.5)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    love.graphics.intersectScissor(r.x, r.y, r.w, r.h)
    -- faint dot grid that moves with the pan
    local gap = 28 * w.zoom
    ui.set_color("faint", 0.5)
    local gx0 = r.x + (w.ox % gap)
    local gy0 = r.y + (w.oy % gap)
    love.graphics.setPointSize(1.4)
    local pts = {}
    for gx = gx0, r.x + r.w, gap do for gy = gy0, r.y + r.h, gap do pts[#pts + 1] = gx; pts[#pts + 1] = gy end end
    if #pts > 0 then love.graphics.points(pts) end

    if #markers.list == 0 then
        ui.text_center("no markers yet — add some on the MAP tab", r.x, r.y + r.h / 2 - 8, r.w, "dim")
        if ui.clip then love.graphics.setScissor(unpack(ui.clip)) else love.graphics.setScissor() end
        ui.set_color("faint", 1); love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
        return
    end

    local mx, my = ui.mouse.x, ui.mouse.y
    local hover_board = ui.hover(r.x, r.y, r.w, r.h) and not ui.focus

    -- hit-test cards (topmost = last)
    local hovered
    for _, m in ipairs(markers.list) do
        local sx, sy = card_screen(w, r, m)
        if hover_board and mx >= sx and mx < sx + CARD_W * w.zoom and my >= sy and my < sy + CARD_H * w.zoom then
            hovered = m
        end
    end

    -- strings first (under the cards)
    for _, l in ipairs(markers.links) do
        local a, b = markers.get(l.a), markers.get(l.b)
        if a and b then
            local x1, y1 = pin_point(w, r, a)
            local x2, y2 = pin_point(w, r, b)
            local strong = markers.selected == l.a or markers.selected == l.b
            draw_string(ui, x1, y1, x2, y2, l.label, time, strong, w.zoom)
        end
    end
    -- rubber band while linking
    if w.link_from then
        local a = markers.get(w.link_from)
        if a then
            local x1, y1 = pin_point(w, r, a)
            local tx, ty = (hovered and hovered.id ~= w.link_from) and (select(1, pin_point(w, r, hovered))) or mx, (hovered and hovered.id ~= w.link_from) and (select(2, pin_point(w, r, hovered))) or my
            draw_string(ui, x1, y1, tx, ty, nil, time, true, w.zoom)
        end
    end

    -- cards (selected one last so it's on top)
    local sel = markers.selected
    local order = {}
    for _, m in ipairs(markers.list) do if m.id ~= sel then order[#order + 1] = m end end
    for _, m in ipairs(markers.list) do if m.id == sel then order[#order + 1] = m end end
    for _, m in ipairs(order) do
        local sx, sy = card_screen(w, r, m)
        draw_card(w, ui, m, sx, sy, time)
    end

    -- interaction
    if hovered then
        local sx, sy = card_screen(w, r, hovered)
        if ui.clicked(sx, sy, CARD_W * w.zoom, CARD_H * w.zoom) then
            if w.link_mode then
                if not w.link_from then
                    w.link_from = hovered.id; ui.sound("beep", { pitch = 1.3 })
                elseif w.link_from ~= hovered.id then
                    markers.link(w.link_from, hovered.id)
                    ui.sound("lock", { volume = 0.7 })
                    ui.print("{accent}↔{} linked {white}" .. markers.label(markers.get(w.link_from)):gsub("{", "{{") ..
                        "{} ↔ {white}" .. markers.label(hovered):gsub("{", "{{"))
                    if not love.keyboard.isDown("lshift", "rshift") then w.link_mode, w.link_from = false, nil else w.link_from = hovered.id end
                end
            else
                markers.select(hovered.id)
                w.cdrag = { id = hovered.id, grabx = (mx - sx), graby = (my - sy), moved = false }
                ui.sound("beep", { pitch = 1.05, volume = 0.5 })
            end
        end
        if w.link_mode then ui.tooltip(w.link_from and ("link to " .. markers.label(hovered)) or ("start a link from " .. markers.label(hovered))) end
    end
    if hover_board and not hovered and not w.link_mode and ui.clicked(r.x, r.y, r.w, r.h) then
        w.pan = { x = mx, y = my, ox = w.ox, oy = w.oy, moved = false }
        markers.selected = nil
    end
    -- dragging a card
    if w.cdrag then
        local m = markers.get(w.cdrag.id)
        if ui.mouse.down and m then
            if math.abs(ui.mouse.dx or 0) + math.abs(ui.mouse.dy or 0) > 0 then w.cdrag.moved = true end
            m.bx = (mx - r.x - w.ox - w.cdrag.grabx) / w.zoom
            m.by = (my - r.y - w.oy - w.cdrag.graby) / w.zoom
        else
            if w.cdrag.moved then markers.touch(); ui.sound("tick", { pitch = 0.9, volume = 0.4 }) end
            w.cdrag = nil
        end
    end
    -- panning the board
    if w.pan then
        if ui.mouse.down then
            w.ox = w.pan.ox + (mx - w.pan.x)
            w.oy = w.pan.oy + (my - w.pan.y)
        else
            w.pan = nil
        end
    end

    local hint = w.link_mode and (w.link_from and "click another card to link" or "click a card to start a link")
        or "drag cards to arrange  ·  drag background to pan  ·  wheel to zoom"
    ui.set_color("bg", 0.8)
    love.graphics.rectangle("fill", r.x + 6, r.y + r.h - 22, ui.font:getWidth(hint) + 10, 17, 2, 2)
    ui.text(hint, r.x + 11, r.y + r.h - 20, w.link_mode and "accent" or "dim")

    if ui.clip then love.graphics.setScissor(unpack(ui.clip)) else love.graphics.setScissor() end
    ui.set_color("faint", 1); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
end

return W
