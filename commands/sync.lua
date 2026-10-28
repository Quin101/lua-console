-- Keep your markers and case board in step across devices through a cloud folder.
--   sync to <folder>   point at a Dropbox / iCloud / OneDrive / Drive folder
--   sync off           stop syncing (data stays on this device)
--   sync status        show the current state
local sync = require("src.sync")

local function esc(s) return (tostring(s or ""):gsub("{", "{{")) end

return {
    {
        name = "sync",
        aliases = { "cloud" },
        help = "sync markers + board across devices via a cloud folder",
        usage = "sync <to <folder> | off | status>",
        category = "tools",
        run = function(t, args, rest)
            local sub = (args[1] or ""):lower()

            if sub == "to" or sub == "on" or sub == "set" then
                local path = rest:gsub("^%S+%s*", ""):gsub('^"(.*)"$', "%1"):gsub("%s+$", "")
                if path == "" then
                    t.print("{dim}give a folder your cloud app keeps in sync, e.g.")
                    t.print("  {accent}sync to " .. (love.system.getOS() == "Windows" and "C:/Users/you/Dropbox/Qrawller" or "/Users/you/Dropbox/Qrawller"))
                    return
                end
                t.spin("checking folder", 0.5)
                local ok, msg = sync.enable(path)
                if not ok then
                    t.print("{err}✗{} " .. esc(msg))
                    t.sound("err")
                    return
                end
                t.config.on_setting("syncdir", sync.dir)
                t.print("{accent}✓ sync on{}  {dim}" .. esc(sync.dir))
                t.print("{dim}" .. esc(msg) .. "  ·  markers + board now mirror to that folder")
                t.print("{dim}open this app on another device, run the same {accent}sync to{dim} that folder,")
                t.print("{dim}and changes will appear on both within a few seconds.")
                t.sound("ok", { volume = 0.5 })
                t.sparks(16)

            elseif sub == "off" or sub == "stop" then
                sync.disable()
                t.config.on_setting("syncdir", "")
                t.print("{dim}sync off — your data stays on this device")
                t.sound("back")

            else
                t.print("")
                if sync.enabled() then
                    t.print("{accent}● sync on{}")
                    t.print("{dim}folder  {}" .. esc(sync.dir))
                    t.print("{dim}files   {}markers.lua, board.lua")
                    local ago = sync.last_in and (math.floor(love.timer.getTime() - sync.last_in) .. "s ago") or "none yet"
                    t.print("{dim}last incoming update  {}" .. ago)
                else
                    t.print("{dim}● sync off")
                    t.print("")
                    t.print("{dim}keep your markers + board in step across devices through a folder")
                    t.print("{dim}that Dropbox / iCloud / OneDrive / Google Drive already syncs:")
                    t.print("  {accent}sync to <folder>")
                    t.print("")
                    t.print("{dim}note: near-real-time (rides your cloud app, not instant);")
                    t.print("{dim}last edit wins if two devices change the same thing;")
                    t.print("{dim}email settings and vault files stay local.")
                end
                t.print("")
            end
        end,
    },
}
