local log = {}

local function prefix()
    local epochMs = os.epoch("local")
    local milliseconds = epochMs % 1000
    return ("[%s.%03d] : "):format(
        textutils.formatTime(os.time("local"), true),
        milliseconds
    )
end

function log.info(message)
    print(prefix() .. tostring(message))
end

function log.event(category, message)
    print(prefix() .. tostring(category) .. " -> " .. tostring(message))
end

function log.warn(message)
    print(prefix() .. "Warning -> " .. tostring(message))
end

function log.error(message)
    print(prefix() .. "Error -> " .. tostring(message))
end

return log
