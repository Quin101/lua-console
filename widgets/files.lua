-- FILES: a real file vault stored in the save folder.
-- Make folders, text documents, and import images and any other files
-- (drag them onto the window). Everything is saved under …/qrawller/vault.
local vault = require("src.vault")
local images = require("src.images")
local util = require("src.util")

local W = {
    title = "FILES",
    tab = "FILES",
    order = 2,
    height = "fill",
    width = 0.6,
    collapsible = false,
}

local ICON = { folder = "⊞", text = "≡", image = "■", file = "□" }
local ICON_COLOR = { folder = "accent", text = "white", image = "info", file = "dim" }

local function refresh(w)
    w.items = vault.list(w.dir)
end

function W.load(w, ui)
    vault.init()
    w.dir = vault.ROOT
    w.sel = nil             -- selected item path
    w.scroll = 0
    w.open = nil            -- open text/image path
    w.text = ""
    w.renaming = nil        -- path being renamed
    w.rename_val = ""
    w.confirm = nil
    w.view = "list"         -- list | grid
    refresh(w)
end

function W.status(w)
    return vault.size_str(vault.total(vault.ROOT))
end

function W.update(w, dt)
    vault.flush()
end

local function go(w, ui, dir)
    w.dir = dir
    w.sel = nil
    w.scroll = 0
    w.open = nil
    w.renaming = nil
    refresh(w)
    ui.sound("tick", { pitch = 1.1 })
end

