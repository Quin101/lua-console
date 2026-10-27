-- Terminal side of the world map.
local markers = require("src.markers")

local function esc(s) return (tostring(s or ""):gsub("{", "{{")) end

local function resolve(t, query)
    local m = markers.find(query)
    if not m then
        t.print("no marker matches {white}" .. esc(query) .. "{}  ·  try {accent}markers{}", "err")
        t.sound("err", { volume = 0.6 })
    end
    return m
end

return {
    {
        name = "markers",
        help = "list everything on the world map",
        category = "map",
        run = function(t)
            if #markers.list == 0 then
                return t.print("the map is empty  ·  use {accent}◆ VICTIM{} or {white}○ PLACE{} above the map to drop one", "dim")
            end
            t.print("")
            local rows = { { "ID", "TYPE", "NAME", "LOCATION" } }
            for _, m in ipairs(markers.list) do
                rows[#rows + 1] = { "#" .. m.id, m.kind, markers.label(m), markers.coords(m.lat, m.lon) }
            end
            t.table(rows, { "dim", "accent", "white", "dim" })
            t.print("")
            t.print("{dim}locate <name or id>  ·  dossier <name or id>")
            t.print("")
        end,
    },
    {
        name = "locate",
        help = "fly the map to a marker",
        usage = "locate <name or id>",
        category = "map",
        run = function(t, args, rest)
            local m = resolve(t, rest)
            if not m then return end
            t.sound("whoosh", { volume = 0.6 })
            markers.select(m.id, true)
            t.spin("triangulating " .. esc(markers.label(m)), 0.7, markers.coords(m.lat, m.lon))
        end,
    },
    {
        name = "dossier",
        help = "print everything known about a marker",
        usage = "dossier <name or id>",
        category = "map",
        run = function(t, args, rest)
            local m = resolve(t, rest)
            if not m then return end
            markers.select(m.id, true)
            local victim = m.kind == "victim"
            t.print("")
            t.progress("pulling records", 0.8)
            t.print("")
            t.print("{dim}──── " .. (victim and "{accent}VICTIM FILE{dim}" or "{white}PLACE FILE{dim}") .. " #" .. m.id .. " " .. string.rep("─", 28))
            t.decode(markers.label(m):upper(), victim and "accent" or "white", 0.6)
            local fields = victim and markers.VICTIM_FIELDS or markers.PLACE_FIELDS
            for _, f in ipairs(fields) do
                if f[1] ~= "name" and f[1] ~= "notes" then
                    local v = m[f[1]]
                    t.print("{dim}" .. t.pad(f[2], 16) .. "{}" .. ((v and v ~= "") and esc(v) or "{faint}—"))
                    t.sound("tick", { pitch = 0.8, volume = 0.5 })
                    t.wait(0.05)
                end
            end
            t.print("{dim}" .. t.pad("location", 16) .. "{}" .. markers.coords(m.lat, m.lon))
            t.print("{dim}" .. t.pad("on file since", 16) .. "{}" .. esc(m.created or "?"))
            if m.notes and m.notes ~= "" then
                t.print("")
                t.print("{dim}" .. (victim and "notes" or "description"))
                t.type(esc(m.notes), "text", 140)
            end
            t.print("{dim}" .. string.rep("─", 46))
            t.print("")
            t.sound("lock", { volume = 0.6 })
        end,
    },
}
