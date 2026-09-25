local BASE = "https://raw.githubusercontent.com/sankaku789/CCtweaked-SimplifiedBroadcastingSystem/main/"
local FILES = {
    "startup.lua",
    "config.lua",
    "import_audio.lua",
    "announcement_patterns/main.lua",
    "announcement_patterns/segments.lua",
    "src/app.lua",
    "src/audio/player.lua",
    "src/audio/segment.lua",
    "src/core/composer.lua",
    "src/core/protocol.lua",
    "src/core/client/playback.lua",
    "src/core/client/scheduler.lua",
    "src/core/server/playback.lua",
    "src/hardware/approach_input.lua",
    "src/hardware/speakers.lua",
    "src/util/log.lua",
}

-- function: Ensure one directory and all of its parents exist.
local function ensureDirectory(path)
    if path == "" or path == "." then return end
    if fs.exists(path) then return end
    local parent = fs.getDir(path)
    if parent ~= "" and parent ~= path then ensureDirectory(parent) end
    fs.makeDir(path)
end

-- function: Ensure the parent directory for one target file exists.
local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" then ensureDirectory(parent) end
end

-- function: Download one repository file into the local ComputerCraft filesystem.
local function download(path)
    local target = fs.combine("/", path)
    ensureParent(target)
    local response, err = http.get(BASE .. path)
    if not response then error("Download failed: " .. path .. ": " .. tostring(err), 0) end
    local content = response.readAll()
    response.close()
    local handle = assert(fs.open(target, "w"), "Could not write " .. target)
    handle.write(content)
    handle.close()
    print("Installed -> " .. target)
end

for _, path in ipairs(FILES) do download(path) end

for _, dir in ipairs({ "audio/melody", "audio/approach", "audio/track/ni" }) do
    ensureDirectory(fs.combine("/", dir))
end

print("Installation complete.")
print("Run 'import_audio' to import audio assets, then reboot.")
