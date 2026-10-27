-- CASE BOARD: a free-form corkboard of note cards joined by red string.
-- This is its OWN space — nothing here is tied to the map markers.
-- Add cards, type a title + notes, colour them, drop a photo on one,
-- link them, drag them around. Everything saves automatically.
local board = require("src.board")
local images = require("src.images")
local util = require("src.util")

local CARD_W, CARD_H = 184, 120

local W = {
    title = "CASE BOARD",
    tab = "BOARD",
    order = 3,
    height = "fill",
    width = 0.6,
    collapsible = false,
}

function W.load(w, ui)
    w.ox, w.oy = 0, 0
    w.zoom, w.tz = 1, 1
    w.link_mode = false
    w.link_from = nil
    if #board.cards == 0 and #board.links == 0 then board.load() end
end

function W.status(w)
    return #board.cards .. " cards  ·  " .. #board.links .. " links"
end

function W.update(w, dt)
    board.update()
    local k = math.min(1, dt * 10)
    w.zoom = w.zoom + (w.tz - w.zoom) * k
end

function W.keypressed(w, ui, key)
    if key == "escape" then
        if w.link_mode or w.link_from then w.link_mode, w.link_from = false, nil; ui.sound("back"); return true end
        if board.selected then board.selected = nil; ui.unfocus(); return true end
    end
    return false
end

function W.wheelmoved(w, ui, dx, dy)
    local r = w.rect
    if not r or not ui.hover(r.x, r.y, r.w, r.h) then return end
    local mx, my = ui.mouse.x, ui.mouse.y
    local bx = (mx - r.x - w.ox) / w.zoom
    local by = (my - r.y - w.oy) / w.zoom
    w.tz = util.clamp(w.tz * 1.15 ^ dy, 0.4, 2.2)
    w.zoom = w.tz
    w.ox = mx - r.x - bx * w.zoom
    w.oy = my - r.y - by * w.zoom
    ui.sound("tick", { pitch = dy > 0 and 1.2 or 0.8, volume = 0.4 })
end

-- drop an image onto a card to set its photo
function W.filedropped(w, ui, file)
    if ui.active_tab ~= W.tab or not w.rect then return false end
    local mx, my = ui.mouse.x, ui.mouse.y
    local target
    for _, c in ipairs(board.cards) do
        local sx, sy = w.rect.x + w.ox + c.x * w.zoom, w.rect.y + w.oy + c.y * w.zoom
        if mx >= sx and mx < sx + CARD_W * w.zoom and my >= sy and my < sy + CARD_H * w.zoom then target = c end
    end
    target = target or (board.selected and board.get(board.selected))
    if not target then return false end
    local name = file:getFilename():match("([^/\\]+)$") or "photo.png"
    if not images.is_image_name(name) then return false end
    file:open("r"); local data = file:read(); file:close()
    local ok, err = board.set_photo(target, name, data)
    if ok then
        board.selected = target.id
        w.drop_flash = ui.time()
        ui.sound("place"); ui.fx.flash("accent", 0.12)
        ui.print("{accent}▤{} photo set on {white}" .. board.title(target):gsub("{", "{{"))
    else
        ui.sound("err"); ui.print("{err}✗{} " .. err)
    end
    return true
end

local function card_screen(w, r, c)
    return r.x + w.ox + c.x * w.zoom, r.y + w.oy + c.y * w.zoom
end

local function pin_point(w, r, c)
    local sx, sy = card_screen(w, r, c)
    return sx + CARD_W * w.zoom / 2, sy + 8 * w.zoom
end

