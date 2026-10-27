local util = require("src.util")
local fx = require("src.fx")
local sound = require("src.sound")
local bigtext = require("src.bigtext")

local T = {
    lines = {},
    input = { chars = {}, born = {}, pos = 0 },
    history = {},
    hist_i = nil,
    scroll = 0,
    scroll_back = 0,
    time = 0,
    task = nil,
    cursor_x = 0,
    cursor_y = 0,
    last_type = 0,
    wipe = nil,
    max_lines = 3000,
}

local PAD_X, TOP = 22, 52
T.BANNER_LINES = 3 -- terminal rows a banner occupies
T.area = { x = PAD_X, y = TOP, w = 800, h = 600 }

-- layout -----------------------------------------------------------------------

function T.init(cfg, commands)
    T.cfg = cfg
    T.commands = commands
    T.font = love.graphics.newFont("assets/fonts/JetBrainsMono-Regular.ttf", cfg.font_size or 15)
    T.font_bold = love.graphics.newFont("assets/fonts/JetBrainsMono-Bold.ttf", cfg.font_size or 15)
    T.font_small = love.graphics.newFont("assets/fonts/JetBrainsMono-Regular.ttf", math.max(10, (cfg.font_size or 15) - 3))
    T.char_w = T.font:getWidth("M")
    T.line_h = math.floor(T.font:getHeight() * (cfg.line_spacing or 1.35))
    fx.cell_w, fx.cell_h = T.char_w, T.line_h
    T.layout()
end

-- the rectangle the terminal text lives in (set by the dashboard layout)
function T.set_area(x, y, w, h)
    T.area = { x = x, y = y, w = w, h = h }
    T.layout()
end

function T.layout()
    local w, h = love.graphics.getDimensions()
    T.w, T.h = w, h
    local a = T.area
    T.cols = math.max(20, math.floor(a.w / T.char_w))
    T.view_h = a.h - 26 -- room for the hint line
    T.rows = math.max(3, math.floor(T.view_h / T.line_h))
end

-- output -----------------------------------------------------------------------

