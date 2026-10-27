-- Full-screen start-up sequence: spinning dotted globe, link arcs, a logo that
-- assembles from flying pixels, a shockwave, and a loading sequence.
-- Any key or click skips ahead.
local util = require("src.util")
local fx = require("src.fx")
local sound = require("src.sound")
local world = require("src.world")
local bigtext = require("src.bigtext")

local intro = { active = false }

local LOGO_AT = 1.15      -- pixels start flying
local IMPACT = 2.35       -- logo locks in
local LOAD_AT = 3.0       -- loading bar starts
local LOAD_LEN = 2.9
local READY = LOAD_AT + LOAD_LEN + 0.2
local AUTO_EXIT = READY + 2.6
local EXIT_LEN = 0.9

local function ease_out_back(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function intro.start(info, on_done)
    intro.active = true
    intro.t = 0
    intro.exit_t = nil
    intro.on_done = on_done
    intro.info = info or {}
    intro.events = {}
    intro.arcs = {}
    intro.next_arc = 0.8
    intro.fonts = {
        small = love.graphics.newFont("assets/fonts/JetBrainsMono-Regular.ttf", 12),
        mid = love.graphics.newFont("assets/fonts/JetBrainsMono-Bold.ttf", 15),
    }
    intro.node = util.hexstr(6)
    intro.globe = world.globe_points(2)
    intro.verts = {}
    for i = 1, #intro.globe do intro.verts[i] = { 0, 0, 0, 0, 0, 0 } end

    -- logo pixels
    local rows = bigtext.render("QRAWLLER", "#")
    intro.ncols = #rows[1]
    intro.pixels = {}
    for r = 1, 5 do
        for c = 1, intro.ncols do
            if rows[r]:byte(c) == 35 then
                local a = math.random() * math.pi * 2
                intro.pixels[#intro.pixels + 1] = {
                    r = r, c = c,
                    sa = a, sd = 0.55 + math.random() * 0.5,
                    delay = LOGO_AT + (c / intro.ncols) * 0.55 + math.random() * 0.35,
                    dur = 0.55 + math.random() * 0.25,
                    spin = (math.random() - 0.5) * 8,
                    ex = (math.random() - 0.5) * 2, ey = (math.random() - 0.5) * 2,
                }
            end
        end
    end

    intro.status = {
        "establishing encrypted uplink",
        "routing through " .. math.random(5, 9) .. " proxies",
        "spoofing hardware address",
        "decrypting world grid",
        "loading " .. (intro.info.commands or 0) .. " modules",
        "restoring " .. (intro.info.markers or 0) .. " map markers",
        "erasing footprints",
    }
    fx.hide_grid = true
    sound.ambient(true, 0.4)
end

local function once(name, t, fn)
    if not intro.events[name] and intro.t >= t then
        intro.events[name] = true
        fn()
    end
end

function intro.skip()
    if not intro.active then return end
    if intro.exit_t then return end
    if intro.t < IMPACT then
        -- jump straight to the finished logo so the skip still feels like something
        intro.t = math.max(intro.t, READY)
        for k in pairs({ riser = 1, impact = 1, sub = 1 }) do intro.events[k] = true end
        sound.play("boom", { volume = 0.7 })
        fx.glitch(0.25, 0.6)
    end
    intro.exit_t = 0
    sound.play("whoosh", { volume = 0.8 })
end

function intro.update(dt)
    if not intro.active then return end
    intro.t = intro.t + dt

    once("riser", 0.25, function() sound.play("riser", { volume = 0.8 }) end)
    once("impact", IMPACT, function()
        sound.play("boom")
        fx.glitch(0.45, 1)
        fx.do_shake(14)
        fx.flash("accent", 0.35)
        intro.shock = intro.t
    end)
    once("sub", IMPACT + 0.25, function() sound.play("glitch", { volume = 0.4, pitch = 0.7 }) end)
    once("ready", READY, function()
        sound.play("lock")
        sound.play("ok", { volume = 0.7 })
        fx.flash("accent", 0.12)
    end)

    -- clicks while pixels land
    if intro.t > LOGO_AT + 0.3 and intro.t < IMPACT then
        intro.tick_acc = (intro.tick_acc or 0) + dt
        if intro.tick_acc > 0.045 then
            intro.tick_acc = 0
            sound.play("tick", { pitch = 0.6 + math.random() * 0.5, volume = 0.6 })
        end
    end
    -- a beep per loading status
    local si = math.floor((intro.t - LOAD_AT) / (LOAD_LEN / #intro.status)) + 1
    if intro.t >= LOAD_AT and si ~= intro.last_status and si <= #intro.status then
        intro.last_status = si
        sound.play("beep", { pitch = 0.8 + si * 0.05, volume = 0.45 })
    end

    -- arcs between random places on the globe
    intro.next_arc = intro.next_arc - dt
    if intro.next_arc <= 0 and not intro.exit_t then
        intro.next_arc = 0.25 + math.random() * 0.35
        local g = intro.globe
        intro.arcs[#intro.arcs + 1] = { a = g[math.random(#g)], b = g[math.random(#g)], t0 = intro.t, len = 0.9 + math.random() * 0.6 }
        if #intro.arcs > 14 then table.remove(intro.arcs, 1) end
    end

    if intro.t > AUTO_EXIT and not intro.exit_t then intro.skip() end
    if intro.exit_t then
        intro.exit_t = intro.exit_t + dt
        if intro.exit_t >= EXIT_LEN then
            intro.active = false
            fx.hide_grid = false
            if intro.on_done then intro.on_done() end
        end
    end
end

-- globe -----------------------------------------------------------------------

local function rotator(angle, tilt)
    local ca, sa, ct, st = math.cos(angle), math.sin(angle), math.cos(tilt), math.sin(tilt)
    return function(p)
        local x = p[1] * ca + p[3] * sa
        local z = -p[1] * sa + p[3] * ca
        local y = p[2] * ct - z * st
        z = p[2] * st + z * ct
        return x, y, z
    end
end

local function draw_globe(cx, cy, R, alpha)
    local rot = rotator(intro.t * 0.22 + 2.2, 0.38)
    local acc, dim = util.palette.accent, util.palette.dim
    local verts = intro.verts
    for i, p in ipairs(intro.globe) do
        local x, y, z = rot(p)
        local v = verts[i]
        v[1], v[2] = cx + x * R, cy - y * R
        if z > 0 then
            local k = 0.25 + 0.75 * z
            v[3], v[4], v[5], v[6] = acc[1], acc[2], acc[3], k * 0.8 * alpha
        else
            v[3], v[4], v[5], v[6] = dim[1], dim[2], dim[3], (0.12 + 0.12 * z) * alpha
        end
    end
    love.graphics.setPointSize(1.8 * love.graphics.getDPIScale())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.points(verts)

    -- outline + orbit rings
    love.graphics.setLineWidth(1)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.25 * alpha)
    love.graphics.circle("line", cx, cy, R, 160)
    for k = 1, 2 do
        local tilt = k == 1 and 0.28 or -0.5
        local rr = R * (1.18 + k * 0.1)
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.rotate(tilt)
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.12 * alpha)
        love.graphics.ellipse("line", 0, 0, rr, rr * 0.22, 140)
        local a = intro.t * (0.6 + k * 0.25) + k
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.9 * alpha)
        love.graphics.circle("fill", math.cos(a) * rr, math.sin(a) * rr * 0.22, 2.4)
        love.graphics.pop()
    end

    -- arcs
    for _, arc in ipairs(intro.arcs) do
        local age = (intro.t - arc.t0) / arc.len
        if age < 1.6 then
            local head = math.min(1, age)
            local tail = math.max(0, age - 0.6)
            local pts = {}
            local ax, ay, az = arc.a[1], arc.a[2], arc.a[3]
            local bx, by, bz = arc.b[1], arc.b[2], arc.b[3]
            local N = 28
            for s = math.floor(tail * N), math.floor(head * N) do
                local u = s / N
                local px, py, pz = ax + (bx - ax) * u, ay + (by - ay) * u, az + (bz - az) * u
                local len = math.sqrt(px * px + py * py + pz * pz)
                local lift = (1 + 0.28 * math.sin(math.pi * u)) / math.max(0.001, len)
                local x, y, z = rot({ px * lift, py * lift, pz * lift })
                if z > -0.1 then
                    pts[#pts + 1] = cx + x * R
                    pts[#pts + 1] = cy - y * R
                end
            end
            local fade = 1 - math.max(0, age - 1) / 0.6
            if #pts >= 4 then
                love.graphics.setColor(acc[1], acc[2], acc[3], 0.7 * fade * alpha)
                love.graphics.setLineWidth(1.2)
                love.graphics.line(pts)
                local white = util.palette.white
                love.graphics.setColor(white[1], white[2], white[3], fade * alpha)
                love.graphics.circle("fill", pts[#pts - 1], pts[#pts], 2)
            end
            -- ping at the target
            if age >= 1 then
                local x, y, z = rot(arc.b)
                if z > 0 then
                    local pr = (age - 1) / 0.6
                    love.graphics.setColor(acc[1], acc[2], acc[3], (1 - pr) * alpha)
                    love.graphics.circle("line", cx + x * R, cy - y * R, 2 + pr * 14)
                end
            end
        end
    end
end

-- drawing ---------------------------------------------------------------------

local function decode_text(text, t0, dur)
    local chars = util.chars(text)
    local out = {}
    local p = (intro.t - t0) / dur
    if p <= 0 then return "" end
    for i, ch in ipairs(chars) do
        local reveal = (i - 1) / #chars
        if p >= reveal + 0.25 or ch == " " then
            out[i] = ch
        elseif p >= reveal - 0.1 then
            out[i] = util.GLYPHS[(i * 31 + math.floor(intro.t * 30)) % #util.GLYPHS + 1]
        else
            out[i] = " "
        end
    end
    return table.concat(out)
end

function intro.draw()
    if not intro.active then return end
    local W, H = love.graphics.getDimensions()
    local t = intro.t
    local ex = intro.exit_t and util.clamp(intro.exit_t / EXIT_LEN, 0, 1) or 0
    local fade = 1 - util.ease_out(ex)

    -- backdrop (fades to reveal the dashboard)
    local bg = util.palette.bg
    love.graphics.setColor(bg[1], bg[2], bg[3], fade)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- CRT power-on line
    if t < 0.7 then
        local p = util.clamp(t / 0.35, 0, 1)
        local acc = util.palette.white
        love.graphics.setColor(acc[1], acc[2], acc[3], 1 - util.clamp((t - 0.35) / 0.35, 0, 1))
        love.graphics.rectangle("fill", W / 2 - W / 2 * p, H / 2 - 1, W * p, 2)
    end

    local cx, cy = W / 2, H * 0.45
    local R = math.min(W, H) * 0.34 * (1 + ex * 0.5)
    local galpha = util.clamp((t - 0.3) / 1.0, 0, 1) * fade
    if galpha > 0 then draw_globe(cx, cy, R, galpha) end

    -- logo
    local px = math.floor(math.min(W * 0.62 / intro.ncols, 26))
    local lw, lh = intro.ncols * px, 5 * px
    local lx, ly = cx - lw / 2, cy - lh / 2
    -- dark plate behind the logo so it reads over the globe
    if t > LOGO_AT then
        local a = util.clamp((t - LOGO_AT) / 0.6, 0, 1) * 0.75 * fade
        love.graphics.setColor(bg[1], bg[2], bg[3], a)
        love.graphics.rectangle("fill", lx - px * 1.5, ly - px * 1.2, lw + px * 3, lh + px * 2.4 + 70, 6, 6)
    end
    local acc, white = util.palette.accent, util.palette.white
    local shimmer = ((t - IMPACT) * 34) % (intro.ncols + 50) - 12
    for _, p in ipairs(intro.pixels) do
        local k = util.clamp((t - p.delay) / p.dur, 0, 1)
        if k > 0 then
            local e = ease_out_back(k)
            local tx, ty = lx + (p.c - 1) * px, ly + (p.r - 1) * px
            local sx = cx + math.cos(p.sa) * W * p.sd
            local sy = cy + math.sin(p.sa) * H * p.sd
            local x = sx + (tx - sx) * e
            local y = sy + (ty - sy) * e
            if ex > 0 then
                local d = util.ease_out(ex)
                x = x + (tx - cx + p.ex * 120) * d * 2.2
                y = y + (ty - cy + p.ey * 120) * d * 2.2
            end
            local size = (px - 2) * (0.3 + 0.7 * k)
            local c
            if t < IMPACT then
                c = util.mix(white, acc, k)
            else
                local sh = math.max(0, 1 - math.abs(p.c - shimmer) / 5) * 0.6
                local hit = util.clamp(1 - (t - IMPACT) / 0.5, 0, 1)
                c = util.mix(acc, white, math.max(sh, hit))
            end
            love.graphics.setColor(c[1], c[2], c[3], fade)
            if k < 1 then
                love.graphics.push()
                love.graphics.translate(x + size / 2, y + size / 2)
                love.graphics.rotate(p.spin * (1 - k))
                love.graphics.rectangle("fill", -size / 2, -size / 2, size, size)
                love.graphics.pop()
            else
                love.graphics.rectangle("fill", x, y, size, size)
            end
        end
    end

    -- shockwave
    if intro.shock then
        local s = (t - intro.shock) / 0.9
        if s < 1 then
            love.graphics.setLineWidth(2 * (1 - s) + 0.5)
            love.graphics.setColor(acc[1], acc[2], acc[3], (1 - s) * fade)
            love.graphics.circle("line", cx, cy, 20 + s * math.max(W, H) * 0.7, 120)
            love.graphics.setColor(white[1], white[2], white[3], (1 - s) * 0.5 * fade)
            love.graphics.circle("line", cx, cy, 10 + s * math.max(W, H) * 0.45, 120)
        end
    end

    -- subtitle
    local fs, fm = intro.fonts.small, intro.fonts.mid
    local sub_y = ly + lh + px * 0.9
    if t > IMPACT + 0.15 then
        love.graphics.setFont(fm)
        local s = decode_text("T E R M I N A L", IMPACT + 0.15, 0.7)
        love.graphics.setColor(white[1], white[2], white[3], fade)
        love.graphics.print(s, cx - fm:getWidth("T E R M I N A L") / 2, sub_y)
        love.graphics.setFont(fs)
        local s2 = decode_text("// covert operations console  v2.0", IMPACT + 0.5, 0.8)
        local d = util.palette.dim
        love.graphics.setColor(d[1], d[2], d[3], fade)
        love.graphics.print(s2, cx - fs:getWidth("// covert operations console  v2.0") / 2, sub_y + 24)
    end

    -- loading bar + status
    local bar_y = sub_y + 62
    if t > LOAD_AT - 0.2 then
        local bw = math.min(lw, 460)
        local bx = cx - bw / 2
        local p = util.clamp((t - LOAD_AT) / LOAD_LEN, 0, 1)
        p = util.clamp(p - math.sin(p * math.pi * 5) / (math.pi * 5) * 0.8, 0, 1)
        local faint = util.palette.faint
        love.graphics.setColor(faint[1], faint[2], faint[3], fade)
        love.graphics.rectangle("fill", bx, bar_y, bw, 2)
        love.graphics.setColor(acc[1], acc[2], acc[3], fade)
        love.graphics.rectangle("fill", bx, bar_y, bw * p, 2)
        love.graphics.setColor(white[1], white[2], white[3], fade)
        love.graphics.rectangle("fill", bx + bw * p - 3, bar_y - 1, 3, 4)
        love.graphics.setFont(fs)
        local pct = ("%3d%%"):format(math.floor(p * 100))
        love.graphics.print(pct, bx + bw - fs:getWidth(pct), bar_y + 10)
        local si = util.clamp(math.floor((t - LOAD_AT) / (LOAD_LEN / #intro.status)) + 1, 1, #intro.status)
        local label = t >= READY and "ready" or intro.status[si]
        local t0 = t >= READY and READY or (LOAD_AT + (si - 1) * LOAD_LEN / #intro.status)
        local txt = decode_text(label, t0, 0.3)
        local tc = t >= READY and acc or util.palette.text
        love.graphics.setColor(tc[1], tc[2], tc[3], fade)
        love.graphics.print((t >= READY and "■ " or "› ") .. txt, bx, bar_y + 10)
    end

    if t > READY + 0.4 and not intro.exit_t then
        local a = 0.35 + 0.35 * math.sin((t - READY) * 4)
        love.graphics.setFont(fs)
        local s = "[ press any key ]"
        love.graphics.setColor(white[1], white[2], white[3], a)
        love.graphics.print(s, cx - fs:getWidth(s) / 2, H - 60)
    end

    -- corner readouts
    if t > 0.5 then
        local d = util.palette.dim
        love.graphics.setFont(fs)
        love.graphics.setColor(d[1], d[2], d[3], fade * util.clamp((t - 0.5) * 2, 0, 1))
        love.graphics.print("QRAWLLER//BOOT", 24, 20)
        love.graphics.print(os.date("%Y-%m-%d  %H:%M:%S"), W - 24 - fs:getWidth("0000-00-00  00:00:00"), 20)
        love.graphics.print(("node %s   ·   lat %.2f lon %.2f"):format(intro.node, math.sin(t) * 60, math.cos(t * 0.7) * 170), 24, H - 32)
        local fr = ("frame %06d"):format(math.floor(t * 60))
        love.graphics.print(fr, W - 24 - fs:getWidth(fr), H - 32)
    end
end

return intro
