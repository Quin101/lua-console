-- Live system graphs. FPS and Lua memory are real; cpu/net are simulated.
local N = 60

local function push(list, v)
    list[#list + 1] = v
    if #list > N then table.remove(list, 1) end
end

return {
    title = "SYSTEM",
    order = 1,
    height = 112,

    load = function(w)
        w.cpu, w.net, w.fps, w.mem = {}, {}, {}, {}
        w.cpu_v, w.net_v = 0.3, 0.2
        w.acc = 0
        for _ = 1, N do push(w.cpu, 0); push(w.net, 0); push(w.fps, 0); push(w.mem, 0) end
    end,

    update = function(w, dt, ui)
        w.acc = w.acc + dt
        if w.acc < 0.1 then return end
        w.acc = 0
        local busy = ui.busy() and 0.35 or 0
        w.cpu_v = ui.util.clamp(w.cpu_v + (math.random() - 0.5) * 0.18 + (0.25 + busy - w.cpu_v) * 0.1, 0.03, 0.98)
        w.net_v = ui.util.clamp(w.net_v + (math.random() - 0.5) * 0.3 + (0.2 + busy * 1.4 - w.net_v) * 0.15, 0, 1)
        push(w.cpu, w.cpu_v)
        push(w.net, w.net_v)
        push(w.fps, love.timer.getFPS())
        push(w.mem, collectgarbage("count") / 1024)
    end,

    status = function(w)
        return os.date("%H:%M:%S")
    end,

    draw = function(w, ui, x, y, width, height)
        local colw = (width - 14) / 2
        local rowh = (height - 10) / 2
        local cells = {
            { "cpu", w.cpu, 1, ("%d%%"):format(w.cpu_v * 100), "accent" },
            { "net", w.net, 1, ("%.1f MB/s"):format(w.net_v * 12), "text" },
            { "fps", w.fps, 75, tostring(love.timer.getFPS()), "accent" },
            { "lua mem", w.mem, math.max(1, (w.mem[#w.mem] or 1) * 1.6), ("%.1f MB"):format(w.mem[#w.mem] or 0), "text" },
        }
        for i, c in ipairs(cells) do
            local cx = x + ((i - 1) % 2) * (colw + 14)
            local cy = y + math.floor((i - 1) / 2) * (rowh + 10)
            ui.text(c[1], cx, cy, "dim")
            local vf = ui.font_bold
            ui.text(c[4], cx + colw - vf:getWidth(c[4]), cy, "white", vf)
            ui.graph(c[2], cx, cy + 18, colw, rowh - 22, c[5], c[3])
            if ui.hover(cx, cy, colw, rowh) then ui.tooltip(c[1] .. "  " .. c[4]) end
        end
    end,
}
