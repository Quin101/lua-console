-- Fake "hacker" sequences. Nothing here touches the network — it's all theatre.
local SERVICES = {
    { 21, "ftp" }, { 22, "ssh" }, { 25, "smtp" }, { 53, "dns" }, { 80, "http" }, { 110, "pop3" },
    { 143, "imap" }, { 443, "https" }, { 3306, "mysql" }, { 5432, "postgres" }, { 6379, "redis" },
    { 8080, "http-alt" }, { 27017, "mongodb" },
}

local PATHS = {
    "about", "login", "api", "assets", "blog", "cdn", "admin", "dashboard", "docs", "static",
    "uploads", "users", "search", "status", "graphql", "auth", "billing", "support", "careers",
    "legal", "sitemap.xml", "robots.txt", ".well-known",
}
local SUBPATHS = {
    "v1", "v2", "index.html", "config.json", "images", "js", "css", "export", "settings",
    "users/1337", "keys", "logs", "backup.zip", "private", "internal", "tokens", "health",
    "debug", "archive", "drafts", ".env", "session", "upload", "feed.xml",
}

local function hexdump(t, rows)
    for _ = 1, rows do
        local addr = "0x" .. t.hex(8)
        local bytes = {}
        for i = 1, 8 do bytes[i] = t.hex(2) end
        local ascii = {}
        for i = 1, 8 do ascii[i] = string.char(t.random(33, 126)) end
        t.raw(addr .. "  " .. table.concat(bytes, " ") .. "   " .. table.concat(ascii), "dim")
        t.wait(0.025)
    end
end