local function open_item(w, ui, it)
    if it.kind == "folder" then
        go(w, ui, it.path)
    elseif it.kind == "text" then
        vault.flush(true)
        w.open = it.path
        w.text = vault.read(it.path)
        ui.focus_field("file_edit")
        ui.focus_from_click = true
        ui.sound("beep", { pitch = 1.1, volume = 0.4 })
    elseif it.kind == "image" then
        local imgs, idx = {}, 1
        for _, x in ipairs(w.items) do
            if x.kind == "image" then
                imgs[#imgs + 1] = x.path
                if x.path == it.path then idx = #imgs end
            end
        end
        ui.open_viewer(imgs, idx, vault.basename(it.path))
    else
        ui.sound("beep", { pitch = 0.8, volume = 0.4 })
        ui.print("{dim}" .. it.name:gsub("{", "{{") .. " — " .. vault.size_str(it.size) .. "  (open the vault folder to use it)")
    end
end

-- toolbar + breadcrumb ---------------------------------------------------------

local function draw_bar(w, ui, x, y, width)
    local bh = 26
    if ui.button("f_new_folder", "+ FOLDER", x, y, 96, bh, { tip = "create a folder" }) then
        w.sel = vault.mkdir(w.dir, "new folder"); refresh(w); ui.sound("place", { volume = 0.5 })
        w.renaming, w.rename_val = w.sel, vault.basename(w.sel); ui.focus_field_all("file_rename"); ui.focus_from_click = true
    end
    if ui.button("f_new_doc", "+ DOC", x + 102, y, 76, bh, { tip = "create a text document" }) then
        w.sel = vault.new_text(w.dir, "untitled.txt"); refresh(w); ui.sound("place", { volume = 0.5 })
        w.renaming, w.rename_val = w.sel, vault.basename(w.sel); ui.focus_field_all("file_rename"); ui.focus_from_click = true
    end
    if ui.button("f_view", w.view == "list" and "GRID" or "LIST", x + 184, y, 64, bh, { tip = "switch view" }) then
        w.view = w.view == "list" and "grid" or "list"; ui.sound("tick")
    end
    if ui.button("f_reveal", "OPEN FOLDER", x + width - 112, y, 112, bh, { tip = "open the vault in your file browser" }) then
        vault.reveal(w.dir); ui.sound("whoosh", { volume = 0.4 })
    end

    -- breadcrumb
    local by = y + bh + 8
    local parts = {}
    for p in (w.dir):gmatch("[^/]+") do parts[#parts + 1] = p end
    local cx = x
    local acc_path = ""
    for i, part in ipairs(parts) do
        acc_path = i == 1 and part or (acc_path .. "/" .. part)
        local label = (i == 1 and "vault" or part)
        local tw = ui.font:getWidth(label)
        local last = i == #parts
        local hov = ui.hover(cx, by, tw, 16)
        ui.text(label, cx, by, last and "white" or (hov and "accent" or "text"))
        if not last and ui.clicked(cx, by, tw, 16) then go(w, ui, acc_path) end
        cx = cx + tw
        if not last then ui.text("  ›  ", cx, by, "dim"); cx = cx + ui.font:getWidth("  ›  ") end
    end
    return by + 22
end

-- an item's context actions (shown for the selected row)
local function item_actions(w, ui, it, x, y)
    local bw = 54
    if ui.button("f_rename", "RENAME", x, y, 64, 20, { bold = false }) then
        w.renaming, w.rename_val = it.path, it.name
        ui.focus_field_all("file_rename"); ui.focus_from_click = true
    end
    local confirming = w.confirm == it.path and ui.time() - (w.confirm_at or 0) < 3
    if ui.button("f_delete", confirming and "CONFIRM" or "DELETE", x + 70, y, confirming and 68 or 64, 20, { bold = false, active = confirming }) then
        if confirming then
            vault.remove(it.path); w.confirm = nil; w.sel = nil; w.open = nil
            refresh(w); ui.sound("err", { volume = 0.6 }); ui.fx.glitch(0.2, 0.4)
        else
            w.confirm, w.confirm_at = it.path, ui.time()
        end
    end
end

-- list / grid ------------------------------------------------------------------

local function draw_list(w, ui, x, y, lw, lh)
    local rh = 24
    w.list_rect = { x = x, y = y, w = lw, h = lh }
    if #w.items == 0 then
        ui.text("empty folder", x + 4, y + 6, "dim")
        ui.text("drag files here, or use + FOLDER / + DOC", x + 4, y + 26, "faint")
        return
    end
    local visible = math.max(1, math.floor(lh / rh))
    w.scroll = util.clamp(w.scroll, 0, math.max(0, #w.items - visible))
    local first = math.floor(w.scroll) + 1
    for i = first, math.min(#w.items, first + visible - 1) do
        local it = w.items[i]
        local ry = y + (i - first) * rh
        local sel = w.sel == it.path
        local hov = ui.hover(x, ry, lw, rh)
        local hv = ui.ease("f_row_" .. it.path, (hov or sel) and 1 or 0, 16)
        ui.set_color("accent", 0.04 + hv * 0.08)
        love.graphics.rectangle("fill", x, ry + 1, lw, rh - 2, 2, 2)
        if sel then ui.set_color("accent", 1); love.graphics.rectangle("fill", x, ry + 1, 2, rh - 2) end
        ui.text(ICON[it.kind], x + 8, ry + 4, ICON_COLOR[it.kind])
        if w.renaming == it.path then
            w.rename_val = ui.textfield("file_rename", w.rename_val, x + 26, ry + 2, lw - 34, rh - 4)
        else
            local name = it.name
            local maxw = lw - 34 - (it.kind == "folder" and 46 or 70)
            while ui.font:getWidth(name) > maxw and #name > 4 do name = name:sub(1, -5) .. "…" end
            ui.text(name, x + 26 + hv * 2, ry + 4, sel and "white" or "text")
            local meta = it.kind == "folder" and (vault.count(it.path) .. " items") or vault.size_str(it.size)
            ui.text(meta, x + lw - ui.font:getWidth(meta), ry + 4, "dim")
        end
        if ui.clicked(x, ry, lw, rh) and w.renaming ~= it.path then
            if w.sel == it.path and ui.time() - (w.last_click or 0) < 0.4 then
                open_item(w, ui, it)
            else
                w.sel = it.path
                ui.sound("tick", { pitch = 1.05, volume = 0.5 })
            end
            w.last_click = ui.time()
        end
    end
    if #w.items > visible then
        local bh = lh * visible / #w.items
        local by = y + (lh - bh) * (w.scroll / math.max(1, #w.items - visible))
        ui.set_color("accent", 0.5); love.graphics.rectangle("fill", x + lw - 2, by, 2, bh)
    end
end

local function draw_grid(w, ui, x, y, gw, gh)
    w.list_rect = { x = x, y = y, w = gw, h = gh }
    local cell = 96
    local cols = math.max(1, math.floor(gw / cell))
    cell = gw / cols
    local ch = cell + 6
    if #w.items == 0 then ui.text("empty folder — drag files here", x + 4, y + 6, "dim"); return end
    local rows_vis = math.max(1, math.floor(gh / ch))
    local maxscroll = math.max(0, math.ceil(#w.items / cols) - rows_vis)
    w.scroll = util.clamp(w.scroll, 0, maxscroll)
    local first_row = math.floor(w.scroll)
    for i = 1 + first_row * cols, math.min(#w.items, (first_row + rows_vis) * cols) do
        local it = w.items[i]
        local gi = i - 1
        local cx = x + (gi % cols) * cell
        local cy = y + (math.floor(gi / cols) - first_row) * ch
        local pad = 6
        local sel = w.sel == it.path
        local hov = ui.hover(cx, cy, cell - 4, ch - 4)
        local hv = ui.ease("f_cell_" .. it.path, (hov or sel) and 1 or 0, 16)
        ui.set_color("accent", 0.03 + hv * 0.08)
        love.graphics.rectangle("fill", cx + 1, cy + 1, cell - 6, ch - 6, 3, 3)
        local box = cell - 6 - pad * 2
        local ix, iy = cx + pad + 3, cy + pad
        if it.kind == "image" then
            local img = images.get(it.path)
            ui.set_color("bg", 0.8); love.graphics.rectangle("fill", ix, iy, box, box)
            if img then images.draw_fit(img, ix, iy, box, box, true) end
            ui.set_color(sel and "accent" or "faint", 1); love.graphics.rectangle("line", ix, iy, box, box)
        else
            ui.set_color(ICON_COLOR[it.kind], 0.1 + hv * 0.08); love.graphics.rectangle("fill", ix, iy, box, box, 3, 3)
            love.graphics.setFont(ui.T.font)
            ui.text_center(ICON[it.kind], ix, iy + box / 2 - 12, box, ICON_COLOR[it.kind], ui.T.font)
        end
        local name = it.name
        while ui.font:getWidth(name) > cell - 10 and #name > 4 do name = name:sub(1, -5) .. "…" end
        ui.text_center(name, cx, cy + ch - 20, cell - 4, sel and "white" or "text")
        if sel then ui.set_color("accent", 1); love.graphics.rectangle("line", cx + 1, cy + 1, cell - 6, ch - 6, 3, 3) end
        if ui.clicked(cx, cy, cell - 4, ch - 4) then
            if w.sel == it.path and ui.time() - (w.last_click or 0) < 0.4 then open_item(w, ui, it)
            else w.sel = it.path; ui.sound("tick", { pitch = 1.05, volume = 0.5 }) end
            w.last_click = ui.time()
        end
    end
    if maxscroll > 0 then
        local bh = gh * rows_vis / math.ceil(#w.items / cols)
        local by = y + (gh - bh) * (w.scroll / maxscroll)
        ui.set_color("accent", 0.5); love.graphics.rectangle("fill", x + gw - 2, by, 2, bh)
    end
end

-- text editor ------------------------------------------------------------------

local function draw_editor(w, ui, x, y, ew, eh)
    local name = vault.basename(w.open)
    ui.text(ICON.text .. "  " .. name, x, y, "white", ui.font_bold)
    local saved = vault.is_saved(w.open)
    ui.text(saved and "saved" or "saving…", x + ew - ui.font:getWidth("saving…"), y + 2, saved and "dim" or "accent")
    local ty = y + 22
    local th = eh - 22 - 30
    local nv = ui.textfield("file_edit", w.text, x, ty, ew, th, { multiline = true, placeholder = "type your notes…" })
    if nv ~= w.text then w.text = nv; vault.write_later(w.open, nv) end
    local by = y + eh - 24
    local words = select(2, w.text:gsub("%S+", ""))
    ui.text(#w.text .. " chars · " .. words .. " words", x, by + 4, "dim")
    if ui.button("f_close", "CLOSE", x + ew - 76, by, 76, 24) then
        vault.write_later(w.open, w.text); vault.flush(true)
        w.open = nil; ui.unfocus(); refresh(w); ui.sound("back")
    end
end

-- info / preview pane ----------------------------------------------------------

local function draw_side(w, ui, x, y, sw, sh)
    local it
    for _, x2 in ipairs(w.items) do if x2.path == w.sel then it = x2 end end
    if not it then
        ui.text("FILE VAULT", x, y + 4, "text", ui.font_bold)
        local v, p = nil, nil
        local lines = {
            "▣ folders   ≡ documents   ▤ images   ◰ files",
            "",
            "double-click to open",
            "drag files or folders onto the window to import",
            "OPEN FOLDER reveals the vault on disk",
            "",
            "stored in " .. vault.pretty(vault.ROOT) .. " in the save folder",
        }
        for i, l in ipairs(lines) do ui.text(l, x, y + 28 + (i - 1) * 18, i == 1 and "text" or "dim") end
        return
    end
    ui.text(ICON[it.kind] .. "  " .. it.kind:upper(), x, y + 2, ICON_COLOR[it.kind], ui.font_bold)
    if it.kind == "image" then
        local img = images.get(it.path)
        local box = math.min(sw, sh - 120)
        if img then
            images.draw_fit(img, x, y + 24, sw, box, false)
            local iw, ih = img:getDimensions()
            ui.text(iw .. "×" .. ih .. " px", x, y + 28 + box, "dim")
        end
    end
    local info_y = it.kind == "image" and (y + sh - 78) or (y + 30)
    local name = it.name
    while ui.font:getWidth(name) > sw and #name > 4 do name = name:sub(1, -5) .. "…" end
    ui.text(name, x, info_y, "white")
    ui.text(it.kind == "folder" and (vault.count(it.path) .. " items · " .. vault.size_str(vault.total(it.path)))
        or vault.size_str(it.size), x, info_y + 18, "dim")
    if it.modtime then ui.text(os.date("%Y-%m-%d %H:%M", it.modtime), x, info_y + 34, "dim") end
    item_actions(w, ui, it, x, info_y + 56)
end

function W.draw(w, ui, x, y, width, height)
    local list_y = draw_bar(w, ui, x, y, width)
    local lh = y + height - list_y
    if lh < 40 then return end
    local lw = math.floor(width * 0.52)
    if w.view == "grid" then draw_grid(w, ui, x, list_y, lw, lh) else draw_list(w, ui, x, list_y, lw, lh) end
    ui.set_color("faint", 1); love.graphics.rectangle("fill", x + lw + 12, list_y, 1, lh)
    local sx, sw = x + lw + 26, width - lw - 26
    if w.open then draw_editor(w, ui, sx, list_y, sw, lh) else draw_side(w, ui, sx, list_y, sw, lh) end

    -- commit a rename when focus leaves the box
    if w.renaming and (not ui.focus or ui.focus.id ~= "file_rename") then
        local newp = vault.rename(w.renaming, w.rename_val)
        w.sel = newp; w.renaming = nil; refresh(w); ui.sound("lock", { volume = 0.5 })
    end
end

function W.wheelmoved(w, ui, dx, dy)
    w.scroll = math.max(0, w.scroll - dy)
end

function W.keypressed(w, ui, key)
    if key == "escape" and w.open then
        vault.flush(true); w.open = nil; ui.unfocus(); return true
    end
    return false
end

-- dropping a file imports it into the current folder
function W.filedropped(w, ui, file)
    if ui.active_tab ~= W.tab then return false end
    local name = file:getFilename():match("([^/\\]+)$") or "file"
    file:open("r")
    local data = file:read()
    file:close()
    local path = vault.import(w.dir, name, data)
    refresh(w); w.sel = path
    ui.sound("place", { volume = 0.6 }); ui.fx.flash("accent", 0.1)
    ui.print("{accent}▸{} imported {white}" .. name:gsub("{", "{{") .. "{}  {dim}→ " .. vault.pretty(w.dir))
    return true
end

function W.directorydropped(w, ui, path)
    if ui.active_tab ~= W.tab then return false end
    local target = vault.import_folder(w.dir, path)
    refresh(w)
    if target then
        w.sel = target
        ui.sound("place", { volume = 0.6 })
        ui.print("{accent}▸{} imported folder {white}" .. vault.basename(target):gsub("{", "{{"))
    else
        ui.sound("err"); ui.print("{err}✗{} could not import that folder")
    end
    return true
end

return W
