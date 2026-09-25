local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(options)
    return setmetatable({
        config = options.config,
        logger = options.logger,
        input = options.input,
        composer = options.composer,
        player = options.player,
        pending = {},
    }, Scheduler)
end

function Scheduler:_priority()
    local priorities = self.config.queue and self.config.queue.priorities or {}
    return tonumber(priorities.approach) or 0
end

function Scheduler:_expiresAt()
    local ttl = self.config.queue and self.config.queue.ttlMs or {}
    local ttlMs = tonumber(ttl.approach)
    if not ttlMs then return nil end
    return os.epoch("utc") + math.max(0, ttlMs)
end

function Scheduler:_dispatch(lineId, track)
    local request = { type = "approach", track = track, lineId = lineId }
    local segments, diagnostics = self.composer:compose(request)

    if #segments == 0 then
        self.logger.warn(("Approach announcement has no playable segments: line=%s track=%s"):format(
            tostring(lineId), tostring(track)
        ))
        for _, diagnostic in ipairs(diagnostics or {}) do self.logger.warn(diagnostic) end
        return
    end

    for _, diagnostic in ipairs(diagnostics or {}) do self.logger.warn(diagnostic) end

    self.logger.event("Approach", ("line=%s track=%s"):format(tostring(lineId), tostring(track)))
    local completed = self.player:playSegments(
        segments,
        self:_priority(),
        nil,
        "approach",
        self:_expiresAt()
    )

    if not completed then
        self.logger.warn(("Approach playback did not complete: line=%s track=%s"):format(
            tostring(lineId), tostring(track)
        ))
    end
end

function Scheduler:_enqueue(lineId, track)
    self.pending[#self.pending + 1] = { lineId = lineId, track = track }
    os.queueEvent("simplified_approach_pending")
end

function Scheduler:_dispatchLoop()
    while true do
        if #self.pending == 0 then
            os.pullEvent("simplified_approach_pending")
        end

        local nextRequest = table.remove(self.pending, 1)
        if nextRequest then
            self:_dispatch(nextRequest.lineId, nextRequest.track)
        end
    end
end

function Scheduler:run()
    parallel.waitForAll(
        function()
            self.input:run(function(lineId, track)
                self:_enqueue(lineId, track)
            end)
        end,
        function() self:_dispatchLoop() end
    )
end

return Scheduler