local function push_line(line)
    line.t0 = line.t0 or T.time
    line.len = line.len or util.ulen(util.plain(line.segs))
    T.lines[#T.lines + 1] = line
    if #T.lines > T.max_lines then
        table.remove(T.lines, 1)
        T.scroll = T.scroll - 1
    end
    T.scroll_back = 0
    return line
end

local function prepare_decode(line)
    local n = line.len
    line.reveal = {}
    local d = line.duration or 0.9
    for i = 1, n do
        line.reveal[i] = line.t0 + d * 0.55 * (i - 1) / math.max(1, n - 1) + d * 0.45 * math.random()
    end
end

-- Adds text (with {colour} markup). Returns the created line objects.
function T.add(text, color, opts)
    opts = opts or {}
    text = tostring(text == nil and "" or text)
    local out = {}
    for _, raw in ipairs(util.split(text, "\n")) do
        local segs = opts.raw and { { text = raw, color = color or "text" } } or util.markup(raw, color or "text")
        for _, segline in ipairs(util.wrap(segs, T.cols)) do
            local line = { segs = segline, fx = opts.fx, speed = opts.speed, duration = opts.duration, banner = opts.banner }
            out[#out + 1] = push_line(line)
            if line.fx == "decode" then prepare_decode(line) end
        end
    end
    return out
end

function T.clear(animated)
    if animated ~= false and #T.lines > 0 then
        T.wipe = { lines = T.lines, t0 = T.time, scroll = T.scroll }
    end
    T.lines = {}
    T.scroll = 0
    T.scroll_back = 0
end

-- tasks (commands run as coroutines so they can wait) ------------------------------

function T.start_task(fn, name)
    local co = coroutine.create(fn)
    T.task = { co = co, name = name }
    T.resume_task()
end

function T.resume_task()
    local task = T.task
    if not task then return end
    local ok, err = coroutine.resume(task.co)
    if not ok then
        T.task = nil
        T.add("error in " .. tostring(task.name) .. ": " .. tostring(err), "err", { raw = true })
        sound.play("err")
        fx.glitch(0.3, 0.6)
        print(debug.traceback(task.co, err))
    elseif coroutine.status(task.co) == "dead" then
        if T.task == task then T.task = nil end
        if T.cfg.on_task_done then T.cfg.on_task_done() end
    end
end

function T.abort_task()
    if not T.task then return end
    T.task = nil
    T.asking = nil
    fx.matrix.on = false
    T.add("^C", "dim")
    sound.play("back")
end

local function task_ready()
    local task = T.task
    if not task then return false end
    if task.wake_at and T.time < task.wake_at then return false end
    if task.wait_fn and not task.wait_fn() then return false end
    task.wake_at, task.wait_fn = nil, nil
    return true
end

-- executing a command line --------------------------------------------------------

function T.run_line(line_text)
    line_text = util.trim(line_text)
    if line_text == "" then return end
    local words = util.words(line_text)
    local name = words[1]:lower()
    local alias = T.cfg.aliases and T.cfg.aliases[name]
    if alias then
        line_text = alias .. line_text:sub(#words[1] + 1)
        words = util.words(line_text)
        name = words[1]:lower()
    end
    local cmd = T.commands.find(name)
    if not cmd then
        local guess = T.commands.suggest(name)
        T.add("command not found: {white}" .. name:gsub("{", "{{") .. "{}" ..
            (guess and ("  ·  did you mean {accent}" .. guess .. "{}?") or ""), "err")
        sound.play("err")
        fx.glitch(0.18, 0.4)
        fx.do_shake(5)
        return
    end
    local args = {}
    for i = 2, #words do args[#args + 1] = words[i] end
    local rest = util.trim(line_text:sub(#words[1] + 1))
    T.start_task(function() cmd.run(T.api, args, rest) end, cmd.name)
end

function T.submit()
    local text = table.concat(T.input.chars)
    local prompt_segs = T.prompt_segs()
    -- echo the command into the scrollback
    local segs = {}
    for _, s in ipairs(prompt_segs) do segs[#segs + 1] = s end
    if T.asking and T.asking.mask then
        segs[#segs + 1] = { text = string.rep("•", #T.input.chars), color = "white" }
    else
        segs[#segs + 1] = { text = text, color = "white" }
    end
    for _, l in ipairs(util.wrap(segs, T.cols)) do push_line({ segs = l, t0 = T.time - 1 }) end

    fx.ripple(T.cursor_x, T.cursor_y, 1)
    fx.sparks(T.cursor_x, T.cursor_y, 10, "accent", 110)
    fx.do_shake(2.5)
    sound.play("enter", { pitch = 0.95 + math.random() * 0.1 })

    T.input = { chars = {}, born = {}, pos = 0 }
    T.hist_i = nil

    if T.asking then
        T.asking.result = text
        T.asking = nil
        return
    end
    if util.trim(text) ~= "" then
        if T.history[#T.history] ~= text then T.history[#T.history + 1] = text end
        if T.cfg.on_history then T.cfg.on_history(T.history) end
    end
    T.run_line(text)
end

function T.prompt_segs()
    if T.asking then
        return util.markup(T.asking.prompt, "accent")
    end
    return {
        { text = T.cfg.prompt or "qrawller", color = "accent" },
        { text = " " .. (T.cfg.prompt_symbol or "❯") .. " ", color = "dim" },
    }
end

-- Types a command into the prompt by itself, then runs it. Used by the UI widgets.
function T.request(line)
    if T.task and not T.asking then T.abort_task() end
    if T.asking then T.asking = nil; T.task = nil end
    T.input = { chars = {}, born = {}, pos = 0 }
    T.auto = { chars = util.chars(line), i = 0, next = T.time + 0.05 }
end

function T.input_visible()
    return T.task == nil or T.asking ~= nil
end

-- input ------------------------------------------------------------------------

local function set_input(str)
    local chars = util.chars(str)
    local born = {}
    for i = 1, #chars do born[i] = T.time - 1 + i * 0.012 end
    T.input = { chars = chars, born = born, pos = #chars }
end

function T.textinput(t)
    if not T.input_visible() or T.auto then return end
    for _, ch in ipairs(util.chars(t)) do
        local inp = T.input
        inp.pos = inp.pos + 1
        table.insert(inp.chars, inp.pos, ch)
        table.insert(inp.born, inp.pos, T.time)
    end
    T.last_type = T.time
    T.scroll_back = 0
    sound.play("key", { pitch = 0.9 + math.random() * 0.25, volume = 0.8 })
    fx.sparks(T.cursor_x + T.char_w, T.cursor_y, 2, "accent", 50)
    fx.ripple(T.cursor_x, T.cursor_y, 0.25)
end

function T.complete()
    local text = table.concat(T.input.chars)
    if text:find("%s") then return end
    local matches = T.commands.complete(text:lower())
    if #matches == 1 then
        set_input(matches[1] .. " ")
        sound.play("beep", { pitch = 1.4, volume = 0.5 })
    elseif #matches > 1 then
        T.add(table.concat(matches, "   "), "dim")
        sound.play("tick")
    end
end

function T.keypressed(key)
    local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
    local task = T.task

    if ctrl and key == "c" then
        if task then
            T.abort_task()
        else
            T.add(table.concat(T.input.chars) .. " ^C", "dim", { raw = true })
            T.input = { chars = {}, born = {}, pos = 0 }
        end
        return
    end

    if T.auto then return end

    if task and task.wait_key then
        task.key = key
        task.wait_key = false
        return
    end

    if key == "pageup" or (key == "up" and love.keyboard.isDown("lshift", "rshift")) then
        T.scroll_back = T.scroll_back + math.floor(T.rows / 2)
        return
    elseif key == "pagedown" or (key == "down" and love.keyboard.isDown("lshift", "rshift")) then
        T.scroll_back = math.max(0, T.scroll_back - math.floor(T.rows / 2))
        return
    end

    if not T.input_visible() then return end
    local inp = T.input

    if key == "return" or key == "kpenter" then
        T.submit()
    elseif key == "backspace" then
        if inp.pos > 0 then
            if ctrl then
                while inp.pos > 0 and inp.chars[inp.pos] == " " do
                    table.remove(inp.chars, inp.pos); table.remove(inp.born, inp.pos); inp.pos = inp.pos - 1
                end
                while inp.pos > 0 and inp.chars[inp.pos] ~= " " do
                    table.remove(inp.chars, inp.pos); table.remove(inp.born, inp.pos); inp.pos = inp.pos - 1
                end
            else
                table.remove(inp.chars, inp.pos)
                table.remove(inp.born, inp.pos)
                inp.pos = inp.pos - 1
            end
            T.last_type = T.time
            sound.play("back", { pitch = 0.9 + math.random() * 0.2 })
            fx.sparks(T.cursor_x, T.cursor_y, 2, "dim", 40)
        end
    elseif key == "delete" then
        if inp.pos < #inp.chars then
            table.remove(inp.chars, inp.pos + 1)
            table.remove(inp.born, inp.pos + 1)
            sound.play("back")
        end
    elseif key == "left" then
        inp.pos = math.max(0, inp.pos - 1); T.last_type = T.time
    elseif key == "right" then
        inp.pos = math.min(#inp.chars, inp.pos + 1); T.last_type = T.time
    elseif key == "home" then
        inp.pos = 0
    elseif key == "end" then
        inp.pos = #inp.chars
    elseif key == "up" and not T.asking then
        if #T.history > 0 then
            T.hist_i = math.max(1, (T.hist_i or #T.history + 1) - 1)
            set_input(T.history[T.hist_i])
            sound.play("tick")
        end
    elseif key == "down" and not T.asking then
        if T.hist_i then
            T.hist_i = T.hist_i + 1
            if T.hist_i > #T.history then
                T.hist_i = nil
                set_input("")
            else
                set_input(T.history[T.hist_i])
            end
            sound.play("tick")
        end
    elseif key == "tab" and not T.asking then
        T.complete()
    elseif key == "l" and ctrl then
        T.clear()
        sound.play("whoosh", { volume = 0.6 })
    elseif key == "v" and ctrl then
        local clip = love.system.getClipboardText() or ""
        T.textinput((clip:gsub("[\r\n]+", " ")))
    end
end

function T.wheelmoved(_, y)
    T.scroll_back = math.max(0, T.scroll_back + y * 3)
end

-- update -----------------------------------------------------------------------

function T.update(dt)
    T.time = T.time + dt

    -- typewriter ticks
    for i = math.max(1, #T.lines - T.rows), #T.lines do
        local l = T.lines[i]
        if l and l.fx == "type" then
            local n = math.floor((T.time - l.t0) * (l.speed or 60))
            if n >= l.len then
                l.fx = nil
            elseif n > (l.last_n or 0) then
                if n - (l.last_tick or 0) >= 2 then
                    sound.play("tick", { pitch = 0.9 + math.random() * 0.3, volume = 0.5 })
                    l.last_tick = n
                end
                l.last_n = n
            end
        elseif l and l.fx == "decode" then
            if not l.reveal then prepare_decode(l) end
            if T.time > l.t0 + (l.duration or 0.9) + 0.05 then l.fx = nil end
        end
    end

    -- auto-typing from UI clicks
    local auto = T.auto
    if auto and T.time >= auto.next then
        auto.i = auto.i + 1
        local ch = auto.chars[auto.i]
        if ch then
            local inp = T.input
            inp.pos = inp.pos + 1
            table.insert(inp.chars, inp.pos, ch)
            table.insert(inp.born, inp.pos, T.time)
            T.last_type = T.time
            sound.play("key", { pitch = 0.95 + math.random() * 0.25, volume = 0.6 })
            fx.sparks(T.cursor_x + T.char_w, T.cursor_y, 1, "accent", 40)
            auto.next = T.time + 0.022 + math.random() * 0.03
        else
            T.auto = nil
            T.submit()
        end
    end

    -- run the active command until it waits again
    local guard = 0
    while task_ready() and guard < 200 do
        T.resume_task()
        guard = guard + 1
    end

    -- smooth scrolling
    local total = #T.lines + (T.input_visible() and 1 or 0)
    local max_scroll = math.max(0, total - T.rows)
    T.scroll_back = math.min(T.scroll_back, max_scroll)
    local target = max_scroll - T.scroll_back
    T.scroll = T.scroll + (target - T.scroll) * math.min(1, dt * 14)
    if math.abs(target - T.scroll) < 0.001 then T.scroll = target end

    if T.wipe and T.time - T.wipe.t0 > 0.35 then T.wipe = nil end
end

-- drawing ----------------------------------------------------------------------

local function scramble_char(i)
    local g = util.GLYPHS
    local k = (i * 7919 + math.floor(T.time * 24) * 104729) % #g + 1
    return g[k]
end

local function draw_line(line, x, y, alpha)
    local age = T.time - line.t0
    local a = util.ease_out(util.clamp(age / 0.18, 0, 1))
    x = x + (1 - a) * 10
    alpha = alpha * a

    local segs = line.segs
    if line.live then
        local ok, text = pcall(line.live, T.time)
        segs = util.markup(ok and tostring(text) or "?", line.color or "text")
    end

    local visible = math.huge
    if line.fx == "type" then visible = math.floor(age * (line.speed or 60)) end

    if line.banner then
        -- big pixel text spanning BANNER_LINES rows, with a sweep-in and a shimmer
        local text = line.banner
        if type(text) == "function" then
            local ok, v = pcall(text, T.time)
            text = ok and tostring(v) or "?"
        end
        if line.cache_text ~= text then
            line.cache_text, line.cache_rows = text, bigtext.render(text, "#")
        end
        local rows = line.cache_rows
        local ncols = #rows[1]
        local px = math.floor(T.line_h * T.BANNER_LINES / 6)
        px = math.max(2, math.min(px, math.floor(T.area.w / ncols)))
        local oy = y + (T.BANNER_LINES * T.line_h - px * 5) / 2
        local base = util.color(line.color or "accent")
        local white = util.palette.white
        local sweep = age * 70
        local shimmer = ((age * 30) % (ncols + 60)) - 20
        for r = 1, 5 do
            local row = rows[r]
            for c = 1, ncols do
                if row:byte(c) == 35 and c < sweep then -- '#'
                    local fresh = util.clamp(1 - (sweep - c) / 10, 0, 1)
                    local sh = math.max(0, 1 - math.abs(c - shimmer) / 5) * 0.55
                    local col = util.mix(base, white, math.max(fresh, sh))
                    love.graphics.setColor(col[1], col[2], col[3], alpha)
                    love.graphics.rectangle("fill", x + (c - 1) * px, oy + (r - 1) * px, px - 1, px - 1)
                end
            end
        end
        return
    end

    local col = 0
    for _, s in ipairs(segs) do
        local c = util.color(s.color)
        local text = s.text
        local n = util.ulen(text)
        if col >= visible then break end
        if col + n > visible then
            text = util.usub(text, 1, visible - col)
        end
        if line.fx == "decode" and line.reveal then
            local chars = util.chars(text)
            for i, ch in ipairs(chars) do
                local gi = col + i
                if ch ~= " " then
                    if T.time >= (line.reveal[gi] or 0) then
                        local flash = util.clamp(1 - (T.time - line.reveal[gi]) / 0.25, 0, 1)
                        local cc = util.mix(c, util.palette.white, flash)
                        love.graphics.setColor(cc[1], cc[2], cc[3], alpha)
                        love.graphics.print(ch, x + (gi - 1) * T.char_w, y)
                    elseif T.time >= (line.reveal[gi] or 0) - 0.5 then
                        local d = util.palette.accent
                        love.graphics.setColor(d[1], d[2], d[3], alpha * 0.55)
                        love.graphics.print(scramble_char(gi), x + (gi - 1) * T.char_w, y)
                    end
                end
            end
        else
            love.graphics.setColor(c[1], c[2], c[3], alpha)
            love.graphics.print(text, x + col * T.char_w, y)
        end
        col = col + n
    end

    -- the typing head
    if line.fx == "type" and visible < line.len then
        local acc = util.palette.accent
        love.graphics.setColor(acc[1], acc[2], acc[3], alpha * 0.9)
        love.graphics.rectangle("fill", x + visible * T.char_w, y + 3, T.char_w * 0.6, T.line_h - 8)
    end
end

local function draw_input(x, y)
    local col = 0
    for _, s in ipairs(T.prompt_segs()) do
        local c = util.color(s.color)
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.print(s.text, x + col * T.char_w, y)
        col = col + util.ulen(s.text)
    end
    local inp = T.input
    local text_c, white = util.palette.white, { 1, 1, 1 }
    local mask = T.asking and T.asking.mask
    for i, ch in ipairs(inp.chars) do
        local age = T.time - (inp.born[i] or 0)
        local p = util.clamp(age / 0.14, 0, 1)
        local scale = 1 + 0.45 * (1 - util.ease_out(p))
        local c = util.mix(white, text_c, util.clamp(age / 0.3, 0, 1))
        local cx = x + (col + i - 1) * T.char_w
        local cy = y - (1 - util.ease_out(p)) * 4
        love.graphics.setColor(c[1], c[2], c[3], 1)
        local glyph = mask and "•" or ch
        local fh = T.font:getHeight()
        love.graphics.print(glyph, cx + T.char_w / 2, cy + fh / 2, 0, scale, scale, T.font:getWidth(glyph) / 2, fh / 2)
    end

    -- cursor glides to its spot and breathes when idle
    local target = x + (col + inp.pos) * T.char_w
    T.cursor_x = T.cursor_x + (target - T.cursor_x) * math.min(1, love.timer.getDelta() * 28)
    T.cursor_y = y + T.line_h / 2
    local idle = T.time - T.last_type
    local a = idle < 0.6 and 1 or (0.55 + 0.45 * math.cos((idle - 0.6) * 4))
    local acc = util.palette.accent
    love.graphics.setColor(acc[1], acc[2], acc[3], a)
    love.graphics.rectangle("fill", T.cursor_x, y + 3, T.char_w, T.font:getHeight() - 2, 1.5, 1.5)
    -- character under the cursor stays readable
    local under = inp.chars[inp.pos + 1]
    if under and a > 0.5 then
        local bg = util.palette.bg
        love.graphics.setColor(bg[1], bg[2], bg[3], 1)
        love.graphics.print(mask and "•" or under, target, y)
    end
end

-- tiny animated graph in the status bar
local function sparkline(x, y, n, seed)
    local bars = { "▁", "▂", "▃", "▄", "▅", "▆", "▇" }
    local s = {}
    for i = 1, n do
        local v = math.sin(T.time * 1.7 + i * 0.7 + seed) * 0.5 + math.sin(T.time * 3.1 + i * 1.3 + seed * 2) * 0.3 + 0.5
        s[i] = bars[util.clamp(math.floor(v * 7) + 1, 1, 7)]
    end
    return table.concat(s)
end

local function draw_status()
    local f = T.font_small
    love.graphics.setFont(f)
    local acc, dim, text = util.palette.accent, util.palette.dim, util.palette.text
    local y = 18
    local pulse = 0.5 + 0.5 * math.sin(T.time * 2.4)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.5 + 0.5 * pulse)
    love.graphics.circle("fill", PAD_X + 4, y + f:getHeight() / 2, 3.2)
    love.graphics.setColor(text[1], text[2], text[3], 1)
    love.graphics.print("QRAWLLER", PAD_X + 16, y)
    love.graphics.setColor(dim[1], dim[2], dim[3], 1)
    love.graphics.print("console", PAD_X + 16 + f:getWidth("QRAWLLER "), y)

    local right = os.date("%H:%M:%S")
    local cpu = ("cpu %s   net %s   "):format(sparkline(0, 0, 8, 1), sparkline(0, 0, 8, 4))
    local rw = f:getWidth(right)
    love.graphics.setColor(dim[1], dim[2], dim[3], 1)
    love.graphics.print(cpu, T.w - PAD_X - rw - f:getWidth(cpu), y)
    love.graphics.setColor(text[1], text[2], text[3], 1)
    love.graphics.print(right, T.w - PAD_X - rw, y)

    -- hairline with a travelling highlight
    local ly = TOP - 12
    local faint = util.palette.faint
    love.graphics.setColor(faint[1], faint[2], faint[3], 1)
    love.graphics.rectangle("fill", PAD_X, ly, T.w - PAD_X * 2, 1)
    local span = T.w - PAD_X * 2
    local hx = PAD_X + ((T.time * 0.18) % 1) * (span + 200) - 100
    for i = 0, 19 do
        local a = (1 - math.abs(i - 10) / 10) * 0.6
        love.graphics.setColor(acc[1], acc[2], acc[3], a)
        local sx = hx + i * 6
        if sx > PAD_X and sx < PAD_X + span then love.graphics.rectangle("fill", sx, ly, 6, 1) end
    end

    -- bottom hint
    local hint
    if T.task and not T.asking then
        local frames = { "◜", "◝", "◞", "◟" }
        hint = frames[math.floor(T.time * 10) % 4 + 1] .. "  running " .. tostring(T.task.name) .. "   ·   ctrl+c to abort"
    elseif T.scroll_back > 0 then
        hint = "↑ scrolled " .. math.floor(T.scroll_back) .. " lines   ·   type to return"
    else
        hint = "tab complete   ·   ↑↓ history   ·   help"
    end
    love.graphics.setColor(dim[1], dim[2], dim[3], 0.9)
    love.graphics.print(hint, T.area.x, T.area.y + T.area.h - f:getHeight())
    love.graphics.setFont(T.font)
end

function T.draw_text()
    love.graphics.setFont(T.font)
    fx.draw_matrix(T.font)
    local mfade = 1 - fx.matrix.alpha * 0.85
    if T.before_text then T.before_text() end
    love.graphics.setFont(T.font)

    local A = T.area
    love.graphics.setScissor(A.x - 14, A.y - 4, A.w + 28, T.view_h + 8)
    local first = math.max(1, math.floor(T.scroll) + 1)
    for i = first, math.min(#T.lines, first + T.rows + 1) do
        local y = A.y + (i - 1 - T.scroll) * T.line_h
        draw_line(T.lines[i], A.x, y, mfade)
    end
    if T.input_visible() then
        local y = A.y + (#T.lines - T.scroll) * T.line_h
        if mfade > 0.2 then draw_input(A.x, y) end
    else
        T.cursor_y = A.y + (#T.lines - T.scroll) * T.line_h
    end
    -- dissolving lines after `clear`
    if T.wipe then
        local p = util.clamp((T.time - T.wipe.t0) / 0.35, 0, 1)
        local wl = T.wipe.lines
        local start = math.max(1, math.floor(T.wipe.scroll) + 1)
        for i = start, math.min(#wl, start + T.rows + 1) do
            local y = A.y + (i - 1 - T.wipe.scroll) * T.line_h - util.ease_out(p) * 40 - (i - start) * p * 6
            draw_line(wl[i], A.x, y, (1 - p) * mfade)
        end
    end
    love.graphics.setScissor()
    draw_status()
    if T.after_text then T.after_text() end
end

function T.draw()
    fx.render(T.draw_text, T.cursor_x, T.cursor_y, T.time)
end

function T.resize()
    T.layout()
    fx.resize(love.graphics.getDimensions())
end

return T
