-- Real information about the machine, shown with style.
local LOGO = {
    "  ▄▄▄▄▄▄▄  ",
    " █ ▄▄▄▄▄ █ ",
    " █ █   █ █ ",
    " █ █▄▄▄█ █ ",
    " █▄▄▄▄▄▄▄█▄",
    "         ▀▀",
}

local function uptime(s)
    s = math.floor(s)
    return ("%02d:%02d:%02d"):format(math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

return {
    {
        name = "sysinfo",
        aliases = { "neofetch" },
        help = "info about this machine",
        category = "system",
        run = function(t)
            local w, h = love.window.getDesktopDimensions()
            local major, minor, rev = love.getVersion()
            local power, pct = love.system.getPowerInfo()
            local user = os.getenv("USERNAME") or os.getenv("USER") or "operator"
            local info = {
                { "user", user },
                { "os", love.system.getOS() },
                { "cpu", love.system.getProcessorCount() .. " threads" },
                { "display", w .. "×" .. h },
                { "renderer", (select(1, love.graphics.getRendererInfo())) .. " " .. (select(2, love.graphics.getRendererInfo())) },
                { "gpu", (select(4, love.graphics.getRendererInfo())) },
                { "power", power .. (pct and (" " .. pct .. "%") or "") },
                { "engine", "löve " .. major .. "." .. minor .. "." .. rev },
                { "memory", ("%.1f MB (lua)"):format(collectgarbage("count") / 1024) },
                { "uptime", uptime(t.time()) },
                { "fps", tostring(love.timer.getFPS()) },
                { "theme", t.util.theme },
            }
            t.print("")
            for i = 1, math.max(#LOGO, #info) do
                local left = LOGO[i] or string.rep(" ", 11)
                local right = info[i] and ("{accent}" .. t.pad(info[i][1], 10) .. "{}" .. tostring(info[i][2]):gsub("{", "{{")) or ""
                t.print("{accent}" .. left .. "{}   " .. right)
                t.wait(0.03)
            end
            t.print("")
            local swatch = ""
            for _, c in ipairs({ "accent", "text", "white", "dim", "ok", "warn", "err", "info" }) do
                swatch = swatch .. "{" .. c .. "}███"
            end
            t.print(string.rep(" ", 14) .. swatch)
            t.print("")
        end,
    },
    {
        name = "whoami",
        help = "who you are",
        category = "system",
        run = function(t)
            local user = os.getenv("USERNAME") or os.getenv("USER") or "operator"
            t.decode(user .. "  ·  clearance level " .. t.random(3, 9), "accent", 0.7)
        end,
    },
    {
        name = "date",
        aliases = { "time" },
        help = "current date and time",
        category = "system",
        run = function(t)
            t.print(os.date("{white}%H:%M:%S{}  {dim}·{}  %A %d %B %Y"))
        end,
    },
    {
        name = "fps",
        help = "live frame-rate meter — any key to stop",
        category = "system",
        run = function(t)
            local l = t.live(function()
                local fps = love.timer.getFPS()
                local bar = string.rep("▪", math.min(40, math.floor(fps / 4)))
                return "{dim}fps{}  {white}" .. t.lpad(tostring(fps), 4) .. "{}  {accent}" .. bar
            end)
            t.key()
            l.done("{dim}fps{}  " .. love.timer.getFPS())
        end,
    },
}
