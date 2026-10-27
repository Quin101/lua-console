-- Quick action buttons, effect switches and theme picker.
local SITES = { "example.com", "darknet.local", "megacorp.io", "nasa.gov", "bank-of-nowhere.net", "qrawller.dev" }
local TARGETS = { "mainframe.corp", "gibson", "skynet.mil", "evilcorp.com", "satellite-7", "vault.bank" }

local ACTIONS = {
    { "SCAN",    function(ui) return "scan" end, "sweep the network" },
    { "CRAWL",   function(ui) return "crawl " .. ui.util.pick(SITES) end, "spider a website" },
    { "HACK",    function(ui) return "hack " .. ui.util.pick(TARGETS) end, "breach a random target" },
    { "TRACE",   function(ui) return "trace " .. ui.util.ip() end, "trace a route" },
    { "DECRYPT", function(ui) return "decrypt" end, "decode an intercepted message" },
    { "BREACH",  function(ui) return "breach" end, "password challenge" },
    { "MATRIX",  function(ui) return "rain 5" end, "digital rain" },
    { "GLITCH",  function(ui) return "glitch" end, "corrupt the signal" },
    { "CLEAR",   function(ui) return "clear" end, "wipe the terminal" },
}

return {
    title = "QUICK ACTIONS",
    order = 4,
    height = 196,

    draw = function(w, ui, x, y, width, height)
        local cols = 3
        local bw = (width - (cols - 1) * 8) / cols
        local bh = 26
        for i, a in ipairs(ACTIONS) do
            local cx = x + ((i - 1) % cols) * (bw + 8)
            local cy = y + math.floor((i - 1) / cols) * (bh + 7)
            if ui.button("act_" .. a[1], a[1], cx, cy, bw, bh, { tip = a[3] }) then
                ui.run(a[2](ui))
            end
        end

        -- effect switches
        local cfg = ui.cfg
        local ty = y + 3 * (bh + 7) + 6
        local half = (width - 16) / 2
        local snd = require("src.sound")
        local s = ui.toggle("t_sound", "sound", snd.enabled, x, ty, half)
        if s ~= snd.enabled then snd.enabled = s; cfg.on_setting("sound", s) end
        cfg._glow = cfg._glow or (cfg.glow > 0 and cfg.glow or 0.55)
        local g = ui.toggle("t_glow", "glow", cfg.glow > 0, x + half + 16, ty, half)
        cfg.glow = g and cfg._glow or 0
        cfg.background_grid = ui.toggle("t_grid", "grid", cfg.background_grid ~= false, x, ty + 26, half)
        cfg.particles = ui.toggle("t_part", "sparks", cfg.particles ~= false, x + half + 16, ty + 26, half)

        -- theme swatches
        local sy = ty + 60
        ui.text("theme", x, sy - 1, "dim")
        local order = ui.util.theme_order
        for i, name in ipairs(order) do
            local c = ui.util.themes[name].accent
            local sx = x + 64 + (i - 1) * 26
            local hov = ui.hover(sx - 9, sy - 2, 18, 18)
            local r = ui.ease("sw_" .. name, (hov and 8 or 6) + (ui.util.theme == name and 1.5 or 0), 18)
            love.graphics.setColor(c[1], c[2], c[3], 1)
            love.graphics.circle("fill", sx, sy + 7, r)
            if ui.util.theme == name then
                love.graphics.setLineWidth(1)
                love.graphics.circle("line", sx, sy + 7, r + 3.5)
            end
            if hov then ui.tooltip(name) end
            if ui.clicked(sx - 9, sy - 2, 18, 18) then ui.run("theme " .. name) end
        end
    end,
}
