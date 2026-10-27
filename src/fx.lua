-- Visual effects: soft glow, rippling dot grid, sparks, shake, flash, glitch, matrix rain.
local util = require("src.util")

local fx = {
    shake = 0,
    flash_a = 0,
    flash_color = { 1, 1, 1 },
    glitch_t = 0,
    glitch_amt = 0,
    ripples = {},
    particles = {},
    matrix = { on = false, alpha = 0, cols = {} },
    opts = {},
}

local BLUR = [[
extern vec2 dir;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec4 s = Texel(tex, uv) * 0.227027;
    s += Texel(tex, uv + dir * 1.3846) * 0.316216;
    s += Texel(tex, uv - dir * 1.3846) * 0.316216;
    s += Texel(tex, uv + dir * 3.2308) * 0.070270;
    s += Texel(tex, uv - dir * 3.2308) * 0.070270;
    return s * color;
}
]]

local COMPOSITE = [[
extern Image glowTex;
extern number glowAmt;
extern number time;
extern number glitch;
float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec2 p = uv;
    if (glitch > 0.0) {
        float band = floor(uv.y * 28.0);
        float r = rand(vec2(band, floor(time * 24.0)));
        if (r < glitch * 0.45) p.x += (rand(vec2(band, floor(time * 40.0))) - 0.5) * 0.09 * glitch;
    }
    float split = glitch * 0.007 + 0.0006;
    vec3 c;
    c.r = Texel(tex, p + vec2(split, 0.0)).r;
    c.g = Texel(tex, p).g;
    c.b = Texel(tex, p - vec2(split, 0.0)).b;
    c += Texel(glowTex, p).rgb * glowAmt;
    vec2 d = uv - 0.5;
    c *= 1.0 - dot(d, d) * 0.85;
    c += (rand(sc + fract(time)) - 0.5) * 0.018;
    return vec4(c, 1.0) * color;
}
]]

function fx.init(opts)
    fx.opts = opts
    fx.blur = love.graphics.newShader(BLUR)
    fx.composite = love.graphics.newShader(COMPOSITE)
    fx.resize(love.graphics.getDimensions())
end

function fx.resize(w, h)
    fx.w, fx.h = w, h
    fx.text_canvas = love.graphics.newCanvas(w, h)
    fx.scene = love.graphics.newCanvas(w, h)
    local gw, gh = math.max(1, math.floor(w / 3)), math.max(1, math.floor(h / 3))
    fx.glow_a = love.graphics.newCanvas(gw, gh)
    fx.glow_b = love.graphics.newCanvas(gw, gh)
    fx.glow_a:setFilter("linear", "linear")
    fx.glow_b:setFilter("linear", "linear")
    fx.build_vignette()
    fx.matrix.cols = {}
end

-- soft radial light behind the text
function fx.build_vignette()
    local size = 64
    local data = love.image.newImageData(size, size)
    local bg, bg2 = util.palette.bg, util.palette.bg2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local dx, dy = (x / (size - 1) - 0.5) * 2, (y / (size - 1) - 0.42) * 2
            local t = util.clamp(1 - math.sqrt(dx * dx * 0.7 + dy * dy), 0, 1)
            local c = util.mix(bg, bg2, t * t)
            data:setPixel(x, y, c[1], c[2], c[3], 1)
        end
    end
    fx.backdrop = love.graphics.newImage(data)
    fx.backdrop:setFilter("linear", "linear")
end

-- triggers -------------------------------------------------------------------

function fx.do_shake(amount)
    if fx.opts.screen_shake == false then return end
    fx.shake = math.max(fx.shake, amount or 4)
end

function fx.flash(color, alpha)
    fx.flash_color = util.color(color or "accent")
    fx.flash_a = alpha or 0.25
end

function fx.glitch(duration, amount)
    fx.glitch_t = math.max(fx.glitch_t, duration or 0.35)
    fx.glitch_amt = amount or 1
