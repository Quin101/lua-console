-- Full-screen start-up sequence, built around the Qrawller logo.
-- Charge-up → a slamming impact (chromatic split, shockwaves, shake) →
-- a glowing, pulsing logo ringed by a rotating reticle with energy arcs →
-- an intense loading run → an explosive exit into the dashboard.
-- Any key or click skips ahead.
local util = require("src.util")
local fx = require("src.fx")
local sound = require("src.sound")
local world = require("src.world")

local intro = { active = false }

local CHARGE   = 0.30      -- logo begins forming (ghost + glitch)
local CHARGE2  = 1.35      -- second riser, tension peaks
local IMPACT   = 2.15      -- logo slams to full size
local LOAD_AT  = 2.95      -- loading bar starts
local LOAD_LEN = 2.8
local READY    = LOAD_AT + LOAD_LEN + 0.2
local AUTO_EXIT = READY + 3.0
local EXIT_LEN = 1.0

local function ease_out_back(t, s)
    s = s or 2.2
    return 1 + (s + 1) * (t - 1) ^ 3 + s * (t - 1) ^ 2
end

function intro.start(info, on_done)
    intro.active = true
    intro.t = 0
    intro.exit_t = nil
    intro.on_done = on_done
    intro.info = info or {}
    intro.events = {}
    intro.arcs = {}
    intro.bolts = {}
    intro.next_arc = 0.8
    intro.shock = nil
    intro.fonts = {
        small = love.graphics.newFont("assets/fonts/JetBrainsMono-Regular.ttf", 12),
        title = love.graphics.newFont("assets/fonts/JetBrainsMono-Bold.ttf", 30),
        mid = love.graphics.newFont("assets/fonts/JetBrainsMono-Bold.ttf", 14),
    }
    intro.node = util.hexstr(6)
    intro.globe = world.globe_points(2)
    intro.verts = {}
    for i = 1, #intro.globe do intro.verts[i] = { 0, 0, 0, 0, 0, 0 } end

    local ok, img = pcall(love.graphics.newImage, "assets/qrawller_logo.png")
    if ok then img:setFilter("linear", "linear"); intro.logo = img end

    intro.status = {
        "establishing encrypted uplink",
        "routing through " .. math.random(5, 9) .. " proxies",
        "spoofing hardware address",
        "decrypting world grid",
        "arming subsystems",
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

local function spawn_bolts(n, strength)
    for _ = 1, n or 6 do
        local a = math.random() * math.pi * 2
        intro.bolts[#intro.bolts + 1] = { a = a, t0 = intro.t, len = (strength or 1) * (0.7 + math.random() * 0.6), seed = math.random() * 100 }
    end
end

function intro.skip()
    if not intro.active or intro.exit_t then return end
    if intro.t < IMPACT then
        intro.t = math.max(intro.t, READY)
        for _, k in ipairs({ "riser", "charge2", "impact", "ready" }) do intro.events[k] = true end
        intro.shock = intro.t - 0.1
        sound.play("boom", { volume = 0.7 })
        fx.glitch(0.25, 0.6)
    end
    -- explosive exit
    intro.exit_t = 0
    local W, H = love.graphics.getDimensions()
    fx.do_shake(18)
    fx.flash("white", 0.4)
    fx.glitch(0.5, 1)
    sound.play("boom", { volume = 0.8, pitch = 1.1 })
    sound.play("whoosh", { volume = 0.9 })
    fx.sparks(W / 2, H * 0.44, 80, "accent", 320)
    spawn_bolts(12, 1.4)
end

function intro.update(dt)
    if not intro.active then return end
    intro.t = intro.t + dt
    local t = intro.t

    once("riser", CHARGE, function() sound.play("riser", { volume = 0.8 }) end)
    once("charge2", CHARGE2, function()
        sound.play("riser", { volume = 0.7, pitch = 1.3 })
        sound.play("glitch", { volume = 0.4 })
        fx.glitch(0.2, 0.5)
    end)
    once("impact", IMPACT, function()
        sound.play("boom")
        sound.play("glitch", { volume = 0.5, pitch = 0.7 })
        fx.glitch(0.5, 1)
        fx.do_shake(22)
        fx.flash("white", 0.45)
        intro.shock = t
        spawn_bolts(10, 1.3)
        local W, H = love.graphics.getDimensions()
        fx.sparks(W / 2, H * 0.44, 40, "accent", 200)
    end)
    once("aftershock", IMPACT + 0.12, function() fx.glitch(0.2, 0.6); fx.do_shake(8) end)
    once("ready", READY, function()
        sound.play("lock"); sound.play("ok", { volume = 0.7 })
        fx.flash("accent", 0.14); fx.do_shake(5)
        spawn_bolts(5, 0.9)
    end)

    -- charge-up ticks rising in pitch
    if t > CHARGE and t < IMPACT then
        intro.tick_acc = (intro.tick_acc or 0) + dt
        local rate = util.lerp(0.09, 0.02, (t - CHARGE) / (IMPACT - CHARGE))
        if intro.tick_acc > rate then
            intro.tick_acc = 0
            sound.play("tick", { pitch = 0.5 + (t - CHARGE) / (IMPACT - CHARGE) * 1.4, volume = 0.5 })
        end
    end
    -- a beep + tiny glitch per loading status
    local si = math.floor((t - LOAD_AT) / (LOAD_LEN / #intro.status)) + 1
    if t >= LOAD_AT and si ~= intro.last_status and si <= #intro.status then
        intro.last_status = si
        sound.play("beep", { pitch = 0.8 + si * 0.05, volume = 0.45 })
        fx.glitch(0.08, 0.25)
    end

    -- occasional energy arcs after impact
    if t > IMPACT and not intro.exit_t and math.random() < dt * 2.5 then spawn_bolts(1, 0.8) end
    for i = #intro.bolts, 1, -1 do if t - intro.bolts[i].t0 > intro.bolts[i].len then table.remove(intro.bolts, i) end end

    -- globe arcs
    intro.next_arc = intro.next_arc - dt
    if intro.next_arc <= 0 and not intro.exit_t then
        intro.next_arc = 0.22 + math.random() * 0.3
        local g = intro.globe
        intro.arcs[#intro.arcs + 1] = { a = g[math.random(#g)], b = g[math.random(#g)], t0 = t, len = 0.9 + math.random() * 0.6 }
        if #intro.arcs > 16 then table.remove(intro.arcs, 1) end
    end

    if t > AUTO_EXIT and not intro.exit_t then intro.skip() end
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
    -- spins fast during charge, eases to a steady drift
    local spin = intro.t < IMPACT and (intro.t * (2.2 - intro.t / IMPACT * 1.9)) or (IMPACT * 0.3 + intro.t * 0.22)
    local rot = rotator(spin + 2.2, 0.38)
    local acc, dim = util.palette.accent, util.palette.dim
    local verts = intro.verts
    for i, p in ipairs(intro.globe) do
        local x, y, z = rot(p)
        local v = verts[i]
        v[1], v[2] = cx + x * R, cy - y * R
        if z > 0 then
            v[3], v[4], v[5], v[6] = acc[1], acc[2], acc[3], (0.25 + 0.75 * z) * 0.8 * alpha
        else
            v[3], v[4], v[5], v[6] = dim[1], dim[2], dim[3], (0.12 + 0.12 * z) * alpha
        end
    end
    love.graphics.setPointSize(1.8 * love.graphics.getDPIScale())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.points(verts)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.22 * alpha)
    love.graphics.circle("line", cx, cy, R, 160)
    for k = 1, 2 do
        local rr = R * (1.18 + k * 0.1)
        love.graphics.push(); love.graphics.translate(cx, cy); love.graphics.rotate(k == 1 and 0.28 or -0.5)
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.1 * alpha)
        love.graphics.ellipse("line", 0, 0, rr, rr * 0.22, 140)
        local a = intro.t * (0.6 + k * 0.25) + k
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.9 * alpha)
        love.graphics.circle("fill", math.cos(a) * rr, math.sin(a) * rr * 0.22, 2.4)
        love.graphics.pop()
    end

    for _, arc in ipairs(intro.arcs) do
        local age = (intro.t - arc.t0) / arc.len
        if age < 1.6 then
            local head, tail = math.min(1, age), math.max(0, age - 0.6)
            local pts = {}
            local ax, ay, az, bx, by, bz = arc.a[1], arc.a[2], arc.a[3], arc.b[1], arc.b[2], arc.b[3]
            for s = math.floor(tail * 28), math.floor(head * 28) do
                local u = s / 28
                local px, py, pz = ax + (bx - ax) * u, ay + (by - ay) * u, az + (bz - az) * u
                local len = math.sqrt(px * px + py * py + pz * pz)
                local lift = (1 + 0.28 * math.sin(math.pi * u)) / math.max(0.001, len)
                local x, y, z = rot({ px * lift, py * lift, pz * lift })
                if z > -0.1 then pts[#pts + 1] = cx + x * R; pts[#pts + 1] = cy - y * R end
            end
            local fade = 1 - math.max(0, age - 1) / 0.6
            if #pts >= 4 then
                love.graphics.setColor(acc[1], acc[2], acc[3], 0.6 * fade * alpha)
                love.graphics.setLineWidth(1.2); love.graphics.line(pts)
            end
        end
    end
end

-- logo ------------------------------------------------------------------------

local function draw_logo_img(cx, cy, size, color, alpha, rot)
    local img = intro.logo
    if not img then return end
    local s = size / img:getWidth()
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.draw(img, cx, cy, rot or 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
end

-- draw jagged energy bolts radiating from the centre
local function draw_bolts(cx, cy, base_r, alpha)
    local acc, white = util.palette.accent, util.palette.white
    for _, b in ipairs(intro.bolts) do
        local age = (intro.t - b.t0) / b.len
        if age < 1 then
            local reach = base_r * (0.4 + age * 1.6) * b.len
            local segs = 7
            local pts = {}
            for s = 0, segs do
                local u = s / segs
                local r = u * reach
                local jitter = (s == 0 or s == segs) and 0 or (math.sin(b.seed + s * 2.3 + intro.t * 40) * reach * 0.08)
                local pa = b.a + jitter / math.max(1, r)
                pts[#pts + 1] = cx + math.cos(b.a) * r - math.sin(b.a) * (jitter)
                pts[#pts + 1] = cy + math.sin(b.a) * r + math.cos(b.a) * (jitter)
            end
            local f = (1 - age)
            love.graphics.setColor(white[1], white[2], white[3], f * 0.5 * alpha)
            love.graphics.setLineWidth(1.6); love.graphics.line(pts)
            love.graphics.setColor(acc[1], acc[2], acc[3], f * 0.9 * alpha)
            love.graphics.setLineWidth(0.8); love.graphics.line(pts)
        end
    end
end

-- rotating targeting reticle around the logo
local function draw_reticle(cx, cy, r, alpha, snap)
    local acc = util.palette.accent
    love.graphics.push(); love.graphics.translate(cx, cy)
    -- dashed outer ring (rotating)
    love.graphics.rotate(intro.t * 0.4)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.5 * alpha)
    love.graphics.setLineWidth(1)
    local dashes = 48
    for i = 0, dashes - 1 do
        if i % 2 == 0 then
            local a0 = i / dashes * math.pi * 2
            local a1 = (i + 0.7) / dashes * math.pi * 2
            love.graphics.line(math.cos(a0) * r, math.sin(a0) * r, math.cos(a1) * r, math.sin(a1) * r)
        end
    end
    love.graphics.rotate(-intro.t * 0.4)
    -- inner thin ring (counter-rotating) + ticks
    love.graphics.rotate(-intro.t * 0.6)
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.3 * alpha)
    love.graphics.circle("line", 0, 0, r * 0.82, 96)
    for i = 0, 23 do
        local a = i / 24 * math.pi * 2
        local rr = r * 0.82
        local len = (i % 6 == 0) and 7 or 3
        love.graphics.line(math.cos(a) * rr, math.sin(a) * rr, math.cos(a) * (rr + len), math.sin(a) * (rr + len))
    end
    love.graphics.pop()

    -- corner brackets snap in at impact
    local br = r * (1.08 - 0.3 * (1 - snap))
    local L = 26 * snap
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.9 * alpha * snap)
    love.graphics.setLineWidth(2)
    for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local x, y = cx + c[1] * br, cy + c[2] * br
        love.graphics.line(x, y, x - c[1] * L, y)
        love.graphics.line(x, y, x, y - c[2] * L)
    end

    -- scanner sweep line
    local sa = intro.t * 1.5
    love.graphics.setColor(acc[1], acc[2], acc[3], 0.25 * alpha)
    love.graphics.setLineWidth(1)
    love.graphics.line(cx, cy, cx + math.cos(sa) * r, cy + math.sin(sa) * r)
end

-- logo scale / alpha over time
local function logo_scale(t, ex)
    local base
    if t < CHARGE then base = 0
    elseif t < IMPACT then
        local p = (t - CHARGE) / (IMPACT - CHARGE)
        base = 0.3 + p * 0.55 + math.sin(t * 50) * 0.01 * p   -- grows + vibrates
    else
        local p = util.clamp((t - IMPACT) / 0.5, 0, 1)
        base = util.lerp(0.85, 1, ease_out_back(p, 3))         -- slam overshoot
        base = base + math.sin(t * 2.4) * 0.012                -- breathe
    end
    if ex > 0 then base = base * (1 + util.ease_out(ex) * 0.8) end
    return base
end

local function logo_alpha(t, ex)
    local a
    if t < CHARGE then a = 0
    elseif t < IMPACT then
        local p = (t - CHARGE) / (IMPACT - CHARGE)
        a = (0.12 + p * 0.45) * (0.55 + 0.45 * math.random())  -- flicker
    else a = 1 end
    return a * (1 - util.ease_out(ex))
end

-- drawing ---------------------------------------------------------------------

local function decode_text(text, t0, dur)
    local chars = util.chars(text)
    local out = {}
    local p = (intro.t - t0) / dur
    if p <= 0 then return "" end
    for i, ch in ipairs(chars) do
        local reveal = (i - 1) / #chars
        if p >= reveal + 0.25 or ch == " " then out[i] = ch
        elseif p >= reveal - 0.1 then out[i] = util.GLYPHS[(i * 31 + math.floor(intro.t * 30)) % #util.GLYPHS + 1]
        else out[i] = " " end
    end
    return table.concat(out)
end

function intro.draw()
    if not intro.active then return end
    local W, H = love.graphics.getDimensions()
    local t = intro.t
    local ex = intro.exit_t and util.clamp(intro.exit_t / EXIT_LEN, 0, 1) or 0
    local fade = 1 - util.ease_out(ex)
    local acc, white = util.palette.accent, util.palette.white

    local bg = util.palette.bg
    love.graphics.setColor(bg[1], bg[2], bg[3], fade)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- CRT power-on line
    if t < 0.7 then
        local p = util.clamp(t / 0.3, 0, 1)
        love.graphics.setColor(white[1], white[2], white[3], 1 - util.clamp((t - 0.3) / 0.4, 0, 1))
        love.graphics.rectangle("fill", W / 2 - W / 2 * p, H / 2 - 1.5, W * p, 3)
    end

    local cx, cy = W / 2, H * 0.44
    local impactP = util.clamp((t - IMPACT) / 0.6, 0, 1)
    local R = math.min(W, H) * 0.34 * (1 + ex * 0.5)
    local galpha = util.clamp((t - 0.3) / 1.0, 0, 1) * fade * (1 - impactP * 0.45)
    if galpha > 0 then draw_globe(cx, cy, R, galpha) end

    -- energy bolts (under the logo)
    if #intro.bolts > 0 then draw_bolts(cx, cy, math.min(W, H) * 0.3, fade) end

    -- the logo
    local size = math.min(W * 0.46, H * 0.56)
    local scale = logo_scale(t, ex)
    local la = logo_alpha(t, ex) * fade
    if la > 0 and intro.logo then
        local lsz = size * scale
        -- jitter during charge
        local jx, jy = 0, 0
        if t > CHARGE and t < IMPACT then
            local k = (t - CHARGE) / (IMPACT - CHARGE)
            jx = (math.random() - 0.5) * 10 * k
            jy = (math.random() - 0.5) * 10 * k
        end
        local lx, ly = cx + jx, cy + jy

        -- soft shape-matched bloom (additive, pulsing)
        love.graphics.setBlendMode("add")
        local pulse = 0.5 + 0.5 * math.sin(t * 2.4)
        local glow = (t >= IMPACT and (0.07 + 0.04 * pulse) or 0.05)
        for _, gs in ipairs({ 1.6, 2.4 }) do
            draw_logo_img(lx, ly, lsz * gs, acc, glow * la, 0)
        end

        -- chromatic split (strong at impact, decays; a little flicker during charge)
        local split = 0
        if t >= IMPACT then split = (1 - impactP) * 26 + 1.5
        elseif t > CHARGE then split = 4 + math.random() * 6 end
        if split > 1 then
            draw_logo_img(lx - split, ly, lsz, { 1, 0.12, 0.18 }, 0.5 * la, 0)
            draw_logo_img(lx + split, ly, lsz, { 0.2, 0.55, 1 }, 0.5 * la, 0)
        end
        love.graphics.setBlendMode("alpha")

        -- main logo (true colours); flash white at the moment of impact
        draw_logo_img(lx, ly, lsz, { 1, 1, 1 }, la, 0)
        if impactP < 1 and t >= IMPACT then
            love.graphics.setBlendMode("add")
            draw_logo_img(lx, ly, lsz, white, (1 - impactP) * 0.9 * la, 0)
            love.graphics.setBlendMode("alpha")
        end

        -- reticle once the logo is locking in
        if t > IMPACT - 0.1 then
            draw_reticle(cx, cy, lsz * 0.62, fade * util.clamp((t - IMPACT + 0.1) / 0.4, 0, 1), impactP)
        end
    end

    -- shockwaves
    if intro.shock then
        for ring = 0, 2 do
            local s = (t - intro.shock - ring * 0.08) / 0.85
            if s > 0 and s < 1 then
                love.graphics.setLineWidth((2.5 - ring) * (1 - s) + 0.5)
                local c = ring == 0 and white or acc
                love.graphics.setColor(c[1], c[2], c[3], (1 - s) * (ring == 0 and 0.6 or 0.4) * fade)
                love.graphics.circle("line", cx, cy, 20 + s * math.max(W, H) * (0.7 + ring * 0.1), 128)
            end
        end
    end

    -- title + subtitle under the logo
    local ft, fm, fs = intro.fonts.title, intro.fonts.mid, intro.fonts.small
    local base_y = cy + size * 0.52
    if t > IMPACT + 0.1 then
        love.graphics.setFont(ft)
        local s = decode_text("Q R A W L L E R", IMPACT + 0.1, 0.6)
        local col = util.mix(acc, white, 0.25 + 0.2 * math.sin(t * 3))
        love.graphics.setColor(col[1], col[2], col[3], fade)
        love.graphics.print(s, cx - ft:getWidth("Q R A W L L E R") / 2, base_y)
        love.graphics.setFont(fs)
        local s2 = decode_text("// COVERT OPERATIONS CONSOLE   v2.0", IMPACT + 0.4, 0.7)
        local d = util.palette.dim
        love.graphics.setColor(d[1], d[2], d[3], fade)
        love.graphics.print(s2, cx - fs:getWidth("// COVERT OPERATIONS CONSOLE   v2.0") / 2, base_y + 38)
    end

    -- loading bar + status
    local bar_y = base_y + 74
    if t > LOAD_AT - 0.2 then
        local bw = math.min(W * 0.4, 460)
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
        local tc = t >= READY and acc or util.palette.text
        love.graphics.setColor(tc[1], tc[2], tc[3], fade)
        love.graphics.print((t >= READY and "■ " or "› ") .. decode_text(label, t0, 0.3), bx, bar_y + 10)
    end

    if t > READY + 0.4 and not intro.exit_t then
        local a = 0.35 + 0.35 * math.sin((t - READY) * 4)
        love.graphics.setFont(fs)
        local s = "[ press any key ]"
        love.graphics.setColor(white[1], white[2], white[3], a)
        love.graphics.print(s, cx - fs:getWidth(s) / 2, H - 56)
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
