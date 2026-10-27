function love.conf(t)
    t.identity = "qrawller"          -- save folder name (%APPDATA%/LOVE/qrawller on Windows)
    t.version = "11.5"
    t.console = false

    t.window.title = "Qrawller Terminal"
    t.window.width = 1400
    t.window.height = 840
    t.window.minwidth = 640
    t.window.minheight = 400
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = true

    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.touch = false
end
