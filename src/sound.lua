-- Every sound is synthesised at start-up, so there are no audio files to ship.
local sound = { enabled = true, volume = 0.5, sources = {} }

local RATE = 44100

local function make(duration, fn)
    local n = math.floor(duration * RATE)
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 0, n - 1 do
        local t = i / RATE
        local v = fn(t, t / duration)
        data:setSample(i, math.max(-1, math.min(1, v)))
    end
    return data
end

local function sine(f, t) return math.sin(2 * math.pi * f * t) end

local defs = {
    -- soft mechanical tick
    key = function()
        local lp = 0
        return make(0.045, function(t, p)
            local noise = math.random() * 2 - 1
            lp = lp + (noise - lp) * 0.35
            local env = math.exp(-t * 140)
            return (lp * 0.55 + sine(1800, t) * 0.25 * math.exp(-t * 300)) * env
        end)
    end,
    -- deeper thock for Enter
    enter = function()
        local lp = 0
        return make(0.12, function(t, p)
            local noise = math.random() * 2 - 1
            lp = lp + (noise - lp) * 0.15
            local env = math.exp(-t * 45)
            return (lp * 0.6 + sine(140 - 60 * p, t) * 0.7) * env
        end)
    end,
    back = function()
        local lp = 0
        return make(0.035, function(t)
            local noise = math.random() * 2 - 1
            lp = lp + (noise - lp) * 0.22
            return lp * 0.5 * math.exp(-t * 170)
        end)
    end,
    -- tiny blip used while text is being typed out
    tick = function()
        return make(0.018, function(t)
            return sine(2400, t) * 0.18 * math.exp(-t * 260)
        end)
    end,
    beep = function()
        return make(0.09, function(t, p)
            return sine(880, t) * 0.35 * (1 - p) ^ 2
        end)
    end,
    ok = function()
        return make(0.42, function(t)
            local a = sine(660, t) * math.exp(-t * 9)
            local b = t > 0.09 and sine(990, t) * math.exp(-(t - 0.09) * 7) or 0
            local c = t > 0.18 and sine(1320, t) * math.exp(-(t - 0.18) * 6) or 0
            return (a + b + c) * 0.22
        end)
    end,
    err = function()
        return make(0.32, function(t, p)
            local s = (sine(110, t) > 0 and 1 or -1) * 0.18 + sine(55, t) * 0.25
            return s * (1 - p) ^ 1.5
        end)
    end,
    whoosh = function()
        local lp = 0
        return make(0.5, function(t, p)
            local noise = math.random() * 2 - 1
            local k = 0.02 + 0.25 * p
            lp = lp + (noise - lp) * k
            return lp * math.sin(math.pi * p) * 0.7
        end)
    end,
    glitch = function()
        return make(0.22, function(t, p)
            local step = math.floor(t * 90)
            local f = 200 + (step * 7919 % 1400)
            return ((sine(f, t) > 0) and 0.16 or -0.16) * (1 - p)
        end)
    end,
}

function sound.load(enabled, volume)
    sound.enabled = enabled ~= false
    sound.volume = volume or 0.5
    local ok = pcall(function()
        for name, def in pairs(defs) do
            local data = def()
            -- a small pool per sound so fast typing never cuts itself off
            local pool = {}
            for i = 1, 6 do pool[i] = love.audio.newSource(data, "static") end
            sound.sources[name] = { pool = pool, i = 1 }
        end
    end)
    if not ok then sound.sources = {} end
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

return sound