return {
    {
        name = "hack",
        help = "breach a target (it's fake, relax)",
        usage = "hack <target>",
        category = "hack",
        run = function(t, args)
            local target = args[1] or "mainframe.corp"
            local ip = t.ip()
            t.print("")
            t.spin("resolving {white}" .. target, 0.6, ip)
            t.spin("fingerprinting host", 0.5, "linux 6.x · nginx")
            t.print("{dim}scanning ports")
            local open = {}
            for _, s in ipairs(SERVICES) do
                if t.random() < 0.35 then
                    open[#open + 1] = s
                    t.print("  {accent}" .. t.pad(s[1] .. "/tcp", 10) .. "{}" .. t.pad(s[2], 10) .. "{ok}open")
                    t.sound("beep", { pitch = 1.5, volume = 0.3 })
                    t.wait(0.06)
                end
            end
            if #open == 0 then open[1] = { 22, "ssh" } end
            local entry = t.pick(open)
            t.print("")
            t.type("{dim}exploiting{} " .. entry[2] .. " {dim}on port{} " .. entry[1], "text", 120)
            t.progress("injecting payload", 1.4)
            hexdump(t, 6)
            t.progress("escalating privileges", 1.0)
            t.print("")
            t.print("{dim}cracking root hash")
            t.decode("root:" .. t.hex(4) .. "$" .. t.hex(24), "warn", 1.4)
            t.print("")
            t.glitch(0.5)
            t.shake(10)
            t.flash("accent", 0.3)
            t.banner("ACCESS")
            t.banner("GRANTED")
            t.sound("ok")
            t.sparks(60)
            t.print("")
            t.print("{dim}session opened on {}" .. target .. " {dim}as{} {accent}root{}   {dim}(not really)")
            t.print("")
        end,
    },
    {
        name = "crawl",
        help = "send the qrawler spider through a website (simulated)",
        usage = "crawl <url>",
        category = "hack",
        run = function(t, args)
            local site = (args[1] or "example.com"):gsub("^https?://", ""):gsub("/$", "")
            local depth_max = 3
            local found, bytes = 0, 0
            t.print("")
            t.print("{accent}◆{} qrawler  {dim}→{}  " .. site .. "   {dim}depth " .. depth_max)
            t.print("")
            local function walk(prefix, path, depth)
                local n = depth == 1 and t.random(4, 6) or t.random(0, 3)
                local used = {}
                local kids = {}
                for _ = 1, n do
                    local p = t.pick(depth == 1 and PATHS or SUBPATHS)
                    if not used[p] then
                        used[p] = true
                        kids[#kids + 1] = p
                    end
                end
                for i, p in ipairs(kids) do
                    local last = i == #kids
                    local code = t.random() < 0.88 and 200 or t.pick({ 301, 403, 404, 500 })
                    local color = code == 200 and "ok" or (code < 400 and "info" or "err")
                    local size = t.random(2, 180)
                    found, bytes = found + 1, bytes + size
                    t.print("{dim}" .. prefix .. (last and "└── " or "├── ") .. "{}" .. path .. "/" .. p ..
                        "  {" .. color .. "}" .. code .. "{}  {dim}" .. size .. "kb")
                    t.sound("tick", { pitch = 1 + depth * 0.25, volume = 0.4 })
                    t.wait(0.04 + t.random() * 0.06)
                    if depth < depth_max and code == 200 and not p:find("%.") then
                        walk(prefix .. (last and "    " or "│   "), path .. "/" .. p, depth + 1)
                    end
                end
            end
            t.print(site, "white")
            walk("", "", 1)
            t.print("")
            t.print(("{accent}✓{} crawled {white}%d{} pages  ·  {white}%.1f{} MB indexed  ·  %d ms"):format(
                found, bytes / 1024, t.random(800, 4000)))
            t.sound("ok", { volume = 0.6 })
            t.print("")
        end,
    },
    {
        name = "scan",
        help = "sweep the local network (simulated)",
        category = "hack",
        run = function(t)
            local names = { "router", "nas-01", "printer", "tv-livingroom", "phone", "laptop", "unknown", "cam-garage", "xbox", "raspberrypi" }
            local base = "192.168." .. t.random(0, 2) .. "."
            t.print("")
            t.spin("probing " .. base .. "0/24", 0.8)
            t.print("")
            t.print("{dim}" .. t.pad("ADDRESS", 18) .. t.pad("HOST", 18) .. t.pad("MAC", 20) .. "LATENCY")
            local used = {}
            for _ = 1, t.random(5, 8) do
                local last = t.random(2, 250)
                if not used[last] then
                    used[last] = true
                    local mac = {}
                    for i = 1, 6 do mac[i] = t.hex(2) end
                    local name = t.pick(names)
                    t.print(t.pad(base .. last, 18) .. "{" .. (name == "unknown" and "warn" or "white") .. "}" ..
                        t.pad(name, 18) .. "{dim}" .. t.pad(table.concat(mac, ":"), 20) .. "{accent}" .. t.random(1, 40) .. "ms")
                    t.sound("beep", { pitch = 1.3 + t.random() * 0.5, volume = 0.3 })
                    t.wait(0.12)
                end
            end
            t.print("")
        end,
    },
    {
        name = "trace",
        help = "trace a route across the planet (simulated)",
        usage = "trace <host>",
        category = "hack",
        run = function(t, args)
            local host = args[1] or "target.onion"
            local cities = { "frankfurt", "amsterdam", "london", "reykjavik", "new york", "toronto", "tokyo", "singapore", "são paulo", "zürich", "oslo", "seoul" }
            t.print("")
            t.print("{dim}tracing route to{} " .. host)
            local ms = 0
            local hops = t.random(6, 10)
            for i = 1, hops do
                ms = ms + t.random(2, 30)
                local bar = string.rep("▪", math.min(30, math.floor(ms / 8)))
                t.print("{dim}" .. t.lpad(tostring(i), 2) .. "{}  " .. t.pad(t.ip(), 16) .. "{white}" ..
                    t.pad(t.pick(cities), 12) .. "{dim}" .. t.lpad(ms .. "ms", 7) .. "  {accent}" .. bar)
                t.sound("tick", { pitch = 0.8 + i * 0.1 })
                t.wait(0.18)
            end
            t.print("")
            t.decode(("target located  ·  %.4f, %.4f"):format(t.random() * 180 - 90, t.random() * 360 - 180), "accent", 1.0)
            t.sound("ok", { volume = 0.5 })
            t.print("")
        end,
    },
    {
        name = "decrypt",
        help = "decode a message with style",
        usage = "decrypt [text]",
        category = "hack",
        run = function(t, args, rest)
            local messages = {
                "the package arrives at midnight. trust no one.",
                "meet at the old server room. bring coffee.",
                "the password was 'password'. it always is.",
                "they know about the crawler. move to node 7.",
                "if you can read this, the cipher is broken.",
            }
            local msg = rest ~= "" and rest or t.pick(messages)
            t.print("")
            t.print("{dim}ciphertext")
            t.raw(t.hex(math.min(t.width() - 4, #msg * 2)), "faint")
            t.progress("brute forcing key", 1.2)
            t.print("")
            t.decode(msg, "white", 1.6)
            t.sound("ok", { volume = 0.5 })
            t.print("")
        end,
    },
    {
        name = "breach",
        help = "a password prompt that fights back",
        category = "hack",
        run = function(t)
            t.print("")
            t.print("{warn}▲{} restricted node  {dim}·  3 attempts")
            for attempt = 1, 3 do
                local pw = t.ask("password: ", { mask = true })
                t.spin("verifying", 0.6)
                if pw == "qrawller" then
                    t.flash("accent", 0.3)
                    t.banner("WELCOME")
                    t.sound("ok")
                    return
                end
                t.glitch(0.3)
                t.shake(8)
                t.sound("err")
                t.print("{err}✗ denied{}  {dim}" .. (3 - attempt) .. " left")
            end
            t.print("")
            t.decode("lockdown engaged. (hint: the password is the name of this terminal)", "err", 1.2)
            t.print("")
        end,
    },
}
