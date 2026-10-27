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
local intro = require("src.intro")
local markers = require("src.markers")

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

    sound.load(cfg.sound, cfg.volume, cfg.ambient)
    fx.init(cfg)
    local count = commands.load()
    markers.load()
    T.init(cfg, commands)
    T.history = load_history()
    T.api = make_api(T)
    ui.init(T, cfg)
    T.api.ui = ui
    T.before_text = ui.draw
    T.after_text = ui.draw_overlay
    ui.layout()
    make_icon()

    local function start_terminal()
        T.start_task(function()
            boot.welcome(T.api, commands.errors)
            for _, e in ipairs(ui.errors) do T.api.print("{warn}! {}" .. e:gsub("{", "{{"), "dim") end
            for _, line in ipairs(cfg.autorun or {}) do T.api.run(line) end
        end, "boot")
    end

    if cfg.boot ~= false and not love.keyboard.isDown("lshift", "rshift") then
        intro.start({ commands = count, markers = #markers.list }, start_terminal)
    else
        sound.ambient(true, 0.35)
        start_terminal()
    end
end

function love.update(dt)
    dt = math.min(dt, 1 / 20)
    fx.update(dt)
    if intro.active then
        intro.update(dt)
        -- the dashboard slides in while the intro fades out
        if intro.exit_t and not ui.revealed then
            ui.revealed = true
            ui.born = T.time
        end
    end
    ui.update(dt)
    T.update(dt)
end

function love.draw()
    if intro.active then
        fx.render(function()
            if intro.exit_t then T.draw_text() end
            intro.draw()
        end, T.cursor_x, T.cursor_y, T.time)
    else
        T.draw()
    end
end

function love.textinput(text)
    if intro.active then return end
    if ui.textinput(text) then return end
    T.textinput(text)
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        return
    end
    if intro.active then
        intro.skip()
        return
    end
    if key == "f2" then
        ui.show_panels = not ui.show_panels
        return
    end
    if key == "f3" and not ui.focus then
        -- cycle the tabbed panel (MAP / FILES)
        local tabs = ui.tabs()
        for i, w in ipairs(tabs) do
            if w.tab == ui.active_tab then ui.show_tab(tabs[i % #tabs + 1].tab); break end
        end
        return
    end
    if ui.keypressed(key) then return end
    T.keypressed(key)
end

function love.wheelmoved(x, y)
    if not ui.wheelmoved(x, y) then T.wheelmoved(x, y) end
end

function love.mousepressed(x, y, button)
    if intro.active then
        intro.skip()
        return
    end
    ui.mousepressed(x, y, button)
end

function love.quit()
    if markers.dirty_at then markers.save() end
    if require("src.board").dirty_at then require("src.board").save() end
    require("src.vault").flush(true)
end

function love.resize()
    T.resize()
    ui.layout()
end

function love.filedropped(file)
    if intro.active then return end
    ui.filedropped(file)
end

function love.directorydropped(path)
    if intro.active then return end
    ui.directorydropped(path)
end
