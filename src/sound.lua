-- Every sound is synthesised at start-up, so there are no audio files to ship.
-- The palette is deliberately dark: low thumps, sub-bass hits, distortion and reverb tails.
local sound = { enabled = true, volume = 0.5, sources = {}, ambient_on = false }

local RATE = 44100
local pi2 = math.pi * 2
local sin, exp, rand, floor = math.sin, math.exp, math.random, math.floor

-- DSP helpers ------------------------------------------------------------------

local function render(duration, fn)
    local n = floor(duration * RATE)
    local buf = {}
    for i = 0, n - 1 do
        local t = i / RATE
        buf[i + 1] = fn(t, t / duration)
    end
    return buf
end

local function lowpass(k)
    local y = 0
    return function(x)
        y = y + (x - y) * k
        return y
    end
end

local function drive(buf, amount)
    local norm = math.tanh(amount)
    for i = 1, #buf do buf[i] = math.tanh(buf[i] * amount) / norm end
    return buf
end

-- small Freeverb-style reverb: parallel combs into series allpasses
local function reverb(buf, mix, size, tail)
    size = size or 0.84
    local extra = floor((tail or 0.6) * RATE)
    for _ = 1, extra do buf[#buf + 1] = 0 end
    local combs = { 1557, 1617, 1491, 1422, 1277, 1356 }
    local out = {}
    for i = 1, #buf do out[i] = 0 end
    for _, d in ipairs(combs) do
        local line, idx, lp = {}, 1, 0
        for i = 1, d do line[i] = 0 end
        for i = 1, #buf do
            local y = line[idx]
            lp = lp + (y - lp) * 0.45 -- damping
            line[idx] = buf[i] + lp * size
            idx = idx % d + 1
            out[i] = out[i] + y
        end
    end
    for _, d in ipairs({ 225, 556 }) do
        local line, idx = {}, 1
        for i = 1, d do line[i] = 0 end
        for i = 1, #out do
            local b = line[idx]
            local x = out[i]
            line[idx] = x + b * 0.5
            out[i] = b - x * 0.5
            idx = idx % d + 1
        end
    end
    for i = 1, #buf do buf[i] = buf[i] * (1 - mix) + out[i] * mix * 0.22 end
    return buf
end

local function to_data(buf, gain)
    local peak = 0.0001
    for i = 1, #buf do peak = math.max(peak, math.abs(buf[i])) end
    local g = (gain or 0.9) / peak
    local data = love.sound.newSoundData(#buf, RATE, 16, 1)
    for i = 1, #buf do data:setSample(i - 1, math.max(-1, math.min(1, buf[i] * g))) end
    return data
end

local function noise() return rand() * 2 - 1 end
local function saw(ph) return (ph % 1) * 2 - 1 end

-- sound designs ----------------------------------------------------------------

local defs = {
    -- muffled, heavy key thock
    key = function()
        local lp = lowpass(0.10)
        local b = render(0.07, function(t)
            local body = sin(pi2 * (170 - 600 * t) * t) * exp(-t * 110)
            local n = lp(noise()) * exp(-t * 70) * 1.6
            local click = noise() * exp(-t * 900) * 0.25
            return body * 0.8 + n + click
        end)
        return to_data(reverb(drive(b, 1.6), 0.12, 0.7, 0.15), 0.75)
    end,
    back = function()
        local lp = lowpass(0.07)
        local b = render(0.06, function(t)
            return sin(pi2 * 120 * t) * exp(-t * 120) * 0.7 + lp(noise()) * exp(-t * 90) * 1.4
        end)
        return to_data(drive(b, 1.4), 0.6)
    end,
    -- impact with a sub-bass drop
    enter = function()
        local lp = lowpass(0.05)
        local ph = 0
        local b = render(0.45, function(t)
            ph = ph + (95 * exp(-t * 6) + 38) / RATE
            local sub = sin(pi2 * ph) * exp(-t * 9)
            local n = lp(noise()) * exp(-t * 30) * 2
            return sub + n
        end)
        return to_data(reverb(drive(b, 2.2), 0.22, 0.8, 0.5), 0.85)
    end,
    -- faint ticking used by the typewriter
    tick = function()
        local lp = lowpass(0.3)
        local b = render(0.025, function(t)
            return sin(pi2 * 700 * t) * exp(-t * 300) * 0.6 + lp(noise()) * exp(-t * 400)
        end)
        return to_data(b, 0.35)
    end,
    -- low, detuned blip
    beep = function()
        local lp = lowpass(0.12)
        local b = render(0.16, function(t, p)
            local tone = saw(220 * t) + saw(221.7 * t) * 0.7 + sin(pi2 * 110 * t)
            return lp(tone) * exp(-t * 22)
        end)
        return to_data(reverb(drive(b, 1.5), 0.25, 0.8, 0.35), 0.6)
    end,
    -- ominous minor swell for successes
    ok = function()
        local lp = lowpass(0.06)
        local b = render(1.4, function(t, p)
            local env = math.min(1, t / 0.04) * exp(-t * 2.6)
            local chord = saw(110 * t) + saw(130.81 * t) * 0.8 + saw(164.81 * t) * 0.7 + saw(155.56 * t) * 0.25
            local sub = sin(pi2 * 55 * t) * 1.2
            return (lp(chord) * 0.8 + sub) * env
        end)
        return to_data(reverb(drive(b, 1.8), 0.4, 0.86, 1.0), 0.85)
    end,
    -- distorted growl
    err = function()
        local lp = lowpass(0.15)
        local b = render(0.5, function(t, p)
            local s = saw(55 * t) + saw(58.3 * t) + sin(pi2 * 27.5 * t) * 1.5
            local crunch = noise() * 0.3 * (sin(pi2 * 30 * t) > 0 and 1 or 0)
            return lp(s + crunch) * (1 - p) ^ 1.3
        end)
        return to_data(reverb(drive(b, 5), 0.18, 0.75, 0.3), 0.9)
    end,
    -- deep air movement
    whoosh = function()
        local lp = lowpass(0.04)
        local b = render(0.9, function(t, p)
            local env = math.sin(math.pi * p)
            return lp(noise()) * env * env * 3 + sin(pi2 * 45 * t) * env * 0.4
        end)
        return to_data(reverb(b, 0.3, 0.85, 0.5), 0.7)
    end,
    -- bit-crushed digital tearing
    glitch = function()
        local hold, held = 0, 0
        local b = render(0.3, function(t, p)
            local step = floor(t * 70)
            local f = 80 + (step * 7919 % 900)
            local v = (saw(f * t) + noise() * 0.4)
            hold = hold - 1
            if hold <= 0 then held = v; hold = 6 + (step % 5) * 4 end
            return floor(held * 4) / 4 * (1 - p)
        end)
        return to_data(drive(b, 3), 0.65)
    end,
    -- cinematic hit
    boom = function()
        local lp = lowpass(0.03)
        local ph = 0
        local b = render(2.0, function(t)
            ph = ph + (62 * exp(-t * 2.2) + 26) / RATE
            local sub = sin(pi2 * ph) * exp(-t * 2.4)
            local crack = lp(noise()) * exp(-t * 14) * 3
            local metal = sin(pi2 * 311 * t) * sin(pi2 * 437 * t) * exp(-t * 5) * 0.3
            return sub * 1.3 + crack + metal
        end)
        return to_data(reverb(drive(b, 2.5), 0.35, 0.88, 1.6), 1.0)
    end,
    -- tension riser
    riser = function()
        local lp = lowpass(0.02)
        local ph = 0
        local b = render(1.8, function(t, p)
            ph = ph + (60 + 520 * p * p) / RATE
            local tone = saw(ph) + saw(ph * 1.01)
            local n = noise() * (0.2 + p)
            local k = 0.02 + p * 0.2
            return (lp(tone + n) + (tone + n) * k * 0.2) * p ^ 2
        end)
        return to_data(reverb(drive(b, 2), 0.3, 0.8, 0.4), 0.7)
    end,
    -- dark bell for dropping a map marker
    place = function()
        local b = render(1.0, function(t)
            local env = exp(-t * 5)
            return (sin(pi2 * 196 * t) + sin(pi2 * 523.3 * t) * 0.5 * exp(-t * 8) + sin(pi2 * 277.2 * t) * 0.35) * env
                + sin(pi2 * 49 * t) * exp(-t * 10)
        end)
        return to_data(reverb(drive(b, 1.3), 0.4, 0.86, 1.0), 0.75)
    end,
    -- mechanical lock
    lock = function()
        local lp = lowpass(0.2)
        local b = render(0.25, function(t)
            local c1 = lp(noise()) * exp(-t * 200)
            local c2 = t > 0.08 and (noise() * exp(-(t - 0.08) * 160) * 0.8) or 0
            return c1 + c2 + sin(pi2 * 90 * t) * exp(-t * 25) * 0.8
        end)
        return to_data(reverb(drive(b, 2), 0.2, 0.7, 0.3), 0.7)
    end,
}

-- an 8 second seamless loop of low, slowly breathing drone
local function make_drone()
    local L = 8
    local X = 0.6 -- crossfade
    local lp = lowpass(0.01)
    local nlp = lowpass(0.004)
    local b = render(L + X, function(t)
        local lfo = 0.5 + 0.5 * sin(pi2 * t / L)
        local tone = saw(55 * t) + saw(55.125 * t) + saw(82.5 * t) * 0.5 + sin(pi2 * 27.5 * t) * 2
        local k = 0.004 + 0.012 * lfo
        local y = lp(tone) * (1 - k * 20) + tone * k
        local breath = nlp(noise()) * 6 * (0.4 + 0.6 * lfo)
        return y * 0.6 + breath
    end)
    local n = floor(L * RATE)
    local xn = floor(X * RATE)
    for i = 1, xn do
        local a = i / xn
        b[i] = b[i] * a + b[n + i] * (1 - a)
    end
    for i = #b, n + 1, -1 do b[i] = nil end
    return to_data(drive(b, 1.4), 0.5)
end

function sound.load(enabled, volume, ambient)
    sound.enabled = enabled ~= false
    sound.volume = volume or 0.5
    sound.ambient_wanted = ambient ~= false
    local ok, err = pcall(function()
        for name, def in pairs(defs) do
            local data = def()
            -- a small pool per sound so fast typing never cuts itself off
            local pool = {}
            for i = 1, 6 do pool[i] = love.audio.newSource(data, "static") end
            sound.sources[name] = { pool = pool, i = 1 }
        end
        sound.drone = love.audio.newSource(make_drone(), "static")
        sound.drone:setLooping(true)
    end)
    if not ok then
        print("sound disabled: " .. tostring(err))
        sound.sources = {}
        sound.drone = nil
    end
end

-- sound.play("key", { pitch = 1.1, volume = 0.6 })
function sound.play(name, opts)
    if not sound.enabled then return end
    local s = sound.sources[name]
    if not s then return end
    opts = opts or {}
    local src = s.pool[s.i]
    s.i = s.i % #s.pool + 1
    pcall(function()
        src:stop()
        src:setPitch(opts.pitch or 1)
        src:setVolume((opts.volume or 1) * sound.volume)
        src:play()
    end)
end

-- low background hum
function sound.ambient(on, volume)
    if not sound.drone then return end
    sound.ambient_on = on
    pcall(function()
        if on and sound.enabled and sound.ambient_wanted then
            sound.drone:setVolume((volume or 0.35) * sound.volume)
            if not sound.drone:isPlaying() then sound.drone:play() end
        else
            sound.drone:stop()
        end
    end)
end

function sound.set_enabled(on)
    sound.enabled = on
    sound.ambient(sound.ambient_on)
end

return sound
