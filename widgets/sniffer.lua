-- Fake live packet capture. Click a packet to decrypt it in the terminal.
local PROTOS = { "TCP", "UDP", "TLS", "DNS", "HTTP", "SSH", "ICMP" }
local MAX = 40

local function packet(ui)
    local p = ui.util.pick(PROTOS)
    return {
        proto = p,
        src = ui.util.ip(),
        dst = "10.0." .. math.random(0, 9) .. "." .. math.random(2, 254),
        size = math.random(40, 1500),
        born = ui.time(),
        flagged = math.random() < 0.12,
        stamp = os.date("%M:%S"),
    }
end

return {
    title = "PACKETS",
    order = 3,
    height = 132,

    load = function(w)
        w.list = {}
        w.next = 0
        w.paused = false
        w.count = 0
    end,

    status = function(w)
        return (w.paused and "paused · " or "") .. w.count .. " captured"
    end,

    update = function(w, dt, ui)
        if w.paused then return end
        w.next = w.next - dt
        if w.next <= 0 then
            w.next = (ui.busy() and 0.06 or 0.18) + math.random() * 0.35
            table.insert(w.list, 1, packet(ui))
            w.count = w.count + 1
            if #w.list > MAX then table.remove(w.list) end
        end
    end,

    draw = function(w, ui, x, y, width, height)
        local rh = 18
        local rows = math.floor((height - 30) / rh)
        local now = ui.time()
        for i = 1, math.min(rows, #w.list) do
            local p = w.list[i]
            local age = now - p.born
            local slide = ui.util.ease_out(ui.util.clamp(age / 0.25, 0, 1))
            local ry = y + (i - 1) * rh - (1 - slide) * rh
            local hov = ui.hover(x, ry, width, rh)
            if hov then
                ui.set_color("accent", 0.1)
                love.graphics.rectangle("fill", x - 4, ry - 1, width + 8, rh, 3, 3)
                ui.tooltip((p.flagged and "suspicious · click to decrypt" or "click to trace source") .. "  ·  " .. p.size .. " bytes")
            end
            local fresh = ui.util.clamp(1 - age / 0.6, 0, 1)
            local a = (i == 1 and slide or 1) * (1 - (i / (rows + 2)) * 0.5)
            ui.text(p.stamp, x, ry, "dim", nil, a)
            ui.text(p.proto, x + 46, ry, p.flagged and "warn" or (fresh > 0 and "white" or "accent"), ui.font_bold, a)
            ui.text(p.src .. " → " .. p.dst, x + 94, ry, hov and "white" or "text", nil, a)
            local sz = p.size .. "b"
            ui.text(sz, x + width - ui.font:getWidth(sz), ry, "dim", nil, a)
            if hov and ui.clicked(x, ry, width, rh) then
                ui.run(p.flagged and "decrypt" or ("trace " .. p.src))
            end
        end
        local by = y + height - 24
        if ui.button("sn_pause", w.paused and "RESUME" or "PAUSE", x, by, 86, 24) then
            w.paused = not w.paused
        end
        if ui.button("sn_clear", "FLUSH", x + 94, by, 70, 24) then
            w.list = {}
        end
        ui.text("amber = suspicious", x + 176, by + 5, "dim")
    end,
}
