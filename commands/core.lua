-- Built-in essentials. A file can return a list of commands like this one does.
return {
    {
        name = "help",
        help = "list every command",
        category = "core",
        run = function(t, args)
            local cmds = t.commands.list
            if args[1] then
                local c = t.commands.find(args[1]:lower())
                if not c then return t.print("no such command: " .. args[1], "err") end
                t.print("{accent}" .. c.name .. "{}  " .. (c.help or ""))
                if c.usage then t.print("usage   {white}" .. c.usage, "dim") end
                if c.aliases then t.print("aliases " .. table.concat(c.aliases, ", "), "dim") end
                return
            end
            local groups, order = {}, {}
            for _, c in ipairs(cmds) do
                if not c.hidden then
                    local g = c.category or "other"
                    if not groups[g] then
                        groups[g] = {}
                        order[#order + 1] = g
                    end
                    table.insert(groups[g], c)
                end
            end
            local rank = { core = 1, hack = 2, fx = 3, fun = 4, system = 5 }
            table.sort(order, function(a, b) return (rank[a] or 9) < (rank[b] or 9) end)
            t.print("")
            for _, g in ipairs(order) do
                t.print("{dim}── " .. g .. " " .. string.rep("─", 40 - #g))
                for _, c in ipairs(groups[g]) do
                    t.print("  {accent}" .. t.pad(c.name, 12) .. "{}" .. (c.help or ""):gsub("{", "{{"))
                    t.sound("tick", { pitch = 1.6, volume = 0.3 })
                    t.wait(0.018)
                end
                t.print("")
            end
            t.print("{dim}help <command> for details  ·  add your own in the commands/ folder")
            t.print("")
        end,
    },
    {
        name = "clear",
        help = "wipe the screen",
        category = "core",
        run = function(t)
            t.sound("whoosh", { volume = 0.6 })
            t.clear()
        end,
    },
    {
        name = "echo",
        help = "print text (supports {accent}colour{} markup)",
        usage = "echo <text>",
        category = "core",
        run = function(t, args, rest) t.print(rest) end,
    },
    {
        name = "theme",
        help = "change colours: red mint cyan violet amber ice mono",
        usage = "theme [name]",
        category = "core",
        run = function(t, args)
            local order = t.util.theme_order
            local name = args[1]
            if not name then
                -- cycle to the next theme
                local cur = t.util.theme
                for i, n in ipairs(order) do
                    if n == cur then name = order[i % #order + 1] end
                end
            end
            if t.theme(name) then
                t.flash("accent", 0.18)
                t.ripple(2)
                t.sound("ok", { volume = 0.5 })
                t.print("theme → {accent}" .. name)
            else
                t.print("themes: " .. table.concat(order, "  "), "dim")
            end
        end,
    },
    {
        name = "sound",
        help = "turn sound on or off",
        usage = "sound [on|off]",
        category = "core",
        run = function(t, args)
            local s = t.sound_module
            if args[1] == "on" then s.enabled = true
            elseif args[1] == "off" then s.enabled = false
            else s.enabled = not s.enabled end
            t.config.on_setting("sound", s.enabled)
            t.print("sound " .. (s.enabled and "{accent}on" or "{dim}off"))
            t.sound("beep")
        end,
    },
    {
        name = "panels",
        help = "show or hide the side panels (also F2)",
        category = "core",
        run = function(t)
            t.ui.show_panels = not t.ui.show_panels
            t.sound("whoosh", { volume = 0.5 })
        end,
    },
    {
        name = "fullscreen",
        aliases = { "fs" },
        help = "toggle fullscreen (also F11)",
        category = "core",
        run = function()
            love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        end,
    },
    {
        name = "history",
        help = "commands you've typed",
        category = "core",
        run = function(t)
            local h = t.history
            for i = math.max(1, #h - 20), #h do
                t.print("{dim}" .. t.lpad(tostring(i), 4) .. "{}  " .. h[i]:gsub("{", "{{"))
            end
        end,
    },
    {
        name = "reload",
        help = "reload commands/ and widgets/ after you edit them",
        category = "core",
        run = function(t)
            t.spin("reloading commands", 0.4)
            local n = t.commands.load()
            local nw = t.ui.load_widgets()
            t.print("loaded {accent}" .. n .. "{} commands and {accent}" .. nw .. "{} widgets")
            for _, e in ipairs(t.commands.errors) do t.print("{warn}! {}" .. e:gsub("{", "{{"), "dim") end
            for _, e in ipairs(t.ui.errors) do t.print("{warn}! {}" .. e:gsub("{", "{{"), "dim") end
            t.sound("ok", { volume = 0.5 })
        end,
    },
    {
        name = "exit",
        help = "close the terminal",
        category = "core",
        run = function(t)
            t.type("closing session...", "dim", 60)
            t.glitch(0.4)
            t.wait(0.35)
            t.exit()
        end,
    },
    {
        name = "banner",
        help = "giant block text",
        usage = "banner <text>",
        category = "fx",
        run = function(t, args, rest)
            t.print("")
            t.banner(rest ~= "" and rest or "QRAWLLER")
            t.print("")
        end,
    },
    {
        name = "glitch",
        help = "break the screen for a second",
        category = "fx",
        run = function(t, args)
            t.glitch(tonumber(args[1]) or 0.8)
            t.shake(8)
            t.decode("signal corrupted. recovering...", "err", 0.8)
        end,
    },
    {
        name = "about",
        help = "what is this",
        category = "core",
        run = function(t)
            t.print("")
            t.banner("QRAWLLER")
            t.print("")
            t.type("a minimal, over-animated terminal for doing cool-looking things.", "text", 90)
            t.print("{dim}built with lua + löve  ·  every sound is generated in code")
            t.print("{dim}drop a .lua file into {}commands/{dim} and type {accent}reload{dim} to add your own.")
            t.print("")
        end,
    },
}
