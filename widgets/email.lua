-- EMAIL: a compose window that sends real mail through your own SMTP account.
-- Same engine as the `email` terminal command (src/email.lua). Nothing is sent
-- until you set up your account and press SEND.
local email = require("src.email")
local util = require("src.util")

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
            w.to, w.subject, w.body = "", "", ""
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

    -- body fills the rest, above the action row
    local action_h = 34
    local body_h = y + height - yy - action_h - 6
    if body_h > 40 then
        w.body = ui.textfield("em_body", w.body, x, yy, width, body_h, { label = "message", placeholder = "type your message…", multiline = true })
    end

    -- action row
    local ay = y + height - 26
    local ready = email.configured(w.cfg) and #rcpts > 0 and w.curl and not w.sending
    if ui.button("em_send", w.sending and "SENDING…" or ("SEND" .. (#rcpts > 1 and (" ×" .. #rcpts) or "")), x, ay, 130, 26,
        { tip = ready and "send the message" or "fill in recipient(s) first" }) then
        if ready then
            w.sending = true
            w.pending = { to = rcpts, subject = w.subject, body = w.body, visible = w.visible }
            w.send_at = ui.time() + 0.25
            w.result = nil
            ui.sound("beep", { pitch = 1.1 }); ui.fx.sparks(x + 65, ay + 13, 10, "accent", 70)
        else
            ui.sound("err", { volume = 0.5 })
            if not w.curl then w.result = { ok = false, text = "curl not found — can't send", at = ui.time() } end
        end
    end
    if ui.button("em_clear", "CLEAR", x + 138, ay, 80, 26, { bold = false }) then
        w.to, w.subject, w.body = "", "", ""; w.result = nil; ui.unfocus(); ui.sound("back")
    end

    -- status line
    if w.result then
        local age = ui.time() - w.result.at
        local a = w.result.hint and 1 or util.clamp(1 - (age - 6) / 2, 0, 1)   -- errors with hints stay
        if a > 0 then
            local col = w.result.ok and "accent" or "err"
            ui.text((w.result.ok and "✓ " or "✗ ") .. w.result.text, x + 226, ay + 5, col, ui.font, a)
        end
    end
    if w.result and w.result.hint then
        ui.text(w.result.hint, x, ay - 20, "warn", ui.font)
    end
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

return W
