-- Real email sending via the system `curl` and your own SMTP account.
-- Nothing is sent anywhere until you configure your own server + credentials
-- (email setup) and compose a message. From is always your configured address.
local email = { CFG = "email.cfg" }

-- config is a few key = value lines in the save folder -----------------------

local FIELDS = { "host", "port", "user", "pass", "from", "name", "secure" }

function email.load()
    local c = {}
    if love.filesystem.getInfo(email.CFG) then
        for line in love.filesystem.lines(email.CFG) do
            local k, v = line:match("^(%w+)=(.*)$")
            if k then c[k] = v end
        end
    end
    return c
end

function email.save(c)
    local out = {}
    for _, k in ipairs(FIELDS) do
        if c[k] and c[k] ~= "" then out[#out + 1] = k .. "=" .. c[k] end
    end
    love.filesystem.write(email.CFG, table.concat(out, "\n"))
end

function email.configured(c)
    c = c or email.load()
    return c.host and c.user and c.pass and c.from and c.host ~= ""
end

-- common providers so the user doesn't have to look up server settings
email.PRESETS = {
    gmail = { host = "smtp.gmail.com", port = "465", secure = "ssl",
        note = "Gmail needs an App Password (Google Account → Security → 2-Step → App passwords), not your normal password." },
    outlook = { host = "smtp.office365.com", port = "587", secure = "starttls",
        note = "Use your Outlook/Microsoft 365 address and password (or app password if 2FA is on)." },
    yahoo = { host = "smtp.mail.yahoo.com", port = "465", secure = "ssl",
        note = "Yahoo needs an App Password (Account Security → Generate app password)." },
    icloud = { host = "smtp.mail.me.com", port = "587", secure = "starttls",
        note = "iCloud needs an app-specific password (appleid.apple.com → Sign-In and Security)." },
}

-- is curl available on this machine?
function email.curl_ok()
    local f = io.popen("curl --version 2>&1")
    if not f then return false end
    local out = f:read("*a") or ""
    f:close()
    return out:match("^curl%s") ~= nil
end

-- real on-disk path for a file we wrote through love.filesystem
local function real(name)
    local base = love.filesystem.getSaveDirectory():gsub("\\", "/")
    return base .. "/" .. name
end

local function rfc822(c, to, subject, body)
    local from = (c.name and c.name ~= "") and (c.name .. " <" .. c.from .. ">") or c.from
    local date = os.date("!%a, %d %b %Y %H:%M:%S +0000")
    local id = ("<%s.%s@qrawller>"):format(os.time(), tostring(math.random(100000, 999999)))
    -- dots at the start of a line must be escaped for SMTP (dot-stuffing)
    body = tostring(body):gsub("\r\n", "\n"):gsub("\n", "\r\n"):gsub("\r\n%.", "\r\n..")
    local headers = {
        "From: " .. from,
        "To: " .. to,
        "Subject: " .. subject,
        "Date: " .. date,
        "Message-ID: " .. id,
        "MIME-Version: 1.0",
        'Content-Type: text/plain; charset="UTF-8"',
        "Content-Transfer-Encoding: 8bit",
        "X-Mailer: Qrawller Terminal",
    }
    return table.concat(headers, "\r\n") .. "\r\n\r\n" .. body .. "\r\n"
end

-- sends one message. returns ok(boolean), detail(string)
function email.send(c, to, subject, body)
    c = c or email.load()
    if not email.configured(c) then return false, "not configured — run `email setup` first" end
    if not to or to == "" or not to:find("@") then return false, "invalid recipient address" end
    if not email.curl_ok() then return false, "curl was not found on this system (needed to send mail)" end

    local port = c.port or "465"
    local secure = c.secure or (port == "587" and "starttls" or "ssl")
    local scheme = (secure == "ssl") and "smtps" or "smtp"
    local url = ("%s://%s:%s"):format(scheme, c.host, port)

    local msg_name = "email_msg.txt"
    local cfg_name = "email_curl.cfg"
    love.filesystem.write(msg_name, rfc822(c, to, subject, body))

    -- put the url, credentials and options in a curl config file so the
    -- password never appears in the process list / command line
    local function esc(v) return '"' .. tostring(v):gsub('"', '\\"') .. '"' end
    local cfg = {
        "url = " .. esc(url),
        "user = " .. esc(c.user .. ":" .. c.pass),
        "mail-from = " .. esc(c.from),
        "mail-rcpt = " .. esc(to),
        "upload-file = " .. esc(real(msg_name)),
        "ssl-reqd",
        "silent",
        "show-error",
    }
    love.filesystem.write(cfg_name, table.concat(cfg, "\n") .. "\n")

    -- `&& echo __QOK__` marks a zero exit code (works in sh and cmd.exe)
    local cmd = ('curl -K "%s" 2>&1 && echo __QOK__'):format(real(cfg_name))
    local f = io.popen(cmd)
    local out = f and f:read("*a") or ""
    if f then f:close() end

    love.filesystem.remove(cfg_name)   -- remove the file holding the password
    love.filesystem.remove(msg_name)

    local ok = out:find("__QOK__", 1, true) ~= nil
    out = (out:gsub("__QOK__%s*$", "")):gsub("%s+$", "")
    if ok then return true, "delivered to your SMTP server" end
    if out == "" then out = "curl failed (no output) — check host, port and network" end
    return false, out
end

-- what the curl command looks like, with the password masked (for `email show`)
function email.preview(c, to)
    c = c or email.load()
    local port = c.port or "465"
    local secure = c.secure or (port == "587" and "starttls" or "ssl")
    local scheme = (secure == "ssl") and "smtps" or "smtp"
    return ("curl --ssl-reqd %s://%s:%s --user %s:•••••• --mail-from %s --mail-rcpt %s --upload-file message.txt")
        :format(scheme, c.host or "?", port, c.user or "?", c.from or "?", to or "<to>")
end

return email
