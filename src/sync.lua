-- Cloud-folder sync.
-- Mirrors chosen data files to a folder that a file-sync service (Dropbox,
-- iCloud Drive, OneDrive, Google Drive) keeps in step across your devices,
-- and reloads them when another device changes them. Near-real-time, two-way,
-- last-writer-wins. No server involved — it rides on your existing cloud sync.
local sync = {
    dir = nil,
    interval = 1.5,   -- how often to check the folder (seconds)
    acc = 0,
    seen = {},        -- name -> last content we wrote or adopted
    files = {},       -- { name, reload } registered by markers/board/...
    on_change = nil,  -- optional hook(name) when a remote change lands
    last_in = nil,    -- time of the last incoming change
    last_out = nil,   -- time of the last outgoing write
}

function sync.enabled() return sync.dir ~= nil and sync.dir ~= "" end

-- register a data file to keep in sync.  reload() re-reads it from the save dir.
function sync.register(name, reload)
    sync.files[#sync.files + 1] = { name = name, reload = reload }
end

local function ext_path(name) return (sync.dir:gsub("[/\\]+$", "")) .. "/" .. name end

function sync.read_ext(name)
    local f = io.open(ext_path(name), "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

function sync.write_ext(name, data)
    local f, err = io.open(ext_path(name), "wb")
    if not f then return false, err end
    f:write(data)
    f:close()
    return true
end

-- can we actually read/write in the folder? (used when turning sync on)
function sync.check(dir)
    dir = (dir or ""):gsub("[/\\]+$", "")
    if dir == "" then return false, "no folder given" end
    local probe = dir .. "/.qrawller_sync_test"
    local f = io.open(probe, "wb")
    if not f then return false, "can't write to that folder — is the path right?" end
    f:write("ok")
    f:close()
    os.remove(probe)
    return true
end

-- called by a data module right after it saves locally, with the serialized text
function sync.push(name, data)
    if not sync.enabled() then return end
    local ok = sync.write_ext(name, data)
    if ok then
        sync.seen[name] = data
        sync.last_out = love.timer.getTime()
    end
end

-- Turn sync on for `dir`. For each registered file: if the folder already has a
-- copy (from another device), adopt it; otherwise push our local copy up.
-- Returns ok, message.
function sync.enable(dir)
    local ok, err = sync.check(dir)
    if not ok then return false, err end
    sync.dir = (dir:gsub("[/\\]+$", ""))
    sync.seen = {}
    local adopted, pushed = 0, 0
    for _, f in ipairs(sync.files) do
        local remote = sync.read_ext(f.name)
        if remote and #remote > 0 then
            love.filesystem.write(f.name, remote)
            sync.seen[f.name] = remote
            pcall(f.reload)
            adopted = adopted + 1
        else
            local localdata = love.filesystem.read(f.name)
            if localdata then
                sync.write_ext(f.name, localdata)
                sync.seen[f.name] = localdata
                pushed = pushed + 1
            end
        end
    end
    return true, ("adopted %d, uploaded %d"):format(adopted, pushed)
end

function sync.disable()
    sync.dir = nil
    sync.seen = {}
end

-- polled from love.update
function sync.update(dt)
    if not sync.enabled() then return end
    sync.acc = sync.acc + dt
    if sync.acc < sync.interval then return end
    sync.acc = 0
    for _, f in ipairs(sync.files) do
        local remote = sync.read_ext(f.name)
        if remote and remote ~= sync.seen[f.name] then
            -- another device changed it: take the remote copy and reload
            love.filesystem.write(f.name, remote)
            sync.seen[f.name] = remote
            pcall(f.reload)
            sync.last_in = love.timer.getTime()
            if sync.on_change then pcall(sync.on_change, f.name) end
        end
    end
end

function sync.status_line()
    if not sync.enabled() then return "sync: off" end
    local ago = sync.last_in and ("%ds ago"):format(math.floor(love.timer.getTime() - sync.last_in)) or "—"
    return "sync: on  ·  last update " .. ago
end

return sync
