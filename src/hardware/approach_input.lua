local ApproachInput = {}
ApproachInput.__index = ApproachInput

local function active(side, color)
    return colors.test(redstone.getBundledInput(side), color)
end

local function validateLines(lines)
    assert(type(lines) == "table" and #lines == 2, "input.bundled.lines must contain exactly two lines")
    local tracksSeen = {}
    local colorsSeen = {}
    for index, line in ipairs(lines) do
        assert(type(line) == "table", "input line must be a table")
        assert(type(line.track) == "number", "input line track must be a number")
        assert(type(line.color) == "number", "input line color must be a bundled color")
        assert(not tracksSeen[line.track], "input line tracks must be unique")
        assert(not colorsSeen[line.color], "input line colors must be unique")
        tracksSeen[line.track] = true
        colorsSeen[line.color] = true
        lines[index] = {
            track = line.track,
            color = line.color,
        }
    end
end

function ApproachInput.new(options)
    options = options or {}
    local bundled = options.bundled or {}
    assert(type(bundled.side) == "string", "input.bundled.side must be a string")

    local lines = {}
    for index, line in ipairs(bundled.lines or {}) do lines[index] = line end
    validateLines(lines)

    local releaseDelaySeconds = tonumber(bundled.releaseDelaySeconds)
    if releaseDelaySeconds == nil then releaseDelaySeconds = 0.15 end
    assert(releaseDelaySeconds >= 0, "releaseDelaySeconds must be non-negative")

    return setmetatable({
        side = bundled.side,
        lines = lines,
        releaseDelaySeconds = releaseDelaySeconds,
    }, ApproachInput)
end

function ApproachInput:_waitStableLow(line)
    while active(self.side, line.color) do
        os.pullEvent("redstone")
    end

    if self.releaseDelaySeconds <= 0 then return end

    while true do
        local timer = os.startTimer(self.releaseDelaySeconds)
        while true do
            local event, value = os.pullEvent()
            if event == "redstone" and active(self.side, line.color) then
                if type(os.cancelTimer) == "function" then pcall(os.cancelTimer, timer) end
                break
            elseif event == "timer" and value == timer then
                if not active(self.side, line.color) then return end
                break
            end
        end

        while active(self.side, line.color) do
            os.pullEvent("redstone")
        end
    end
end

function ApproachInput:_monitorLine(line, onApproach)
    -- 起動時/chunk load時にHIGHだった線は新規接近として扱わない。
    self:_waitStableLow(line)

    while true do
        while not active(self.side, line.color) do
            os.pullEvent("redstone")
        end

        onApproach(line.track)
        self:_waitStableLow(line)
    end
end

function ApproachInput:run(onApproach)
    assert(type(onApproach) == "function", "approach callback is required")
    local tasks = {}
    for _, line in ipairs(self.lines) do
        tasks[#tasks + 1] = function() self:_monitorLine(line, onApproach) end
    end
    parallel.waitForAll(table.unpack(tasks))
end

return ApproachInput
