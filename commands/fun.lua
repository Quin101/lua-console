local QUOTES = {
    { "the quieter you become, the more you are able to hear.", "kali linux motto" },
    { "talk is cheap. show me the code.", "linus torvalds" },
    { "any sufficiently advanced technology is indistinguishable from magic.", "arthur c. clarke" },
    { "the best way to predict the future is to invent it.", "alan kay" },
    { "first, solve the problem. then, write the code.", "john johnson" },
    { "it's not a bug — it's an undocumented feature.", "anonymous" },
    { "there is no place like 127.0.0.1", "every sysadmin" },
    { "hack the planet!", "hackers, 1995" },
    { "simplicity is prerequisite for reliability.", "edsger dijkstra" },
    { "the computer was born to solve problems that did not exist before.", "bill gates" },
}

return {
    {
        name = "matrix",
        help = "digital rain — press any key to stop",
        category = "fx",
        run = function(t)
            t.matrix(true)
            t.sound("whoosh")
            t.key()
            t.matrix(false)
        end,
    },
    {
        name = "clock",
        help = "a big live clock — any key to stop",
        category = "fun",
        run = function(t)
            t.print("")
            local l = t.banner(function() return os.date("%H:%M:%S") end)
            t.print("")
            t.print("{dim}" .. os.date("%A, %d %B %Y") .. "  ·  any key to stop")
            t.key()
            l.banner = os.date("%H:%M:%S")
            l.color = "dim"
        end,
    },
    {
        name = "quote",
        aliases = { "fortune" },
        help = "words of wisdom",
        category = "fun",
        run = function(t)
            local q = t.pick(QUOTES)
            t.print("")
            t.type("“" .. q[1] .. "”", "white", 55)
            t.print("{dim}   — " .. q[2])
            t.print("")
        end,
    },
    {
        name = "countdown",
        help = "dramatic countdown",
        usage = "countdown [seconds]",
        category = "fun",
        run = function(t, args)
            local n = math.min(tonumber(args[1]) or 5, 60)
            t.print("")
            for i = n, 1, -1 do
                t.clear()
                t.print("")
                t.banner(tostring(i))
                t.sound("beep", { pitch = 0.8 + (n - i) * 0.05 })
                t.ripple(1.5)
                t.wait(1)
            end
            t.clear()
            t.print("")
            t.flash("accent", 0.4)
            t.shake(12)
            t.banner("LAUNCH")
            t.sound("ok")
            t.sparks(80)
            t.print("")
        end,
    },
    {
        name = "roll",
        help = "roll dice, e.g. roll 2d6",
        usage = "roll [NdM]",
        category = "fun",
        run = function(t, args)
            local n, sides = (args[1] or "1d6"):match("(%d*)d(%d+)")
            n, sides = tonumber(n) or 1, tonumber(sides) or 6
            n = math.min(n, 20)
            local results, total = {}, 0
            for i = 1, n do
                local start = t.time()
                local final = t.random(1, sides)
                local l = t.live(function(now)
                    return "{dim}die " .. i .. "{}  {white}" .. t.random(1, sides)
                end)
                t.wait(0.35)
                l.done("{dim}die " .. i .. "{}  {accent}" .. final)
                t.sound("beep", { pitch = 1 + final / sides })
                results[#results + 1] = final
                total = total + final
            end
            t.print("total {accent}" .. total)
        end,
    },
    {
        name = "rain",
        help = "fill the screen with falling glyphs for a few seconds",
        category = "fx",
        run = function(t, args)
            t.matrix(true)
            t.wait(tonumber(args[1]) or 4)
            t.matrix(false)
        end,
    },
}