local function draw_string(ui, x1, y1, x2, y2, label, time, strong, zoom)
    local acc = util.palette.accent
    local sag = math.min(44, math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * 0.16) * zoom
    local mx, my = (x1 + x2) / 2, (y1 + y2) / 2 + sag
    local pts = {}
    for i = 0, 16 do
        local t = i / 16
        local u = 1 - t
        pts[#pts + 1] = u * u * x1 + 2 * u * t * mx + t * t * x2
        pts[#pts + 1] = u * u * y1 + 2 * u * t * my + t * t * y2
    end
    love.graphics.setColor(acc[1] * 0.5, acc[2] * 0.2, acc[3] * 0.2, strong and 0.9 or 0.55)
    love.graphics.setLineWidth((strong and 2 or 1.4) * util.clamp(zoom, 0.6, 1.4))
    love.graphics.line(pts)
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

local function draw_card(w, ui, c, sx, sy)
    local z = w.zoom
    local cw, ch = CARD_W * z, CARD_H * z
    local selected = board.selected == c.id
    local hov = ui.hover(sx, sy, cw, ch)
    local col = c.color or "accent"
    local cc = util.color(col)

    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", sx + 3, sy + 4, cw, ch, 3, 3)
    ui.set_color("bg2", 0.98)
    love.graphics.rectangle("fill", sx, sy, cw, ch, 3, 3)
    -- coloured top band
    love.graphics.setColor(cc[1], cc[2], cc[3], 0.16)
    love.graphics.rectangle("fill", sx, sy, cw, 4 * z)
    love.graphics.setColor(cc[1], cc[2], cc[3], selected and 1 or (hov and 0.8 or 0.45))
    love.graphics.setLineWidth(selected and 2 or 1)
    love.graphics.rectangle("line", sx + 0.5, sy + 0.5, cw - 1, ch - 1, 3, 3)

    if z > 0.5 then
        local pad = 9 * z
        local tx, ty = sx + pad, sy + pad + 2 * z
        local inner = cw - pad * 2
        -- optional photo on the right
        local img = c.photo and images.get(c.photo)
        local tw = inner
        if img then
            local th = ch - pad * 2 - 4 * z
            local pw = math.min(th, 64 * z)
            images.draw_fit(img, sx + cw - pad - pw, ty, pw, th, true)
            love.graphics.setColor(cc[1], cc[2], cc[3], 0.6)
            love.graphics.rectangle("line", sx + cw - pad - pw, ty, pw, th)
            tw = inner - pw - 8 * z
        end
        if z > 0.68 then
            local title = board.title(c)
            local _, tl = ui.font_bold:getWrap(title, tw)
            ui.text(tl[1] or title, tx, ty, c.title ~= "" and "white" or "dim", ui.font_bold)
            local byy = ty + 16
            if tl[2] then ui.text(tl[2], tx, byy, "white", ui.font_bold); byy = byy + 15 end
            if c.body and c.body ~= "" then
                local _, bl = ui.font:getWrap(c.body, tw)
                for i = 1, math.min(#bl, math.floor((sy + ch - pad - byy) / 14)) do
                    ui.text(bl[i], tx, byy + (i - 1) * 14, "text")
                end
            end
            local links = 0
            for _, l in ipairs(board.links) do if l.a == c.id or l.b == c.id then links = links + 1 end end
            if links > 0 then ui.text("↔" .. links, tx, sy + ch - pad - 10, "dim") end
        end
    end

    -- pushpin
    local px, py = sx + cw / 2, sy + 8 * z
    love.graphics.setColor(0, 0, 0, 0.4); love.graphics.circle("fill", px + 1, py + 2, 4 * z)
    love.graphics.setColor(cc[1], cc[2], cc[3], 1); love.graphics.circle("fill", px, py, 4 * z)
    ui.set_color("white", 0.8); love.graphics.circle("fill", px - z, py - z, 1.5 * z)
    return hov
end

-- bottom editor for the selected card ----------------------------------------

local function draw_editor(w, ui, c, x, y, ew, eh)
    ui.set_color("faint", 1); love.graphics.setLineWidth(1)
    love.graphics.line(x, y - 4, x + ew, y - 4)
    local photo_w = 86
    local tw = ew - photo_w - 14
    -- title
    local nt = ui.textfield("cb_title_" .. c.id, c.title or "", x, y, tw, 26, { placeholder = "card title…", label = "title" })
    if nt ~= (c.title or "") then c.title = nt; board.touch() end
    -- body
    local by = y + 46
    local nb = ui.textfield("cb_body_" .. c.id, c.body or "", x, by, tw, eh - 46 - 26, { placeholder = "notes…", label = "notes", multiline = true })
    if nb ~= (c.body or "") then c.body = nb; board.touch() end

    -- colour swatches + actions row
    local ay = y + eh - 22
    ui.text("colour", x, ay + 2, "dim")
    local cxp = x + 50
    for _, name in ipairs(board.COLORS) do
        local cc = util.color(name)
        local active = (c.color or "accent") == name
        local hov = ui.hover(cxp - 8, ay, 16, 18)
        local r = (active and 8 or 6) + (hov and 1 or 0)
        love.graphics.setColor(cc[1], cc[2], cc[3], 1)
        love.graphics.circle("fill", cxp, ay + 8, r)
        if active then love.graphics.setColor(1, 1, 1, 1); love.graphics.setLineWidth(1); love.graphics.circle("line", cxp, ay + 8, r + 3) end
        if ui.clicked(cxp - 8, ay, 16, 18) then c.color = name; board.touch(); ui.sound("tick", { pitch = 1.1 }) end
        cxp = cxp + 26
    end

    -- photo box on the right
    local px = x + ew - photo_w
    local img = c.photo and images.get(c.photo)
    local ph = eh - 24
    ui.set_color("bg", 0.7); love.graphics.rectangle("fill", px, y, photo_w, ph, 3, 3)
    if img then
        images.draw_fit(img, px + 2, y + 2, photo_w - 4, ph - 4, true)
        ui.set_color("accent", 0.7); love.graphics.rectangle("line", px + 0.5, y + 0.5, photo_w - 1, ph - 1, 3, 3)
        if ui.hover(px, y, photo_w, ph) then
            if ui.button("cb_photo_clear", "×", px + photo_w - 20, y + 3, 17, 17, { tip = "remove photo" }) then board.clear_photo(c); ui.sound("back") end
            if ui.clicked(px, y, photo_w, ph) then ui.open_viewer({ c.photo }, 1, board.title(c)) end
        end
    else
        ui.set_color(ui.hover(px, y, photo_w, ph) and "accent" or "faint", 1); love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", px + 0.5, y + 0.5, photo_w - 1, ph - 1, 3, 3)
        ui.text_center("drop", px, y + ph / 2 - 16, photo_w, "dim")
        ui.text_center("photo", px, y + ph / 2 - 2, photo_w, "dim")
    end

    -- link / delete buttons
    local rbw = 70
    if ui.button("cb_link_sel", "↔ LINK", x + ew - photo_w - 8 - rbw * 2 - 6, ay - 2, rbw, 22, { active = w.link_mode, bold = false }) then
        w.link_mode = not w.link_mode; w.link_from = w.link_mode and c.id or nil
        ui.sound(w.link_mode and "beep" or "back", { pitch = 1.2 })
    end
    local confirming = w.confirm == c.id and ui.time() - (w.confirm_at or 0) < 3
    if ui.button("cb_del", confirming and "SURE?" or "DELETE", x + ew - photo_w - 8 - rbw, ay - 2, rbw, 22, { active = confirming, bold = false }) then
        if confirming then board.remove(c.id); w.confirm = nil; ui.unfocus(); ui.sound("err", { volume = 0.6 }); ui.fx.glitch(0.25, 0.5)
        else w.confirm, w.confirm_at = c.id, ui.time() end
    end
end

function W.draw(w, ui, x, y, width, height)
    local bh = 26
    if ui.button("cb_add", "+ CARD", x, y, 86, bh, { tip = "add a note card" }) then
        local r = w.rect or { x = x, y = y, w = width, h = height }
        local cx = (r.w / 2 - w.ox) / w.zoom - CARD_W / 2
        local cy = (r.h / 2 - w.oy) / w.zoom - CARD_H / 2
        local c = board.add(cx, cy)
        ui.sound("place"); ui.fx.sparks(r.x + r.w / 2, r.y + r.h / 2, 12, "accent", 80)
        ui.focus_field("cb_title_" .. c.id); ui.focus_from_click = true
    end
    if ui.button("cb_link", "↔ LINK", x + 92, y, 86, bh, { active = w.link_mode, tip = "connect two cards" }) then
        w.link_mode = not w.link_mode; w.link_from = nil
        ui.sound(w.link_mode and "beep" or "back", { pitch = 1.2 })
    end
    local zx = x + width - 3 * 34 - 52
    if ui.button("cb_zoom_out", "−", zx, y, 30, bh) then w.tz = util.clamp(w.tz / 1.3, 0.4, 2.2) end
    if ui.button("cb_zoom_in", "+", zx + 34, y, 30, bh) then w.tz = util.clamp(w.tz * 1.3, 0.4, 2.2) end
    if ui.button("cb_fit", "FIT", zx + 68, y, 82, bh, { tip = "recentre the board" }) then
        w.ox, w.oy, w.tz = 0, 0, 1; ui.sound("whoosh", { volume = 0.4 })
    end

    local sel = board.selected and board.get(board.selected)
    local edh = sel and 128 or 0
    local r = { x = x, y = y + bh + 10, w = width, h = (y + height) - (y + bh + 10) - (edh > 0 and edh + 10 or 0) }
    w.rect = r
    local time = ui.time()

    ui.set_color("bg", 0.5)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    love.graphics.intersectScissor(r.x, r.y, r.w, r.h)
    -- panning dot grid
    local gap = 28 * w.zoom
    ui.set_color("faint", 0.5)
    love.graphics.setPointSize(1.4)
    local pts = {}
    for gx = r.x + (w.ox % gap), r.x + r.w, gap do for gy = r.y + (w.oy % gap), r.y + r.h, gap do pts[#pts + 1] = gx; pts[#pts + 1] = gy end end
    if #pts > 0 then love.graphics.points(pts) end

    if #board.cards == 0 then
        ui.text_center("empty board — press + CARD to pin your first note", r.x, r.y + r.h / 2 - 8, r.w, "dim")
        if ui.clip then love.graphics.setScissor(unpack(ui.clip)) else love.graphics.setScissor() end
        ui.set_color("faint", 1); love.graphics.setLineWidth(1); love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
        return
    end

    local mx, my = ui.mouse.x, ui.mouse.y
    local hover_board = ui.hover(r.x, r.y, r.w, r.h) and not ui.focus

    local hovered
    for _, c in ipairs(board.cards) do
        local sx, sy = card_screen(w, r, c)
        if hover_board and mx >= sx and mx < sx + CARD_W * w.zoom and my >= sy and my < sy + CARD_H * w.zoom then hovered = c end
    end

    -- strings
    for _, l in ipairs(board.links) do
        local a, b = board.get(l.a), board.get(l.b)
        if a and b then
            local x1, y1 = pin_point(w, r, a)
            local x2, y2 = pin_point(w, r, b)
            draw_string(ui, x1, y1, x2, y2, l.label, time, board.selected == l.a or board.selected == l.b, w.zoom)
        end
    end
    if w.link_from then
        local a = board.get(w.link_from)
        if a then
            local x1, y1 = pin_point(w, r, a)
            local tx = (hovered and hovered.id ~= w.link_from) and (select(1, pin_point(w, r, hovered))) or mx
            local ty = (hovered and hovered.id ~= w.link_from) and (select(2, pin_point(w, r, hovered))) or my
            draw_string(ui, x1, y1, tx, ty, nil, time, true, w.zoom)
        end
    end

    -- cards (selected last)
    local order = {}
    for _, c in ipairs(board.cards) do if c.id ~= board.selected then order[#order + 1] = c end end
    for _, c in ipairs(board.cards) do if c.id == board.selected then order[#order + 1] = c end end
    for _, c in ipairs(order) do
        local sx, sy = card_screen(w, r, c)
        draw_card(w, ui, c, sx, sy)
    end

    -- interaction
    if hovered then
        local sx, sy = card_screen(w, r, hovered)
        if ui.clicked(sx, sy, CARD_W * w.zoom, CARD_H * w.zoom) then
            if w.link_mode then
                if not w.link_from then w.link_from = hovered.id; ui.sound("beep", { pitch = 1.3 })
                elseif w.link_from ~= hovered.id then
                    board.link(w.link_from, hovered.id)
                    ui.sound("lock", { volume = 0.7 })
                    ui.print("{accent}↔{} linked {white}" .. board.title(board.get(w.link_from)):gsub("{", "{{") .. "{} ↔ {white}" .. board.title(hovered):gsub("{", "{{"))
                    if not love.keyboard.isDown("lshift", "rshift") then w.link_mode, w.link_from = false, nil else w.link_from = hovered.id end
                end
            else
                if board.selected ~= hovered.id then ui.unfocus() end
                board.selected = hovered.id
                w.cdrag = { id = hovered.id, grabx = mx - sx, graby = my - sy, moved = false }
                ui.sound("beep", { pitch = 1.05, volume = 0.5 })
            end
        end
        if w.link_mode then ui.tooltip(w.link_from and ("link to " .. board.title(hovered)) or ("start a link from " .. board.title(hovered))) end
    end
    if hover_board and not hovered and not w.link_mode and ui.clicked(r.x, r.y, r.w, r.h) then
        w.pan = { x = mx, y = my, ox = w.ox, oy = w.oy }
        board.selected = nil; ui.unfocus()
    end
    if w.cdrag then
        local c = board.get(w.cdrag.id)
        if ui.mouse.down and c then
            if math.abs(ui.mouse.dx or 0) + math.abs(ui.mouse.dy or 0) > 0 then w.cdrag.moved = true end
            c.x = (mx - r.x - w.ox - w.cdrag.grabx) / w.zoom
            c.y = (my - r.y - w.oy - w.cdrag.graby) / w.zoom
        else
            if w.cdrag.moved then board.touch(); ui.sound("tick", { pitch = 0.9, volume = 0.4 }) end
            w.cdrag = nil
        end
    end
    if w.pan then
        if ui.mouse.down then w.ox = w.pan.ox + (mx - w.pan.x); w.oy = w.pan.oy + (my - w.pan.y) else w.pan = nil end
    end

    local hint = w.link_mode and (w.link_from and "click another card to link" or "click a card to start a link")
        or "click a card to edit  ·  drag to move  ·  drag background to pan  ·  wheel to zoom"
    ui.set_color("bg", 0.8); love.graphics.rectangle("fill", r.x + 6, r.y + r.h - 22, ui.font:getWidth(hint) + 10, 17, 2, 2)
    ui.text(hint, r.x + 11, r.y + r.h - 20, w.link_mode and "accent" or "dim")

    if ui.clip then love.graphics.setScissor(unpack(ui.clip)) else love.graphics.setScissor() end
    ui.set_color("faint", 1); love.graphics.setLineWidth(1); love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)

    if sel then draw_editor(w, ui, sel, x, r.y + r.h + 14, width, edh - 4) end
end

return W
