local BLOCK_SIZE = 512
local COPY_CHUNK_SIZE = 16 * 1024
local AUDIO_ROOT = "/audio"
local APPROACH_AFTER_MELODY_PATH = "/audio/melody/approach_after.dfpwm"

local function cleanField(value)
    local zero = value:find("\0", 1, true)
    if zero then value = value:sub(1, zero - 1) end
    return value:gsub("%s+$", "")
end

local function parseOctal(value, fieldName)
    value = cleanField(value):gsub("^%s+", "")
    if value == "" then return 0 end
    local parsed = tonumber(value, 8)
    if not parsed then error("Invalid TAR " .. tostring(fieldName) .. " field", 0) end
    return parsed
end

local function readExact(handle, count)
    if count <= 0 then return "" end
    local chunks, total = {}, 0
    while total < count do
        local chunk = handle.read(count - total)
        if not chunk or #chunk == 0 then
            if total == 0 then return nil end
            error("Unexpected end of transferred file", 0)
        end
        chunks[#chunks + 1] = chunk
        total = total + #chunk
    end
    return table.concat(chunks)
end

local function skipBytes(handle, count)
    local remaining = count
    while remaining > 0 do
        local chunk = readExact(handle, math.min(COPY_CHUNK_SIZE, remaining))
        if not chunk then error("Unexpected end of transferred file", 0) end
        remaining = remaining - #chunk
    end
end

local function isZeroBlock(block)
    for index = 1, #block do
        if block:byte(index) ~= 0 then return false end
    end
    return true
end

local function validateChecksum(header)
    local expected = parseOctal(header:sub(149, 156), "checksum")
    local actual = 0
    for index = 1, BLOCK_SIZE do
        actual = actual + ((index >= 149 and index <= 156) and 32 or header:byte(index))
    end
    if actual ~= expected then error("Invalid TAR header checksum", 0) end
end

local function parseHeader(header)
    validateChecksum(header)
    local name = cleanField(header:sub(1, 100))
    local prefix = cleanField(header:sub(346, 500))
    if prefix ~= "" then name = prefix .. "/" .. name end
    return {
        name = name,
        size = parseOctal(header:sub(125, 136), "size"),
        typeFlag = header:sub(157, 157),
    }
end

local function normalizeEntryPath(path)
    if type(path) ~= "string" or path:find("\\", 1, true) then
        error("Invalid TAR entry path", 0)
    end
    while path:sub(1, 2) == "./" do path = path:sub(3) end
    path = path:gsub("/+$", "")
    if path == "" then return nil end
    if path:sub(1, 1) == "/" or path:match("^%a:") then error("Absolute TAR path is not allowed", 0) end

    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == "." or part == ".." then error("Unsafe TAR path", 0) end
        parts[#parts + 1] = part
    end
    if parts[1] == "audio" then
        error("TAR root must be the contents of audio/, not an outer audio/ directory", 0)
    end
    return table.concat(parts, "/")
end

local function ensureDirectory(path)
    if path == "" or path == "/" then return end
    if fs.exists(path) then
        if not fs.isDir(path) then error("Expected directory: " .. path, 0) end
        return
    end
    local parent = fs.getDir(path)
    if parent ~= "" and parent ~= path then ensureDirectory(parent) end
    fs.makeDir(path)
end

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" then ensureDirectory(parent) end
end

local function writeStream(input, target, size)
    ensureParent(target)
    local temporary = target .. ".import"
    if fs.exists(temporary) then fs.delete(temporary) end
    local output = assert(fs.open(temporary, "wb"), "Could not open " .. temporary)

    local ok, result = pcall(function()
        local total = 0
        while size == nil or total < size do
            local wanted = size and math.min(COPY_CHUNK_SIZE, size - total) or COPY_CHUNK_SIZE
            if wanted <= 0 then break end
            local chunk = input.read(wanted)
            if not chunk or #chunk == 0 then
                if size and total < size then error("Unexpected end of transferred file", 0) end
                break
            end
            output.write(chunk)
            total = total + #chunk
        end
        return total
    end)
    output.close()

    if not ok then
        if fs.exists(temporary) then fs.delete(temporary) end
        error(result, 0)
    end
    if fs.exists(target) then fs.delete(target) end
    fs.move(temporary, target)
    return result
end

local function extractTar(handle)
    ensureDirectory(AUDIO_ROOT)
    local files, bytes, skipped = 0, 0, 0
    while true do
        local header = readExact(handle, BLOCK_SIZE)
        if not header or isZeroBlock(header) then break end
        local entry = parseHeader(header)
        local relativePath = normalizeEntryPath(entry.name)
        local regular = entry.typeFlag == "0" or entry.typeFlag == "\0" or entry.typeFlag == ""

        if entry.typeFlag == "5" then
            if relativePath then ensureDirectory(fs.combine(AUDIO_ROOT, relativePath)) end
            skipBytes(handle, entry.size)
        elseif regular and relativePath and relativePath:lower():sub(-6) == ".dfpwm" then
            writeStream(handle, fs.combine(AUDIO_ROOT, relativePath), entry.size)
            files = files + 1
            bytes = bytes + entry.size
            print("Audio -> " .. relativePath)
        else
            skipBytes(handle, entry.size)
            skipped = skipped + 1
        end

        skipBytes(handle, (BLOCK_SIZE - (entry.size % BLOCK_SIZE)) % BLOCK_SIZE)
    end
    return files, bytes, skipped
end

local function selectImportFile(transferredFiles)
    local selected, kind
    for _, file in ipairs(transferredFiles.getFiles()) do
        local name = tostring(file.getName())
        local lower = name:lower()
        if not selected and lower:sub(-4) == ".tar" then
            selected, kind = file, "tar"
            print("Importing TAR -> " .. name)
        elseif not selected and lower:sub(-6) == ".dfpwm" then
            selected, kind = file, "approach_after_melody"
            print("Importing approach-after melody -> " .. name)
        else
            print("Ignore transfer -> " .. name)
            file.close()
        end
    end
    return selected, kind
end

local function main()
    print("Simplified Broadcasting Audio Importer")
    print("Drop audio_pack.tar or one .dfpwm file onto this computer.")
    print("A single .dfpwm is installed as " .. APPROACH_AFTER_MELODY_PATH .. ".")

    while true do
        local _, transferredFiles = os.pullEvent("file_transfer")
        local file, kind = selectImportFile(transferredFiles)
        if file then
            if kind == "approach_after_melody" then
                local ok, result = pcall(writeStream, file, APPROACH_AFTER_MELODY_PATH, nil)
                file.close()
                if not ok then printError("Approach melody import failed: " .. tostring(result)); return end
                print(("Approach melody installed: %s (%d byte(s))."):format(APPROACH_AFTER_MELODY_PATH, result))
                return
            end

            local ok, files, bytes, skipped = pcall(extractTar, file)
            file.close()
            if not ok then printError("Audio import failed: " .. tostring(files)); return end
            print(("Import complete: %d file(s), %d byte(s), %d skipped."):format(files, bytes, skipped))
            return
        end
        printError("No .tar or .dfpwm file was included in the transfer.")
    end
end

main()
