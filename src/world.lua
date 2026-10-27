-- World land data (assets/worldmask.lua) turned into dot meshes for the map and the intro globe.
local world = {}

local mask

local function load_mask()
    if mask then return mask end
    local chunk = love.filesystem.load("assets/worldmask.lua")
    local m = chunk()
    -- decode hex rows into boolean grids
    m.land = {}
    for r, hex in ipairs(m.data) do
        local row = {}
        for i = 1, #hex do
            local v = tonumber(hex:sub(i, i), 16)
            local base = (i - 1) * 4
            row[base + 1] = v >= 8
            row[base + 2] = v % 8 >= 4
            row[base + 3] = v % 4 >= 2
            row[base + 4] = v % 2 == 1
        end
        m.land[r] = row
    end
    m.data = nil
    mask = m
    return m
end

world.LAT_MAX = 84
world.LAT_MIN = -58

-- is (lat, lon) on land?
function world.is_land(lat, lon)
    local m = load_mask()
    local r = math.floor((m.lat_max - lat) / m.step) + 1
    local c = math.floor((lon + 180) / m.step) + 1
    return m.land[r] and m.land[r][c] or false
end

-- normalised map coordinates (0..1) <-> lat/lon (equirectangular)
function world.to_norm(lat, lon)
    return (lon + 180) / 360, (world.LAT_MAX - lat) / (world.LAT_MAX - world.LAT_MIN)
end

function world.from_norm(nx, ny)
    return world.LAT_MAX - ny * (world.LAT_MAX - world.LAT_MIN), nx * 360 - 180
end

-- dots every `every` cells, as a points mesh in normalised coordinates
local meshes = {}
function world.dots(every)
    if meshes[every] then return meshes[every] end
    local m = load_mask()
    local verts = {}
    for r = 1, m.rows, every do
        local row = m.land[r]
        for c = 1, m.cols, every do
            if row[c] then
                local lat = m.lat_max - (r - 0.5) * m.step
                local lon = (c - 0.5) * m.step - 180
                local nx, ny = world.to_norm(lat, lon)
                verts[#verts + 1] = { nx, ny }
            end
        end
    end
    local mesh = love.graphics.newMesh({ { "VertexPosition", "float", 2 } }, verts, "points", "static")
    meshes[every] = mesh
    return mesh
end

-- unit-sphere points for the spinning globe
local globe
function world.globe_points(every)
    if globe then return globe end
    local m = load_mask()
    globe = {}
    for r = 1, m.rows, every do
        local lat = math.rad(m.lat_max - (r - 0.5) * m.step)
        local cl, sl = math.cos(lat), math.sin(lat)
        local row = m.land[r]
        -- fewer dots near the poles so spacing stays even
        local step = math.max(every, math.floor(every / math.max(0.25, cl) + 0.5))
        for c = 1, m.cols, step do
            if row[c] then
                local lon = math.rad((c - 0.5) * m.step - 180)
                globe[#globe + 1] = { cl * math.cos(lon), sl, -cl * math.sin(lon) }
            end
        end
    end
    return globe
end

return world
