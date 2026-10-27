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

-- attachment content types by extension
local MIME = {
    png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif",
    bmp = "image/bmp", webp = "image/webp", svg = "image/svg+xml",
    pdf = "application/pdf", zip = "application/zip",
    txt = "text/plain", md = "text/markdown", csv = "text/csv", log = "text/plain",
    json = "application/json", xml = "application/xml", html = "text/html",
    doc = "application/msword", docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    xls = "application/vnd.ms-excel", xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    mp3 = "audio/mpeg", wav = "audio/wav", mp4 = "video/mp4", lua = "text/plain",
}
function email.mime_type(name)
    return MIME[(tostring(name):match("%.([%w]+)$") or ""):lower()] or "application/octet-stream"
end

-- base64-encode raw bytes and wrap at 76 columns with CRLF (RFC 2045)
local function b64(data)
    local enc = love.data.encode("string", "base64", data, 0)   -- no line breaks, we add our own
    local out = {}
    for i = 1, #enc, 76 do out[#out + 1] = enc:sub(i, i + 75) end
    return table.concat(out, "\r\n")
end

email.MAX_ATTACH_BYTES = 22 * 1024 * 1024   -- ~22 MB (most providers cap around 25)

-- builds the full message. `attachments` is a list of { name = ..., data = ... }.
local function build_message(c, to, subject, body, attachments)
    local from = (c.name and c.name ~= "") and (c.name .. " <" .. c.from .. ">") or c.from
    local date = os.date("!%a, %d %b %Y %H:%M:%S +0000")
    local id = ("<%s.%s@qrawller>"):format(os.time(), tostring(math.random(100000, 999999)))
    local base = {
        "From: " .. from,
        "To: " .. to,
        "Subject: " .. subject,
        "Date: " .. date,
        "Message-ID: " .. id,
        "MIME-Version: 1.0",
    }
    -- SMTP dot-stuffing on the plain-text body
    body = tostring(body):gsub("\r\n", "\n"):gsub("\n", "\r\n"):gsub("\r\n%.", "\r\n..")

    if not attachments or #attachments == 0 then
        base[#base + 1] = 'Content-Type: text/plain; charset="UTF-8"'
        base[#base + 1] = "Content-Transfer-Encoding: 8bit"
        base[#base + 1] = "X-Mailer: Qrawller Terminal"
        return table.concat(base, "\r\n") .. "\r\n\r\n" .. body .. "\r\n"
    end

    local boundary = "qrawller_" .. os.time() .. "_" .. math.random(100000, 999999)
    base[#base + 1] = 'Content-Type: multipart/mixed; boundary="' .. boundary .. '"'
    base[#base + 1] = "X-Mailer: Qrawller Terminal"
    local parts = { table.concat(base, "\r\n") .. "\r\n" }
    -- text part
    parts[#parts + 1] = "--" .. boundary .. "\r\n" ..
        'Content-Type: text/plain; charset="UTF-8"\r\n' ..
        "Content-Transfer-Encoding: 8bit\r\n\r\n" .. body .. "\r\n"
    -- attachment parts
    for _, a in ipairs(attachments) do
        local name = (a.name:gsub('[\r\n"]', ""))
        parts[#parts + 1] = "--" .. boundary .. "\r\n" ..
            "Content-Type: " .. email.mime_type(name) .. '; name="' .. name .. '"\r\n' ..
            "Content-Transfer-Encoding: base64\r\n" ..
            'Content-Disposition: attachment; filename="' .. name .. '"\r\n\r\n' ..
            b64(a.data) .. "\r\n"
    end
    parts[#parts + 1] = "--" .. boundary .. "--\r\n"
    return table.concat(parts)
end

-- splits "a@x.com, b@y.com; c@z.com" into a clean, de-duplicated list of addresses
email.MAX_RECIPIENTS = 100
function email.parse_recipients(s)
    local list, seen = {}, {}
    for part in tostring(s or ""):gmatch("[^,;%s]+") do
        local addr = part:gsub("^<", ""):gsub(">$", "")
        if addr:find("@") and not seen[addr:lower()] then
            seen[addr:lower()] = true
            list[#list + 1] = addr
        end
    end
    return list
end

-- sends one message to one or more recipients.
--   to       a comma/space separated string, or a list of addresses
--   opts.visible   true = everyone in the To header; false/nil = Bcc (hidden)
-- returns ok(boolean), detail(string), hint(string|nil), count(number)
function email.send(c, to, subject, body, opts)
    c = c or email.load()
    opts = opts or {}
    if not email.configured(c) then return false, "not configured — run `email setup` first" end
    if not email.curl_ok() then return false, "curl was not found on this system (needed to send mail)" end

    local rcpts = type(to) == "table" and to or email.parse_recipients(to)
    if #rcpts == 0 then return false, "no valid recipient address" end
    if #rcpts > email.MAX_RECIPIENTS then
        return false, ("too many recipients (%d) — keep it to %d or fewer per message"):format(#rcpts, email.MAX_RECIPIENTS)
    end

    -- the visible To: header (everyone when visible, otherwise hide the list)
    local to_header = (opts.visible or #rcpts == 1) and table.concat(rcpts, ", ") or "undisclosed-recipients:;"

    -- read any attachments (each is { name, path = vault path } or { name, data })
    local attachments = {}
    local total = 0
    for _, a in ipairs(opts.attachments or {}) do
        local data = a.data
        if not data and a.path then data = love.filesystem.read(a.path) end
        if not data then return false, "could not read attachment: " .. tostring(a.name) end
        total = total + #data
        attachments[#attachments + 1] = { name = a.name or "file", data = data }
    end
    if total > email.MAX_ATTACH_BYTES then
        return false, ("attachments too large (%.1f MB) — keep the total under %d MB")
            :format(total / 1024 / 1024, math.floor(email.MAX_ATTACH_BYTES / 1024 / 1024))
    end

    local port = c.port or "465"
    local secure = c.secure or (port == "587" and "starttls" or "ssl")
    local scheme = (secure == "ssl") and "smtps" or "smtp"
    local url = ("%s://%s:%s"):format(scheme, c.host, port)

    local msg_name = "email_msg.txt"
    local cfg_name = "email_curl.cfg"
    love.filesystem.write(msg_name, build_message(c, to_header, subject, body, attachments))

    -- put the url, credentials and options in a curl config file so the
    -- password never appears in the process list / command line
    -- (escape backslashes first, then quotes — curl unescapes both inside quotes)
    local function esc(v) return '"' .. tostring(v):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
    local cfg = {
        "url = " .. esc(url),
        "user = " .. esc(c.user .. ":" .. c.pass),
        "mail-from = " .. esc(c.from),
    }
    for _, r in ipairs(rcpts) do cfg[#cfg + 1] = "mail-rcpt = " .. esc(r) end
    for _, line in ipairs({
        "upload-file = " .. esc(real(msg_name)),
        "ssl-reqd", "silent", "show-error",
    }) do cfg[#cfg + 1] = line end
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
    if ok then
        local n = #rcpts
        return true, ("delivered to your SMTP server for %d recipient%s"):format(n, n == 1 and "" or "s"), nil, n
    end
    if out == "" then out = "curl failed (no output) — check host, port and network" end
    return false, out, email.hint(out), #rcpts
end

-- turn a raw curl/SMTP error into a plain-English next step
function email.hint(out)
    local o = out:lower()
    if o:find("%(67%)") or o:find("login denied") or o:find("535") or o:find("not accepted")
        or o:find("authentication") or o:find("5%.7%.8") then
        return "login was rejected. For Gmail / Yahoo / iCloud you must use an APP PASSWORD "
            .. "(not your normal password), with 2-step verification turned on. "
            .. "Use your full email address as the username, and remove any spaces from the app password. "
            .. "Re-run `email setup` to re-enter it."
    end
    if o:find("could not resolve") or o:find("resolve host") then
        return "the SMTP host name could not be found — check it for typos (e.g. smtp.gmail.com)."
    end
    if o:find("couldn't connect") or o:find("connection refused") or o:find("timed out") or o:find("timeout") then
        return "couldn't reach the server — check the port (465 for SSL, 587 for STARTTLS) and that a firewall isn't blocking it."
    end
    if o:find("certificate") or o:find("ssl") or o:find("tls") then
        return "a secure-connection problem — try the other port/mode (465 ssl vs 587 starttls) in `email setup`."
    end
    return nil
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
