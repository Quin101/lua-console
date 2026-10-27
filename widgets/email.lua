-- EMAIL: a compose window that sends real mail through your own SMTP account.
-- Same engine as the `email` terminal command (src/email.lua). Nothing is sent
-- until you set up your account and press SEND.
local email = require("src.email")
local util = require("src.util")

local draw_picker, add_attachment  -- defined below

local W = {
    title = "EMAIL",
    tab = "MAIL",
    order = 5,
    height = "fill",
    width = 0.5,
    collapsible = false,
}

function W.load(w, ui)
    w.cfg = email.load()
    w.to = ""
    w.subject = ""
    w.body = ""
    w.visible = false
    w.attach = {}
    w.picker = nil
    w.result = nil          -- { ok, text, hint, at }
    w.sending = false
    w.send_at = nil
    w.mode = email.configured(w.cfg) and "compose" or "setup"
    w.curl = email.curl_ok()
end

function W.status(w)
    if not email.configured(w.cfg or email.load()) then return "not set up" end
    return (w.cfg and w.cfg.from) or ""
end

-- a sent/failed message is actually fired one frame after SEND so the UI can
-- paint "sending…" first
function W.update(w, dt, ui)
    if w.send_at and ui.time() >= w.send_at then
        w.send_at = nil
        local ok, detail, hint, n = email.send(w.cfg, w.pending.to, w.pending.subject, w.pending.body, { visible = w.pending.visible })
        w.sending = false
        w.result = { ok = ok, text = detail, hint = hint, at = ui.time(), n = n }
        if ok then
            ui.sound("ok"); ui.fx.flash("accent", 0.15)
            w.to, w.subject, w.body, w.attach = "", "", "", {}
            ui.print("{accent}✓{} email sent to " .. (n or 1) .. " recipient" .. ((n or 1) == 1 and "" or "s"))
        else
            ui.sound("err"); ui.fx.glitch(0.25, 0.4)
        end
    end
end

-- settings form --------------------------------------------------------------

local PROVIDER_ROW = { "gmail", "outlook", "yahoo", "icloud" }

local function draw_setup(w, ui, x, y, width, height)
    ui.text("ACCOUNT SETUP", x, y, "text", ui.font_bold)
    ui.text(w.curl and "curl: ready" or "curl: NOT FOUND", x + width - ui.font:getWidth("curl: NOT FOUND"), y + 1,
        w.curl and "dim" or "err")
    local yy = y + 22
    -- provider presets
    ui.text("provider", x, yy, "dim")
    local bw = (width - 3 * 6) / 4
    for i, name in ipairs(PROVIDER_ROW) do
        if ui.button("em_prov_" .. name, name:upper(), x + (i - 1) * (bw + 6), yy + 14, bw, 24, { bold = false }) then
            local p = email.PRESETS[name]
            w.cfg.host, w.cfg.port, w.cfg.secure = p.host, p.port, p.secure
            ui.print("{dim}" .. p.note)
            ui.sound("tick", { pitch = 1.1 })
        end
    end
    yy = yy + 46

    local half = (width - 10) / 2
    w.cfg.host = ui.textfield("em_host", w.cfg.host or "", x, yy, half + 30, 40, { label = "smtp host", placeholder = "smtp.gmail.com" })
    w.cfg.port = ui.textfield("em_port", w.cfg.port or "", x + half + 40, yy, half - 30, 40, { label = "port", placeholder = "465" })
    yy = yy + 48
    w.cfg.from = ui.textfield("em_from", w.cfg.from or "", x, yy, width, 40, { label = "your email address (the From)", placeholder = "you@example.com" })
    yy = yy + 48
    w.cfg.user = ui.textfield("em_user", w.cfg.user or "", x, yy, half, 40, { label = "login username", placeholder = "usually your address" })
    w.cfg.name = ui.textfield("em_name", w.cfg.name or "", x + half + 10, yy, half, 40, { label = "display name (optional)", placeholder = "Your Name" })
    yy = yy + 48
    w.cfg.pass = ui.textfield("em_pass", w.cfg.pass or "", x, yy, width, 40, { label = "password / app password", mask = not w.show_pass })
    if ui.button("em_showpass", w.show_pass and "HIDE" or "SHOW", x + width - 56, yy, 56, 18, { bold = false }) then
        w.show_pass = not w.show_pass
    end
    yy = yy + 54

    ui.text("Gmail / Yahoo / iCloud need an app password + 2-step verification, not your normal password.", x, yy, "dim")
    yy = yy + 20
    if ui.button("em_save", "SAVE ACCOUNT", x, yy, 150, 28, { tip = "store these settings" }) then
        w.cfg.port = (w.cfg.port ~= "" and w.cfg.port) or "465"
        if w.cfg.user == "" then w.cfg.user = w.cfg.from end
        w.cfg.secure = w.cfg.secure or (w.cfg.port == "587" and "starttls" or "ssl")
        if email.configured(w.cfg) then
            email.save(w.cfg)
            w.mode = "compose"
            w.result = { ok = true, text = "account saved", at = ui.time() }
            ui.sound("ok", { volume = 0.5 }); ui.unfocus()
        else
            w.result = { ok = false, text = "fill in host, address and password first", at = ui.time() }
            ui.sound("err", { volume = 0.5 })
        end
    end
    if email.configured(email.load()) then
        if ui.button("em_cancel", "CANCEL", x + 160, yy, 90, 28, { bold = false }) then
            w.cfg = email.load(); w.mode = "compose"; ui.unfocus(); ui.sound("back")
        end
    end
