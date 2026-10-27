-- ─────────────────────────────────────────────────────────────────────────
--  HOW TO ADD A COMMAND
--
--  1. Copy this file to a new name in commands/, e.g. commands/greet.lua
--     (files starting with "_" are ignored, so this template never loads)
--  2. Change name / help / run
--  3. Type `reload` in the terminal — no restart needed
--
--  Inside run() you get `t`, the terminal toolkit:
--
--    t.print(text, color)          print a line. Inline colours: "{accent}hi{} there"
--    t.type(text, color, speed)    typewriter effect (waits until done)
--    t.decode(text, color, secs)   scrambled → real text (waits)
--    t.banner(text)                BIG block letters
--    t.progress(label, secs)       animated progress bar (waits)
--    t.spin(label, secs, done)     spinner, then a ✓
--    t.table(rows, colors)         aligned columns
--    t.live(fn)                    a line that updates every frame; returns { done = fn }
--    t.wait(secs)                  pause
--    t.ask(prompt, {mask=true})    read a line from the user
--    t.key()                       wait for any key, returns its name
--    t.clear()  t.shake(n)  t.flash(color)  t.glitch(secs)  t.ripple()  t.sparks(n)
--    t.matrix(true/false)          matrix rain behind the text
--    t.sound(name)                 key enter back tick beep ok err whoosh glitch
--    t.theme(name)                 red mint cyan violet amber ice mono
--    t.run("other command")        run another command
--    t.hex(n)  t.ip()  t.pick(list)  t.random(a, b)  t.pad(s, w)
--
--  Colours: text dim accent white ok warn err info faint
-- ─────────────────────────────────────────────────────────────────────────

return {
    name = "greet",
    aliases = { "hi" },               -- optional other names
    help = "say hello",               -- shown in `help`
    usage = "greet [name]",           -- optional
    category = "fun",                 -- optional: groups commands in `help`

    run = function(t, args, rest)
        -- args = list of words after the command, rest = the same as one string
        local name = args[1] or t.ask("what's your name? ")
        t.type("hello, {accent}" .. name .. "{}!")
        t.sound("ok")
        t.sparks(30)
    end,
}
