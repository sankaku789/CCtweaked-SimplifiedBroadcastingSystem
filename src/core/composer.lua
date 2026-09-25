local Composer = {}
Composer.__index = Composer

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function appendAll(output, items)
    if not items then return end
    for _, item in ipairs(items) do output[#output + 1] = item end
end

local function appendDiagnostics(output, diagnostics)
    for _, diagnostic in ipairs(diagnostics or {}) do
        output[#output + 1] = diagnostic
    end
end

local function parseEntry(entry)
    assert(type(entry) == "string", "announcement pattern entry must be a string")
    entry = trim(entry)
    assert(entry ~= "", "announcement pattern entry cannot be empty")

    local optional = entry:sub(1, 1) == "?"
    if optional then
        entry = trim(entry:sub(2))
        assert(entry ~= "", "optional announcement segment cannot be empty")
    end

    local separator = entry:find("|", 1, true)
    if not separator then
        return { optional = optional, primary = entry }
    end

    local primary = trim(entry:sub(1, separator - 1))
    local fallback = trim(entry:sub(separator + 1))
    assert(primary ~= "" and fallback ~= "", "fallback segment cannot be empty")
    return { optional = optional, primary = primary, fallback = fallback }
end

function Composer.new(patterns, resolver)
    return setmetatable({ patterns = patterns or {}, resolver = resolver }, Composer)
end

function Composer:_resolveSymbol(id, context, requirePlayable)
    local items, reason = self.resolver:resolve(id, context, requirePlayable)
    if not items and reason then return nil, { tostring(id) .. ": " .. tostring(reason) } end
    return items
end

function Composer:_resolveEntry(entry, context)
    local parsed = parseEntry(entry)
    if parsed.fallback then
        local primary, primaryDiagnostics = self:_resolveSymbol(parsed.primary, context, true)
        if primary then return primary, parsed end
        local fallback, fallbackDiagnostics = self:_resolveSymbol(parsed.fallback, context, true)
        if fallback then return fallback, parsed end
        local diagnostics = {}
        appendDiagnostics(diagnostics, primaryDiagnostics)
        appendDiagnostics(diagnostics, fallbackDiagnostics)
        return nil, parsed, diagnostics
    end

    local items, diagnostics = self:_resolveSymbol(parsed.primary, context, parsed.optional)
    return items, parsed, diagnostics
end

function Composer:compose(request)
    local pattern = self.patterns[request.type]
    if type(pattern) ~= "table" then
        return {}, { "announcement pattern not found: " .. tostring(request.type) }
    end

    local context = { request = request }
    local output = {}
    local diagnostics = {}

    for _, entry in ipairs(pattern) do
        local items, parsed, entryDiagnostics = self:_resolveEntry(entry, context)
        if items then
            appendAll(output, items)
        elseif not parsed.optional then
            appendDiagnostics(diagnostics, entryDiagnostics)
        end
    end

    return output, diagnostics
end

return Composer
