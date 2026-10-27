-- Start-up animation. Any key skips straight to the welcome screen.
local boot = {}

function boot.intro(t, count)
    local os_name = love.system.getOS()
    local cores = love.system.getProcessorCount()

    t.wait(0.25)
    t.type("{dim}qrawller core{} {white}1.0.0{}   {dim}·{}   " .. os_name:lower() .. "   {dim}·{}   " .. cores .. " threads", "text", 160)
    t.wait(0.15)
    local steps = {
        { "mounting virtual filesystem", 0.18 },
        { "starting render pipeline", 0.22 },
        { "seeding entropy pool", 0.16 },
        { "loading " .. count .. " command modules", 0.25 },
    }
    for _, s in ipairs(steps) do
        t.print("{accent}▸{} {dim}" .. t.pad(s[1], 40, " ") .. "{}{accent}ok{}")
        t.sound("tick", { pitch = 1.4 })
        t.wait(s[2])
    end
    t.progress("opening secure channel", 0.9, { label_width = 24 })
    t.wait(0.25)
    t.clear()
    t.wait(0.3)
end

function boot.welcome(t, errors)
    local major, minor, rev = love.getVersion()
    t.print("")
    t.banner("QRAWLLER")
    t.print("")
    t.decode("terminal  ·  v1.0  ·  engine " .. major .. "." .. minor .. "." .. rev, "dim", 0.7)
    t.print("")
    t.type("type {accent}help{} to see what i can do.", "text", 90)
    for _, e in ipairs(errors) do
        t.print("{warn}! {}" .. e:gsub("{", "{{"), "dim")
    end
    t.print("")
    t.sound("ok", { volume = 0.6 })
end

return boot
