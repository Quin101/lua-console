-- Interactive network map. Hover a node to inspect it, click it to hack it.
local NAMES = {
    "gateway", "db-prod", "mail", "vault", "cctv", "hr-share", "build-01", "vpn", "dc-02",
    "printer", "backup", "wiki", "payroll", "iot-hub", "dev-box", "proxy", "ldap", "git",
}

local function gen(w, width, height)
    w.nodes, w.edges, w.packets = {}, {}, {}
    w.gen_time = love.timer.getTime()
    local used = {}
    local count = math.random(7, 10)
    -- "you" sits on the left
    w.nodes[1] = { name = "you", ip = "127.0.0.1", rx = 0.08, ry = 0.5, owned = true, you = true, born = 0 }
    local tries = 0
    while #w.nodes < count + 1 and tries < 400 do
        tries = tries + 1
        local rx, ry = 0.22 + math.random() * 0.72, 0.1 + math.random() * 0.8
        local ok = true
        for _, n in ipairs(w.nodes) do
            local dx, dy = (n.rx - rx) * width, (n.ry - ry) * height
            if dx * dx + dy * dy < 54 * 54 then ok = false break end
        end
        if ok then
            local name
            repeat name = NAMES[math.random(#NAMES)] until not used[name]
            used[name] = true
            w.nodes[#w.nodes + 1] = {
                name = name, rx = rx, ry = ry, born = #w.nodes * 0.06,
                ip = ("10.%d.%d.%d"):format(math.random(0, 9), math.random(0, 255), math.random(2, 254)),
                ports = math.random(1, 6),
                risk = math.random(),
            }
        end
    end
    -- connect each node to its two nearest neighbours
    local seen = {}
    for i, a in ipairs(w.nodes) do
        local d = {}
        for j, b in ipairs(w.nodes) do
            if i ~= j then d[#d + 1] = { j, (a.rx - b.rx) ^ 2 * width ^ 2 + (a.ry - b.ry) ^ 2 * height ^ 2 } end
        end
        table.sort(d, function(p, q) return p[2] < q[2] end)
        for k = 1, math.min(2, #d) do
            local j = d[k][1]
            local key = math.min(i, j) .. "-" .. math.max(i, j)
            if not seen[key] then
                seen[key] = true
                w.edges[#w.edges + 1] = { i, j }
            end
        end
    end
end

return {
    title = "NETWORK MAP",
    order = 2,
    height = "fill",

    load = function(w)
        w.nodes = nil
    end,

    status = function(w)
        if not w.nodes then return "" end
        local owned = 0
        for _, n in ipairs(w.nodes) do if n.owned and not n.you then owned = owned + 1 end end
        return owned .. "/" .. (#w.nodes - 1) .. " owned"
    end,

    update = function(w, dt, ui)
        if not w.nodes then return end
        local now = ui.time()
        -- packets running along the wires
        if math.random() < dt * 6 and #w.edges > 0 then
            local e = w.edges[math.random(#w.edges)]
            local fwd = math.random() < 0.5
            w.packets[#w.packets + 1] = { a = fwd and e[1] or e[2], b = fwd and e[2] or e[1], t = 0, speed = 0.6 + math.random() * 0.9 }
        end
        for i = #w.packets, 1, -1 do
            local p = w.packets[i]
            p.t = p.t + dt * p.speed
            if p.t >= 1 then table.remove(w.packets, i) end
        end
        for _, n in ipairs(w.nodes) do
            if n.breach_at and now >= n.breach_at then
                n.breach_at = nil
                n.owned = true
                n.flash = now
                ui.sound("ok", { volume = 0.35, pitch = 1.3 })
            end
        end
    end,

    draw = function(w, ui, x, y, width, height)
        if height < 40 then return end
        if not w.nodes or w.size_w ~= math.floor(width) or w.size_h ~= math.floor(height) then
            w.size_w, w.size_h = math.floor(width), math.floor(height)
            if not w.nodes then gen(w, width, height) end
        end
        local now = ui.time()
        local age = love.timer.getTime() - w.gen_time
        local function pos(n) return x + n.rx * width, y + n.ry * (height - 30) end

        -- wires
        love.graphics.setLineWidth(1)
        for _, e in ipairs(w.edges) do
            local a, b = w.nodes[e[1]], w.nodes[e[2]]
            local ax, ay = pos(a)
            local bx, by = pos(b)
            local hot = a.owned and b.owned
            ui.set_color(hot and "accent" or "faint", hot and 0.55 or 1)
            love.graphics.line(ax, ay, bx, by)
        end
        -- packets
        for _, p in ipairs(w.packets) do
            local a, b = w.nodes[p.a], w.nodes[p.b]
            local ax, ay = pos(a)
            local bx, by = pos(b)
            ui.set_color("accent", math.sin(p.t * math.pi))
            love.graphics.circle("fill", ax + (bx - ax) * p.t, ay + (by - ay) * p.t, 1.6)
        end
        -- nodes
        for i, n in ipairs(w.nodes) do
            local nx, ny = pos(n)
            local appear = ui.util.ease_out(ui.util.clamp((age - n.born) / 0.3, 0, 1))
            local hov = ui.hover(nx - 14, ny - 14, 28, 28)
            local hv = ui.ease("nm_" .. i, hov and 1 or 0, 16)
            local r = (n.you and 6 or 4.5) * appear + hv * 2
            if n.breach_at then
                -- pulsing rings while being hacked
                local ph = (now * 1.6) % 1
                ui.set_color("accent", 1 - ph)
                love.graphics.circle("line", nx, ny, r + ph * 16)
            end
            if n.flash then
                local f = now - n.flash
                if f < 0.8 then
                    ui.set_color("white", 1 - f / 0.8)
                    love.graphics.circle("line", nx, ny, r + f * 30)
                end
            end
            if n.owned then
                ui.set_color("accent", 1)
                love.graphics.circle("fill", nx, ny, r)
            else
                ui.set_color("bg", 1)
                love.graphics.circle("fill", nx, ny, r)
                ui.set_color(hov and "accent" or "dim", 1)
                love.graphics.circle("line", nx, ny, r)
            end
            if hv > 0.01 then
                ui.set_color("accent", 0.35 * hv)
                love.graphics.circle("line", nx, ny, r + 5)
            end
            ui.text(n.name, nx - ui.font:getWidth(n.name) / 2, ny + r + 3,
                n.owned and "text" or (hov and "white" or "dim"), nil, appear)

            if hov then
                ui.tooltip(n.you and "this machine" or
                    (n.name .. "  " .. n.ip .. "  ·  " .. n.ports .. " open ports  ·  " ..
                    (n.owned and "owned" or ("click to hack"))))
                if not n.you and not n.owned and not n.breach_at and ui.clicked(nx - 14, ny - 14, 28, 28) then
                    n.breach_at = now + 9
                    ui.run("hack " .. n.name)
                end
            end
        end

        -- bottom bar
        local by = y + height - 24
        if ui.button("nm_rescan", "RESCAN", x, by, 86, 24, { tip = "discover a new network" }) then
            gen(w, width, height)
            ui.sound("whoosh", { volume = 0.5 })
            ui.run("scan")
        end
        if ui.button("nm_all", "OWN ALL", x + 94, by, 86, 24, { tip = "hack everything (one by one)" }) then
            local delay = 0
            for _, n in ipairs(w.nodes) do
                if not n.owned and not n.breach_at then
                    delay = delay + 0.35
                    n.breach_at = now + delay
                end
            end
            ui.run("glitch")
        end
        ui.text("click a node to hack it", x + 192, by + 5, "dim")
    end,
}