end

function fx.ripple(x, y, strength)
    fx.ripples[#fx.ripples + 1] = { x = x, y = y, t = 0, s = strength or 1 }
    if #fx.ripples > 8 then table.remove(fx.ripples, 1) end
end

function fx.sparks(x, y, n, color, spread)
    if fx.opts.particles == false then return end
    for _ = 1, n or 3 do
        local a = math.random() * math.pi * 2
        local sp = (spread or 60) * (0.4 + math.random())
        fx.particles[#fx.particles + 1] = {
            x = x, y = y,
            vx = math.cos(a) * sp, vy = math.sin(a) * sp - 20,
            life = 0, max = 0.35 + math.random() * 0.35,
            size = 1 + math.random() * 1.6,
            color = color or "accent",
        }
    end
end

-- update ---------------------------------------------------------------------

function fx.update(dt)
    fx.shake = math.max(0, fx.shake - dt * 30)
    fx.flash_a = math.max(0, fx.flash_a - dt * 1.6)
    fx.glitch_t = math.max(0, fx.glitch_t - dt)

    for i = #fx.ripples, 1, -1 do
        local r = fx.ripples[i]
        r.t = r.t + dt
        if r.t > 2.2 then table.remove(fx.ripples, i) end
    end

    for i = #fx.particles, 1, -1 do
        local p = fx.particles[i]
        p.life = p.life + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * (1 - dt * 4)
        p.vy = p.vy * (1 - dt * 4) + 40 * dt
        if p.life > p.max then table.remove(fx.particles, i) end
    end

    local m = fx.matrix
    m.alpha = util.clamp(m.alpha + (m.on and dt * 2 or -dt * 3), 0, 1)
    if m.alpha > 0 then fx.update_matrix(dt) end
end

-- matrix rain ------------------------------------------------------------------

function fx.update_matrix(dt)
    local m = fx.matrix
    local cw, lh = fx.cell_w or 9, fx.cell_h or 20
    local ncols = math.floor(fx.w / cw)
    local nrows = math.floor(fx.h / lh) + 2
    m.nrows = nrows
    for c = 1, ncols do
        local col = m.cols[c]
        if not col then
            col = { y = -math.random() * nrows, speed = 6 + math.random() * 22, len = math.random(6, 26), glyphs = {} }
            m.cols[c] = col
        end
        col.y = col.y + col.speed * dt
        if col.y - col.len > nrows then
            col.y = -math.random() * 10
            col.speed = 6 + math.random() * 22
            col.len = math.random(6, 26)
        end
        if math.random() < dt * 12 then
            col.glyphs[math.random(1, nrows)] = util.glyph()
        end
    end
end

function fx.draw_matrix(font)
    local m = fx.matrix
    if m.alpha <= 0 then return end
    local cw, lh = fx.cell_w or 9, fx.cell_h or 20
    love.graphics.setFont(font)
    local acc, white = util.palette.accent, util.palette.white
    for c, col in pairs(m.cols) do
        local head = math.floor(col.y)
        for k = 0, col.len do
            local row = head - k
            if row >= 0 and row < (m.nrows or 0) then
                local g = col.glyphs[row]
                if not g then
                    g = util.glyph()
                    col.glyphs[row] = g
                end
                local a = (1 - k / col.len) ^ 1.6 * m.alpha
                if k == 0 then
                    love.graphics.setColor(white[1], white[2], white[3], m.alpha)
                else
                    love.graphics.setColor(acc[1], acc[2], acc[3], a * 0.8)
                end
                love.graphics.print(g, (c - 1) * cw, row * lh)
            end
        end
    end
end

-- drawing ----------------------------------------------------------------------

function fx.draw_grid(cursor_x, cursor_y, time)
    if fx.opts.background_grid == false then return end
    local gap = 26
    local pts = {}
    local f = util.palette.faint
    local acc = util.palette.accent
    local ox = (fx.w % gap) / 2
    local oy = (fx.h % gap) / 2
    for y = oy, fx.h, gap do
        for x = ox, fx.w, gap do
            local b = 0
            for _, r in ipairs(fx.ripples) do
                local d = math.sqrt((x - r.x) ^ 2 + (y - r.y) ^ 2)
                local front = r.t * 520
                local w = d - front
                b = b + math.exp(-(w * w) / 1800) * (1 - r.t / 2.2) * r.s
            end
            local dc = math.sqrt((x - cursor_x) ^ 2 + (y - cursor_y) ^ 2)
            b = b + math.max(0, 1 - dc / 160) * 0.35
            b = math.min(b, 1)
            local c = util.mix(f, acc, b)
            pts[#pts + 1] = { x, y, c[1], c[2], c[3], 0.55 + 0.45 * b }
        end
    end
    love.graphics.setPointSize(1.6 * love.graphics.getDPIScale())
    love.graphics.points(pts)
end

function fx.draw_particles()
    for _, p in ipairs(fx.particles) do
        local c = util.color(p.color)
        local a = 1 - p.life / p.max
        love.graphics.setColor(c[1], c[2], c[3], a)
        love.graphics.rectangle("fill", p.x - p.size / 2, p.y - p.size / 2, p.size, p.size)
    end
end

function fx.shake_offset()
    if fx.shake <= 0 then return 0, 0 end
    return (math.random() - 0.5) * fx.shake, (math.random() - 0.5) * fx.shake
end

-- Draws the whole frame. draw_text renders into a transparent canvas that is
-- also blurred to create the glow.
function fx.render(draw_text, cursor_x, cursor_y, time)
    local w, h = fx.w, fx.h

    love.graphics.setCanvas(fx.text_canvas)
    love.graphics.clear(0, 0, 0, 0)
    local sx, sy = fx.shake_offset()
    love.graphics.push()
    love.graphics.translate(sx, sy)
    draw_text()
    fx.draw_particles()
    love.graphics.pop()

    local glow = fx.opts.glow or 0.5
    if glow > 0 then
        local gw, gh = fx.glow_a:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setCanvas(fx.glow_a)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.draw(fx.text_canvas, 0, 0, 0, gw / w, gh / h)
        for pass = 1, 2 do
            love.graphics.setShader(fx.blur)
            fx.blur:send("dir", { pass / gw, 0 })
            love.graphics.setCanvas(fx.glow_b)
            love.graphics.clear(0, 0, 0, 0)
            love.graphics.draw(fx.glow_a)
            fx.blur:send("dir", { 0, pass / gh })
            love.graphics.setCanvas(fx.glow_a)
            love.graphics.clear(0, 0, 0, 0)
            love.graphics.draw(fx.glow_b)
        end
        love.graphics.setShader()
    end

    love.graphics.setCanvas(fx.scene)
    local bg = util.palette.bg
    love.graphics.clear(bg[1], bg[2], bg[3], 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(fx.backdrop, 0, 0, 0, w / fx.backdrop:getWidth(), h / fx.backdrop:getHeight())
    fx.draw_grid(cursor_x, cursor_y, time)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(fx.text_canvas)
    love.graphics.setBlendMode("alpha")
    if fx.flash_a > 0 then
        local c = fx.flash_color
        love.graphics.setColor(c[1], c[2], c[3], fx.flash_a)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    love.graphics.setCanvas()

    local g = 0
    if fx.glitch_t > 0 then g = fx.glitch_amt * math.min(1, fx.glitch_t * 4) end
    love.graphics.setShader(fx.composite)
    fx.composite:send("glowTex", fx.glow_a)
    fx.composite:send("glowAmt", glow * 1.6)
    fx.composite:send("time", time)
    fx.composite:send("glitch", g)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(fx.scene)
    love.graphics.setShader()
end

return fx
