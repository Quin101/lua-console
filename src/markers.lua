-- Map markers: stored in the save folder (markers.lua) and shared by the map widget and commands.
--   kind = "victim":  name, age, dob, dod, ip, address, notes
--   kind = "place":   name, notes
local markers = { list = {}, selected = nil, fly = nil, dirty_at = nil }

local FILE = "markers.lua"

markers.VICTIM_FIELDS = {
    { "name", "name" }, { "age", "age" }, { "dob", "date of birth" }, { "dod", "date of death" },
    { "ip", "ip address" }, { "address", "address" }, { "notes", "anything else" },
}
markers.PLACE_FIELDS = { { "name", "name" }, { "notes", "description" } }

local KEYS = { "id", "kind", "lat", "lon", "created", "name", "age", "dob", "dod", "ip", "address", "notes" }

function markers.load()
    markers.list = {}
    if not love.filesystem.getInfo(FILE) then return 0 end
    local ok, chunk = pcall(love.filesystem.load, FILE)
    if not ok or not chunk then return 0 end
    setfenv(chunk, {}) -- the file is plain data; give it no access to anything
    local ok2, data = pcall(chunk)
    if ok2 and type(data) == "table" then
        for _, m in ipairs(data) do
            if type(m) == "table" and tonumber(m.lat) and tonumber(m.lon) then
                markers.list[#markers.list + 1] = m
            end
        end
    end
    return #markers.list
end

function markers.save()
    local out = { "-- Qrawller map markers\nreturn {\n" }
    for _, m in ipairs(markers.list) do
        local parts = {}
        for _, k in ipairs(KEYS) do
            local v = m[k]
            if v ~= nil and v ~= "" then
                parts[#parts + 1] = k .. " = " .. (type(v) == "number" and tostring(v) or ("%q"):format(tostring(v)))
            end
        end
        out[#out + 1] = "    { " .. table.concat(parts, ", ") .. " },\n"
    end
    out[#out + 1] = "}\n"
    love.filesystem.write(FILE, table.concat(out))
    markers.dirty_at = nil
end

-- call after editing a marker; it is written to disk shortly after
function markers.touch()
    markers.dirty_at = love.timer.getTime()
end

function markers.update()
    if markers.dirty_at and love.timer.getTime() - markers.dirty_at > 0.6 then markers.save() end
end

local function next_id()
    local id = 0
    for _, m in ipairs(markers.list) do id = math.max(id, m.id or 0) end
    return id + 1
end

function markers.add(kind, lat, lon)
    local m = { id = next_id(), kind = kind, lat = lat, lon = lon, created = os.date("%Y-%m-%d %H:%M"), name = "" }
    markers.list[#markers.list + 1] = m
    markers.selected = m.id
    markers.save()
    return m
end

function markers.remove(id)
    for i, m in ipairs(markers.list) do
        if m.id == id then
            table.remove(markers.list, i)
            if markers.selected == id then markers.selected = nil end
            markers.save()
            return true
        end
    end
    return false
end

function markers.get(id)
    for _, m in ipairs(markers.list) do
        if m.id == id then return m end
    end
end

-- find by (partial) name or by id
function markers.find(query)
    query = tostring(query or ""):lower()
    if query == "" then return nil end
    local n = tonumber(query)
    for _, m in ipairs(markers.list) do
        if (n and m.id == n) or (m.name or ""):lower() == query then return m end
    end
    for _, m in ipairs(markers.list) do
        if (m.name or ""):lower():find(query, 1, true) then return m end
    end
end

-- select a marker and ask the map to fly to it
function markers.select(id, fly)
    markers.selected = id
    if fly then markers.fly = id end
end

function markers.count()
    local v, p = 0, 0
    for _, m in ipairs(markers.list) do
        if m.kind == "victim" then v = v + 1 else p = p + 1 end
    end
    return v, p
end

function markers.label(m)
    if m.name and m.name ~= "" then return m.name end
    return (m.kind == "victim" and "unknown subject" or "unnamed place") .. " #" .. m.id
end

function markers.coords(lat, lon)
    return ("%.4f°%s  %.4f°%s"):format(math.abs(lat), lat >= 0 and "N" or "S", math.abs(lon), lon >= 0 and "E" or "W")
end

return markers
