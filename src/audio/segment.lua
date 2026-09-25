local Segment = {}
Segment.__index = Segment

-- function: Validate an audio asset ID before using it as a file name.
local function validId(value)
    if value == nil then return false end
    local text = tostring(value)
    if text == "" or text == "." or text == ".." then return false end
    return not text:find("[/\\]")
end

-- function: Read a dotted configuration path from a Lua table.
local function readConfigPath(root, path)
    if type(path) ~= "string" or path == "" then return nil end
    local value = root
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

-- function: Normalize a configured path while rejecting absolute and parent-relative paths.
local function normalizeRelativePath(value)
    if type(value) ~= "string" or value == "" then return nil end
    if value:find("\\", 1, true) or value:sub(1, 1) == "/" or value:match("^%a:") then
        return nil
    end
    local parts = {}
    for part in value:gmatch("[^/]+") do
        if part == "." or part == ".." then return nil end
        parts[#parts + 1] = part
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "/")
end

-- function: Build the expected DFPWM path for one validated audio asset ID.
local function pathFromId(directory, value)
    if not validId(value) or type(directory) ~= "string" or directory == "" then
        return nil
    end
    return fs.combine(directory, tostring(value) .. ".dfpwm")
end

-- function: Create a semantic announcement segment resolver.
function Segment.new(config, definitions)
    return setmetatable({ config = config or {}, definitions = definitions or {} }, Segment)
end

-- function: Check whether an audio file exists and is not a directory.
function Segment:exists(path)
    return type(path) == "string" and path ~= "" and fs.exists(path) and not fs.isDir(path)
end

-- function: Check whether a segment definition is enabled by configuration.
function Segment:_isEnabled(definition)
    if definition.enabled == nil then return true end
    if type(definition.enabled) == "boolean" then return definition.enabled end
    if type(definition.enabled) == "string" then
        return readConfigPath(self.config, definition.enabled) == true
    end
    if type(definition.enabled) == "table" then
        local value = readConfigPath(self.config, definition.enabled.path)
        if value == nil then return definition.enabled.default == true end
        return value == true
    end
    error("invalid segment enabled condition")
end

-- function: Resolve a track-number segment from the announcement request.
function Segment:_resolveTrack(definition, context)
    local request = context and context.request or nil
    local value = request and request.track or nil
    local path = pathFromId(definition.directory, value)
    if not path then return nil, "track value is not available" end
    if self:exists(path) then return { path } end
    return nil, "missing audio: " .. path
end

-- function: Resolve a configured relative DFPWM path inside a fixed audio directory.
function Segment:_resolveConfigPath(definition, requirePlayable)
    local value = readConfigPath(self.config, definition.configPath)
    if value == nil or value == "" then value = definition.defaultPath end
    local relativePath = normalizeRelativePath(value)
    if not relativePath or relativePath:lower():sub(-6) ~= ".dfpwm" then
        error("configured audio path must be a relative .dfpwm path: " .. tostring(value))
    end
    local path = fs.combine(definition.directory, relativePath)
    if requirePlayable and not self:exists(path) then
        return nil, "missing audio: " .. path
    end
    return { path }
end

-- function: Resolve a semantic segment ID into one or more audio playback items.
function Segment:resolve(id, context, requirePlayable)
    local definition = self.definitions[id]
    if type(definition) == "string" then
        if requirePlayable and not self:exists(definition) then
            return nil, "missing audio: " .. definition
        end
        return { definition }
    end
    if type(definition) ~= "table" then
        error("unknown announcement segment: " .. tostring(id))
    end
    if not self:_isEnabled(definition) then return nil, "segment is disabled" end

    if definition.resolver == "track" then
        return self:_resolveTrack(definition, context)
    elseif definition.resolver == "config_path" then
        return self:_resolveConfigPath(definition, requirePlayable)
    end

    error("unknown dynamic segment resolver: " .. tostring(definition.resolver))
end

return Segment
