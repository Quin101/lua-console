-- Send real email through your own SMTP account.
--   email setup           configure your server + login (one time)
--   email send <address>  compose and send a message
--   email test            send yourself a test message
--   email config          show the current settings (password hidden)
local email = require("src.email")

local function esc(s) return (tostring(s or ""):gsub("{", "{{")) end

local function do_setup(t)
    t.print("")
    t.print("{accent}email setup{}  {dim}· your details are stored locally in the save folder")
    t.print("{dim}provider? type one of: {}gmail  outlook  yahoo  icloud  {dim}(or {}custom{dim})")
    local choice = t.ask("provider: "):lower():gsub("%s", "")
    local c = email.load()
    local preset = email.PRESETS[choice]
    if preset then
        c.host, c.port, c.secure = preset.host, preset.port, preset.secure
        t.print("{dim}" .. preset.note)
    elseif choice ~= "custom" and choice ~= "" then
        t.print("{dim}unknown provider — entering custom settings")
        preset = nil
    end
    if not preset then
        c.host = t.ask("smtp host (e.g. smtp.example.com): ")
        c.port = t.ask("port [465 ssl / 587 starttls]: ")
        if c.port == "" then c.port = "465" end
        c.secure = c.port == "587" and "starttls" or "ssl"
    end
    c.from = t.ask("your email address (the From): ")
    if c.from == "" then return t.print("{err}✗{} cancelled — no address given") end
    c.user = t.ask("login username [" .. esc(c.from) .. "]: ")
    if c.user == "" then c.user = c.from end
    c.pass = t.ask("password / app password: ", { mask = true }):gsub("^%s+", ""):gsub("%s+$", "")
    if c.pass == "" then return t.print("{err}✗{} cancelled — no password given") end
    c.name = t.ask("display name (optional): ")
    email.save(c)
    t.print("")
    t.print("{accent}✓{} saved.  host {white}" .. esc(c.host) .. ":" .. esc(c.port) ..
        "{}  from {white}" .. esc(c.from))
    t.print("{dim}the password is stored in email.cfg in the save folder — keep an app password here, not your main one")
    t.print("{dim}send a test with  {accent}email test")
    t.sound("ok", { volume = 0.5 })
end

local function compose_and_send(t, to)
    local c = email.load()
    if not email.configured(c) then
        t.print("{warn}▲ not set up yet.{} run {accent}email setup{} first")
        return
    end
    if not to or to == "" then to = t.ask("to (comma-separate several): ") end
    local rcpts = email.parse_recipients(to)
    if #rcpts == 0 then return t.print("{err}✗{} need at least one valid recipient address") end
    if #rcpts > email.MAX_RECIPIENTS then
        return t.print("{err}✗{} that's " .. #rcpts .. " recipients — keep it to " .. email.MAX_RECIPIENTS .. " or fewer per message")
    end

    local visible = false
    if #rcpts > 1 then
        t.print("{dim}" .. #rcpts .. " recipients. show everyone's address to each other (To), or hide them (Bcc)?")
        local mode = t.ask("{dim}visibility [{}hidden{dim}/{}visible{dim}]: "):lower()
        visible = mode:sub(1, 1) == "v"
    end

    local subject = t.ask("subject: ")
    t.print("{dim}message — type your lines, then a single {white}.{dim} on its own line to finish:")
    local lines = {}
    while true do
        local line = t.ask("{dim}┃ {}")
        if line == "." then break end
        lines[#lines + 1] = line
        if #lines > 500 then break end
    end
    local body = table.concat(lines, "\n")
    t.print("")
    local to_show = #rcpts <= 4 and table.concat(rcpts, ", ")
        or (table.concat({ rcpts[1], rcpts[2], rcpts[3] }, ", ") .. " +" .. (#rcpts - 3) .. " more")
    t.print("{dim}from {}" .. esc(c.from))
    t.print("{dim}to   {}" .. esc(to_show) .. "  {dim}(" .. #rcpts .. ", " .. (visible and "visible" or "hidden/bcc") .. ")")
    t.print("{dim}subj {}" .. esc(subject))
    local yes = t.ask("send to " .. #rcpts .. " recipient" .. (#rcpts == 1 and "" or "s") .. "? [y/N] "):lower()
    if yes ~= "y" and yes ~= "yes" then
        t.print("{dim}cancelled")
        t.sound("back")
        return
    end

    t.spin("connecting to " .. esc(c.host), 0.6)
    t.print("{dim}handing off to " .. esc(c.host) .. "…")
    local ok, detail, hint = email.send(c, rcpts, subject, body, { visible = visible })
    if ok then
        t.flash("accent", 0.15)
        t.print("{accent}✓ sent{}  {dim}" .. esc(detail))
        t.sound("ok")
        t.sparks(24)
    else
        t.print("{err}✗ not sent{}  {dim}" .. esc(detail))
        if hint then t.print("{warn}▲ {}" .. esc(hint)) end
        t.sound("err")
        t.glitch(0.25, 0.4)
    end
end

return {
    {
        name = "email",
        aliases = { "mail", "sendmail" },
        help = "send real email via your own SMTP account",
        usage = "email <setup|send|test|config> [address,address,…]",
        category = "tools",
        run = function(t, args, rest)
            local sub = (args[1] or ""):lower()
            if sub == "setup" then
                do_setup(t)
            elseif sub == "send" then
                compose_and_send(t, args[2])
            elseif sub == "test" then
                local c = email.load()
                if not email.configured(c) then return t.print("{warn}▲{} run {accent}email setup{} first") end
                t.print("{dim}sending a test message to yourself (" .. esc(c.from) .. ")…")
                local ok, detail, hint = email.send(c, c.from, "Qrawller test ✓",
                    "This is a test message from the Qrawller Terminal.\nIf you can read this, sending works.")
                if ok then t.print("{accent}✓ sent{}  {dim}" .. esc(detail)); t.sound("ok"); t.sparks(20)
                else
                    t.print("{err}✗ failed{}  {dim}" .. esc(detail))
                    if hint then t.print("{warn}▲ {}" .. esc(hint)) end
                    t.sound("err"); t.glitch(0.25, 0.4)
                end
            elseif sub == "config" then
                local c = email.load()
                if not email.configured(c) then return t.print("{dim}not configured — run {accent}email setup") end
                t.print("{dim}host    {}" .. esc(c.host) .. ":" .. esc(c.port or "465") .. "  {dim}(" .. esc(c.secure or "ssl") .. ")")
                t.print("{dim}from    {}" .. esc(c.from))
                t.print("{dim}login   {}" .. esc(c.user))
                t.print("{dim}password{}  {dim}•••••••• (hidden)")
                t.print("{dim}curl    {}" .. (email.curl_ok() and "{accent}available" or "{err}not found"))
                t.print("{dim}" .. esc(email.preview(c)))
            elseif sub == "" then
                t.print("{dim}real email sender — send through your own SMTP account")
                t.print("")
                t.print("  {accent}email setup{}           {dim}configure your server + login (once)")
                t.print("  {accent}email send <a@x,b@y>{}   {dim}compose & send (comma-separate recipients)")
                t.print("  {accent}email test{}            {dim}send yourself a test")
                t.print("  {accent}email config{}          {dim}show settings (password hidden)")
                t.print("")
                t.print("{dim}uses {}curl{dim} + SMTP.  for Gmail/Yahoo/iCloud use an app password.")
                t.print("{dim}curl on this machine: " .. (email.curl_ok() and "{accent}available" or "{err}not found"))
            else
                t.print("{err}✗{} unknown option {white}" .. esc(sub) .. "{}  ·  try {accent}email")
            end
        end,
    },
}
