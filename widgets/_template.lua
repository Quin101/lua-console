-- ─────────────────────────────────────────────────────────────────────────
--  HOW TO ADD A WIDGET (a panel on the right side of the screen)
--
--  1. Copy this file to a new name in widgets/, e.g. widgets/radar.lua
--     (files starting with "_" are ignored, so this template never loads)
--  2. Edit it, then type `reload` in the terminal.
--
--  The `ui` toolkit you get in draw():
--    ui.button(id, label, x, y, w, h, {tip = "..."})  -> true when clicked
--    ui.toggle(id, label, value, x, y, w)              -> new value
--    ui.graph(values, x, y, w, h, color, max)          line graph
--    ui.text(str, x, y, color)   ui.text_center(str, x, y, w, color)
--    ui.hover(x, y, w, h)        ui.clicked(x, y, w, h)
--    ui.tooltip("text")          show a tooltip at the mouse
--    ui.set_color(name, alpha)   then use love.graphics.* to draw anything
--    ui.run("hack target")       types + runs a command in the terminal
--    ui.print("text")            print straight into the terminal
--    ui.sound("beep")            ui.fx.sparks(x, y, n)  ui.fx.ripple(x, y)
--    ui.time()  ui.busy()  ui.mouse.x / ui.mouse.y
--  Colours: text dim accent white ok warn err info faint
--  Click a panel's title to collapse it.
-- ─────────────────────────────────────────────────────────────────────────

return {
    title = "EXAMPLE",
    order = 99,          -- lower = higher up the column
    height = 90,         -- pixels, or "fill" to take the remaining space

    load = function(w, ui)
        w.clicks = 0
    end,

    update = function(w, dt, ui)
        -- runs every frame, before draw
    end,

    draw = function(w, ui, x, y, width, height)
        ui.text("clicks: " .. w.clicks, x, y, "text")
        if ui.button("example_btn", "CLICK ME", x, y + 24, 120, 28, { tip = "does a thing" }) then
            w.clicks = w.clicks + 1
            ui.run("banner " .. w.clicks)
        end
    end,

    -- optional: text shown on the right of the title bar
    status = function(w, ui) return w.clicks .. " clicks" end,
}