end

-- compose form ---------------------------------------------------------------

local function draw_compose(w, ui, x, y, width, height)
    -- account bar
    ui.text("FROM", x, y + 2, "dim")
    ui.text((w.cfg.name and w.cfg.name ~= "" and (w.cfg.name .. "  ") or "") .. (w.cfg.from or ""), x + 40, y + 2, "white")
    if ui.button("em_edit", "ACCOUNT", x + width - 86, y, 86, 20, { bold = false, tip = "change account settings" }) then
        w.mode = "setup"; ui.unfocus(); ui.sound("tick")
    end
    local yy = y + 28

    -- recipients
    local rcpts = email.parse_recipients(w.to)
    w.to = ui.textfield("em_to", w.to, x, yy, width, 40, { label = "to  (separate several with commas)", placeholder = "alice@x.com, bob@y.com" })
    -- recipient count + visibility toggle when more than one
    if #rcpts >= 1 then
        ui.text(#rcpts .. " recipient" .. (#rcpts == 1 and "" or "s"), x + width - 150, yy, "dim")
    end
    yy = yy + 46
    if #rcpts > 1 then
        ui.text("visibility", x, yy + 3, "dim")
        if ui.button("em_vis_bcc", "HIDDEN (BCC)", x + 70, yy, 120, 22, { active = not w.visible, bold = false, tip = "recipients can't see each other" }) then w.visible = false end
        if ui.button("em_vis_to", "VISIBLE (TO)", x + 196, yy, 120, 22, { active = w.visible, bold = false, tip = "everyone sees the list" }) then w.visible = true end
        yy = yy + 28
    end

    -- subject
    w.subject = ui.textfield("em_subj", w.subject, x, yy, width, 40, { label = "subject", placeholder = "subject line" })
    yy = yy + 46

    -- attachments strip (chips) grows as files are added
    w.attach = w.attach or {}
    local attach_h = (#w.attach > 0) and 26 or 0

    -- body fills the rest, above the attachments + action row
    local action_h = 34
    local body_h = y + height - yy - action_h - attach_h - 6
    if body_h > 40 then
        w.body = ui.textfield("em_body", w.body, x, yy, width, body_h, { label = "message", placeholder = "type your message…", multiline = true })
        yy = yy + body_h + 6
    end

    -- attachment chips
    if #w.attach > 0 then
        local cx = x
        local total = 0
        for i = #w.attach, 1, -1 do
            local a = w.attach[i]
            total = total + (a.size or 0)
            local label = "▪ " .. a.name .. "  " .. require("src.vault").size_str(a.size or 0)
            local tw = ui.font:getWidth(label) + 24
            ui.set_color("info", ui.hover(cx, yy, tw, 20) and 0.22 or 0.14)
            love.graphics.rectangle("fill", cx, yy, tw, 20, 9, 9)
            ui.set_color("info", 0.8); love.graphics.setLineWidth(1); love.graphics.rectangle("line", cx + 0.5, yy + 0.5, tw - 1, 19, 9, 9)
            ui.text(label, cx + 8, yy + 2, "info")
            local rx = cx + tw - 15
            ui.text("×", rx + 2, yy + 2, ui.hover(rx, yy, 15, 20) and "err" or "dim")
            if ui.clicked(rx, yy, 15, 20) then table.remove(w.attach, i); ui.sound("back") end
            cx = cx + tw + 6
        end
    end

    -- action row
    local ay = y + height - 26
    local ready = email.configured(w.cfg) and #rcpts > 0 and w.curl and not w.sending
    if ui.button("em_send", w.sending and "SENDING…" or ("SEND" .. (#rcpts > 1 and (" ×" .. #rcpts) or "")), x, ay, 118, 26,
        { tip = ready and "send the message" or "fill in recipient(s) first" }) then
        if ready then
            w.sending = true
            w.pending = { to = rcpts, subject = w.subject, body = w.body, visible = w.visible, attachments = w.attach }
            w.send_at = ui.time() + 0.25
            w.result = nil
            ui.sound("beep", { pitch = 1.1 }); ui.fx.sparks(x + 59, ay + 13, 10, "accent", 70)
        else
            ui.sound("err", { volume = 0.5 })
            if not w.curl then w.result = { ok = false, text = "curl not found — can't send", at = ui.time() } end
        end
    end
    if ui.button("em_attach", "+ ATTACH", x + 126, ay, 92, 26, { bold = false, tip = "attach a file from the vault (or drag one onto the window)" }) then
        w.picker = { scroll = 0 }
        ui.sound("beep", { pitch = 1.1 })
    end
    if ui.button("em_clear", "CLEAR", x + 226, ay, 72, 26, { bold = false }) then
        w.to, w.subject, w.body, w.attach = "", "", "", {}; w.result = nil; ui.unfocus(); ui.sound("back")
    end

    -- status line
    if w.result then
        local age = ui.time() - w.result.at
        local a = w.result.hint and 1 or util.clamp(1 - (age - 6) / 2, 0, 1)   -- errors with hints stay
        if a > 0 then
            local col = w.result.ok and "accent" or "err"
            ui.text((w.result.ok and "✓ " or "✗ ") .. w.result.text, x + 306, ay + 5, col, ui.font, a)
        end
        if w.result.hint then ui.text(w.result.hint, x, ay - (#w.attach > 0 and 46 or 20), "warn", ui.font) end
    end

    if w.picker then draw_picker(w, ui, x, y, width, height) end
end

-- read a file into an attachment; returns true or false+reason
add_attachment = function(w, ui, name, data)
    if #data > email.MAX_ATTACH_BYTES then return false, "that file is too large" end
    for _, a in ipairs(w.attach) do if a.name == name and a.size == #data then return false, "already attached" end end
    w.attach[#w.attach + 1] = { name = name, data = data, size = #data }
    ui.sound("place", { volume = 0.5 }); ui.fx.flash("accent", 0.1)
    return true
end

-- modal: pick a file from the vault to attach
local function gather_vault(dir, out, depth)
    local vault = require("src.vault")
    for _, it in ipairs(vault.list(dir)) do
        if it.kind == "folder" then if depth < 4 then gather_vault(it.path, out, depth + 1) end
        else out[#out + 1] = it end
    end
end

draw_picker = function(w, ui, x, y, width, height)
    local vault = require("src.vault")
    ui.set_color("bg", 0.82); love.graphics.rectangle("fill", x - 12, y - 30, width + 24, height + 44)
    local pw, phh = math.min(width - 20, 440), math.min(height - 20, 380)
    local px, py = x + (width - pw) / 2, y + (height - phh) / 2
    ui.set_color("bg2", 0.98); love.graphics.rectangle("fill", px, py, pw, phh, 5, 5)
    ui.set_color("accent", 0.8); love.graphics.setLineWidth(1); love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, phh - 1, 5, 5)
    ui.text("ATTACH A FILE FROM THE VAULT", px + 12, py + 10, "white", ui.font_bold)
    if ui.button("em_pick_close", "✕", px + pw - 32, py + 8, 24, 20) then w.picker = nil; return end
    ui.text("or drag a file onto the window", px + 12, py + 28, "dim")

    local all = {}; gather_vault(vault.ROOT, all, 1)
    local lx, ly, lw, lh = px + 12, py + 48, pw - 24, phh - 58
    local rh = 22
    local visible = math.floor(lh / rh)
    w.picker.scroll = util.clamp(w.picker.scroll, 0, math.max(0, #all - visible))
    if #all == 0 then ui.text("the vault is empty — add files in the FILES tab first", lx, ly + 4, "dim") end
    local first = math.floor(w.picker.scroll) + 1
    for i = first, math.min(#all, first + visible - 1) do
        local it = all[i]
        local ry = ly + (i - first) * rh
        local hov = ui.hover(lx, ry, lw, rh)
        ui.set_color("accent", hov and 0.1 or 0.03); love.graphics.rectangle("fill", lx, ry + 1, lw, rh - 2, 2, 2)
        local icon = it.kind == "image" and "■" or (it.kind == "text" and "≡" or "□")
        ui.text(icon, lx + 6, ry + 3, it.kind == "image" and "info" or "dim")
        ui.text((vault.pretty(it.path):gsub("^vault / ", "")), lx + 22, ry + 3, "text")
        local sz = vault.size_str(it.size)
        ui.text(sz, lx + lw - ui.font:getWidth(sz) - 2, ry + 3, "dim")
        if ui.clicked(lx, ry, lw, rh) then
            local data = vault.read(it.path)
            local ok, why = add_attachment(w, ui, vault.basename(it.path), data)
            if ok then ui.print("{info}▪{} attached {white}" .. vault.basename(it.path):gsub("{", "{{")); w.picker = nil
            else ui.sound("err"); w.result = { ok = false, text = why, at = ui.time() } end
        end
    end
    if ui.press and not ui.press.used and not ui.hover(px, py, pw, phh) then w.picker = nil end
end

function W.draw(w, ui, x, y, width, height)
    -- keep the live config in sync if it was changed from the terminal
    if w.mode == "compose" and not email.configured(w.cfg) then w.cfg = email.load() end
    if w.mode == "setup" then
        draw_setup(w, ui, x, y, width, height)
    else
        draw_compose(w, ui, x, y, width, height)
    end
end

-- dropping a file onto the window attaches it (when the MAIL tab is open)
function W.filedropped(w, ui, file)
    if ui.active_tab ~= W.tab or w.mode ~= "compose" then return false end
    local name = file:getFilename():match("([^/\\]+)$") or "file"
    file:open("r"); local data = file:read(); file:close()
    local ok, why = add_attachment(w, ui, name, data)
    if ok then ui.print("{info}\226\150\170{} attached {white}" .. name:gsub("{", "{{"))
    else ui.sound("err"); w.result = { ok = false, text = name .. ": " .. why, at = ui.time() } end
    return true
end

function W.wheelmoved(w, ui, dx, dy)
    if w.picker then w.picker.scroll = math.max(0, w.picker.scroll - dy * 2) end
end

return W
