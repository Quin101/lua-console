--  Qrawller Terminal
--  Add commands by dropping a .lua file into commands/ (see commands/_template.lua).

local util = require("src.util")
local fx = require("src.fx")
local sound = require("src.sound")
local T = require("src.terminal")
local commands = require("src.commands")
local boot = require("src.boot")
local make_api = require("src.api")
local ui = require("src.ui")

local cfg

-- saved settings (theme, sound) -----------------------------------------------------

local function load_settings()
    local s = {}
    if love.filesystem.getInfo("settings.txt") then
        for line in love.filesystem.lines("settings.txt") do
            local k, v = line:match("^(%w+)=(.*)$")
            if k then s[k] = v end
        end
    end
    return s
end

local function save_settings(s)
    local out = {}
    for k, v in pairs(s) do out[#out + 1] = k .. "=" .. tostring(v) end
    love.filesystem.write("settings.txt", table.concat(out, "\n"))
end

local function load_history()
    local h = {}
    if love.filesystem.getInfo("history.txt") then
        for line in love.filesystem.lines("history.txt") do
            if line ~= "" then h[#h + 1] = line end
        end
    end
    return h
end

local function make_icon()
    local size = 64
    local canvas = love.graphics.newCanvas(size, size, { dpiscale = 1 })
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    local bg, acc = util.palette.bg, util.palette.accent
    love.graphics.setColor(bg[1] + 0.03, bg[2] + 0.03, bg[3] + 0.03, 1)
    love.graphics.rectangle("fill", 2, 2, size - 4, size - 4, 14, 14)
    love.graphics.setColor(acc[1], acc[2], acc[3], 1)
    love.graphics.setLineWidth(6)
    love.graphics.line(18, 18, 34, 32, 18, 46)
    love.graphics.rectangle("fill", 36, 42, 14, 5)
    love.graphics.setCanvas()
    pcall(love.window.setIcon, canvas:newImageData())
end

-- love callbacks ------------------------------------------------------------------

function love.load()
    math.randomseed(os.time())
    love.keyboard.setKeyRepeat(true)

    local ok, user = pcall(require, "config")
    cfg = ok and user or {}
    if not ok then print("config.lua: " .. tostring(user)) end

    local saved = load_settings()
    if saved.theme then cfg.theme = saved.theme end
    if saved.sound then cfg.sound = saved.sound == "true" end
    if not util.set_theme(cfg.theme or "red") then util.set_theme("red") end

    cfg.on_setting = function(k, v)
        saved[k] = v
        save_settings(saved)
    end
    cfg.on_history = function(h)
        local from = math.max(1, #h - 300)
        love.filesystem.write("history.txt", table.concat(h, "\n", from))
    end

    sound.load(cfg.sound, cfg.volume)
    fx.init(cfg)
    local count = commands.load()
    T.init(cfg, commands)
    T.history = load_history()
    T.api = make_api(T)
    ui.init(T, cfg)
    T.api.ui = ui
    T.before_text = ui.draw
    T.after_text = ui.draw_overlay
    ui.layout()
    make_icon()

    local function autorun()
        for _, line in ipairs(cfg.autorun or {}) do T.api.run(line) end
    end

    local skip = not cfg.boot or love.keyboard.isDown("lshift", "rshift")
    if skip then
        T.start_task(function() boot.welcome(T.api, commands.errors); autorun() end, "boot")
    else
        T.start_task(function()
            boot.intro(T.api, count)
            boot.welcome(T.api, commands.errors)
            autorun()
        end, "boot")
        T.booting = true
    end
end

function love.update(dt)
    dt = math.min(dt, 1 / 20)
    fx.update(dt)
    ui.update(dt)
    T.update(dt)
end

function love.draw()
    T.draw()
end

function love.textinput(text)
    T.textinput(text)
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        return
    end
    if key == "f2" then
        ui.show_panels = not ui.show_panels
        return
    end
    if T.booting then
        -- any key skips the boot sequence
        T.booting = false
        if T.task and T.task.name == "boot" then
            T.task = nil
            T.clear(false)
            T.start_task(function()
                boot.welcome(T.api, commands.errors)
                for _, line in ipairs(cfg.autorun or {}) do T.api.run(line) end
            end, "boot")
            return
        end
    end
    T.keypressed(key)
end

function love.wheelmoved(x, y)
    if not ui.wheelmoved(x, y) then T.wheelmoved(x, y) end
end

function love.mousepressed(x, y, button)
    ui.mousepressed(x, y, button)
end

function love.resize()
    T.resize()
    ui.layout()
end
