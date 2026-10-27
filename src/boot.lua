-- Welcome text printed in the terminal once the intro has finished.
local markers = require("src.markers")

local boot = {}

function boot.welcome(t, errors)
    t.decode("session opened  ·  " .. os.date("%d %b %Y  %H:%M"), "dim", 0.6)
    t.print("")
    t.print("{accent}QRAWLLER{}  {dim}// covert operations console v2.0")
    local v, p = markers.count()
    t.print("{dim}map  {}" .. v .. " {dim}victims  ·  {}" .. p .. " {dim}places on file")
    t.print("")
    t.type("type {accent}help{} for commands, or drop markers on the map with {accent}◆ VICTIM{} / {white}○ PLACE{}.", "text", 120)
    for _, e in ipairs(errors or {}) do
        t.print("{warn}! {}" .. e:gsub("{", "{{"), "dim")
    end
    t.print("")
end

return boot
