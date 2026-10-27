-- The toolkit every command receives as `t`.  See commands/_template.lua.
local util = require("src.util")
local fx = require("src.fx")
local sound = require("src.sound")
local bigtext = require("src.bigtext")

return function(T)
    local t = {}

    local function in_task()
        return T.task and coroutine.running() == T.task.co
    end

    -- pause the command until fn() returns true (or `seconds` pass)
    local function block(seconds, fn)
        if not in_task() then return end
        T.task.wake_at = seconds and (T.time + seconds) or nil
        T.task.wait_fn = fn
        coroutine.yield()
    end

    ---------------------------------------------------------------- text output

    -- t.print("hello {accent}world{}", "dim")   colour names: text dim accent white ok warn err info faint
    function t.print(text, color)
        T.add(text, color)
    end

    -- prints without interpreting {markup}
    function t.raw(text, color)
        T.add(text, color, { raw = true })
    end

    -- typewriter effect; waits until finished.  speed = characters per second
    function t.type(text, color, speed)
        speed = speed or 70
        local lines = T.add(text, color, { fx = "type", speed = speed })
        local total = 0
        for i, l in ipairs(lines) do
            l.t0 = T.time + total / speed
            total = total + l.len
        end
        block(total / speed + 0.02)
    end

    -- scrambled characters that resolve into the real text; waits until finished
    function t.decode(text, color, duration)
        duration = duration or 0.9
        T.add(text, color, { fx = "decode", duration = duration })
        sound.play("glitch", { volume = 0.35, pitch = 1.5 })
        block(duration + 0.05)
    end

    -- big pixel letters with a light sweep.  text can also be a function
    -- returning the text, which makes it live (see the `clock` command).
    function t.banner(text, color)
        local line = T.add("", color, { raw = true })[1]
        line.banner = text
        line.color = color or "accent"
        for _ = 2, T.BANNER_LINES do T.add("") end
        sound.play("whoosh", { volume = 0.5 })
        local len = type(text) == "string" and #text or 8
        block(math.min(1.2, len * 6 / 70 + 0.1))
        return line
    end

    -- t.wait(0.5)  pause for half a second
    function t.wait(seconds)
        block(seconds or 0.5)
    end

    -- a line whose text is recalculated every frame.
    --   local l = t.live(function(time) return "clock: " .. os.date("%X") end)
    --   l.done("final text")      -- freezes it
    function t.live(fn, color)
        local line = T.add("", color)[1]
        line.live = fn
        line.color = color
        return {
            line = line,
            done = function(final)
                line.live = nil
                line.segs = util.markup(final or "", color or "text")
                line.len = util.ulen(util.plain(line.segs))
            end,
        }
    end

    -- animated progress bar; waits until it reaches 100%
    function t.progress(label, duration, opts)
        opts = opts or {}
        duration = duration or 1.5
        local width = opts.width or 28
        label = util.pad(label or "", opts.label_width or 26)
        local start = T.time
        local function bar(p)
            local filled = math.floor(p * width + 0.5)
            local s = "{accent}" .. string.rep("━", math.max(0, filled - 1))
            if filled > 0 then s = s .. (p < 1 and "{white}━" or "━") end
            return s .. "{faint}" .. string.rep("━", width - filled) .. "{}"
        end
        local function shape(p)
            -- uneven but always moving forwards, like a real transfer
            return util.clamp(p - math.sin(p * math.pi * 6) / (math.pi * 6) * 0.85, 0, 1)
        end
        local l = t.live(function(now)
            local p = shape(util.clamp((now - start) / duration, 0, 1))
            return "{dim}" .. label .. "{} " .. bar(p) .. ("  {white}%3d%%{}"):format(math.floor(p * 100))
        end)
        block(duration)
        l.done("{dim}" .. label .. "{} " .. bar(1) .. "  {accent}" .. (opts.done or "done") .. "{}")
        sound.play("beep", { pitch = 1.2, volume = 0.5 })
    end

    -- spinner next to a label for `duration` seconds
    function t.spin(label, duration, done_text)
        local frames = { "◜", "◝", "◞", "◟" }
        local start = T.time
        local l = t.live(function(now)
            return "{accent}" .. frames[math.floor((now - start) * 12) % 4 + 1] .. "{} " .. label
        end)
        block(duration or 1)
        l.done("{accent}✓{} " .. label .. (done_text and ("  {dim}" .. done_text .. "{}") or ""))
    end

    -- t.list({ {"ssh", "22", "open"}, {"http", "80", "closed"} }, { "accent", "dim", "ok" })
    -- prints rows as aligned columns
    function t.table(rows, colors, gap)
        gap = gap or 3
        local widths = {}
        for _, r in ipairs(rows) do
            for i, cell in ipairs(r) do
                widths[i] = math.max(widths[i] or 0, util.ulen(tostring(cell)))
            end
        end
        for _, r in ipairs(rows) do
            local parts = {}
            for i, cell in ipairs(r) do
                local c = colors and colors[i] or "text"
                parts[#parts + 1] = "{" .. c .. "}" .. util.pad(tostring(cell):gsub("{", "{{"), widths[i] + gap) .. "{}"
            end
            T.add(table.concat(parts))
        end
    end

    ---------------------------------------------------------------- input

    -- local name = t.ask("name? ")      waits for the user to type a line
    -- local pw = t.ask("password: ", { mask = true })
    function t.ask(prompt, opts)
        opts = opts or {}
        local req = { prompt = prompt or "? ", mask = opts.mask }
        T.asking = req
        block(nil, function() return req.result ~= nil end)
        return req.result or ""
    end

    -- waits for any key press and returns its name ("space", "a", "return" ...)
    function t.key()
        if not in_task() then return end
        T.task.wait_key = true
        block(nil, function() return not T.task.wait_key end)
        return T.task.key
    end

    ---------------------------------------------------------------- effects

    function t.clear() T.clear() end
    function t.shake(amount) fx.do_shake(amount or 6) end
    function t.flash(color, alpha) fx.flash(color, alpha) end
    function t.glitch(seconds, amount) fx.glitch(seconds or 0.4, amount or 1); sound.play("glitch", { volume = 0.6 }) end
    function t.ripple(strength) fx.ripple(T.cursor_x, T.cursor_y, strength or 1.5) end
    function t.sparks(n, color) fx.sparks(T.cursor_x, T.cursor_y, n or 20, color or "accent", 160) end
    function t.matrix(on) fx.matrix.on = on ~= false end

    -- sounds: key enter back tick beep ok err whoosh glitch
    function t.sound(name, opts) sound.play(name, opts) end

    function t.theme(name)
        if util.set_theme(name) then
            fx.build_vignette()
            if T.cfg.on_setting then T.cfg.on_setting("theme", name) end
            return true
        end
        return false
    end

    ---------------------------------------------------------------- misc

    -- run another command from inside a command:  t.run("banner hi")
    function t.run(line)
        local words = util.words(line)
        local cmd = words[1] and T.commands.find(words[1]:lower())
        if not cmd then return t.print("unknown command: " .. tostring(words[1]), "err") end
        local args = {}
        for i = 2, #words do args[#args + 1] = words[i] end
        cmd.run(t, args, util.trim(line:sub(#words[1] + 1)))
    end

    function t.width() return T.cols end
    function t.time() return T.time end
    function t.exit() love.event.quit() end

    t.random = math.random
    t.hex = util.hexstr
    t.ip = util.ip
    t.pick = util.pick
    t.pad = util.pad
    t.lpad = util.lpad
    t.util = util
    t.bigtext = bigtext
    t.commands = T.commands
    t.config = T.cfg
    t.history = T.history
    t.sound_module = sound
    t.terminal = T

    return t
end
