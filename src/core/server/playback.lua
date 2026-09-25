local Protocol = require("core.protocol")

local PlaybackServer = {}
PlaybackServer.__index = PlaybackServer

local SEEN_TERMINAL_RETENTION_MS = 5 * 60 * 1000
local TERMINAL_ACTIONS = {
    [Protocol.ACTION.PLAY_COMPLETED] = true,
    [Protocol.ACTION.PLAY_INTERRUPTED] = true,
    [Protocol.ACTION.PLAY_CANCELLED] = true,
    [Protocol.ACTION.PLAY_FAILED] = true,
    [Protocol.ACTION.PLAY_EXPIRED] = true,
    [Protocol.ACTION.PLAY_REJECTED] = true,
}

local function now() return os.epoch("utc") end
local function priorityOf(request) return tonumber(request.priority) or 0 end
local function requestLabel(request) return tostring(request.label or request.requestId) end

function PlaybackServer.new(options)
    return setmetatable({
        player = options.player,
        logger = options.logger,
        instanceId = options.instanceId,
        queue = {},
        sequence = 0,
        current = nil,
        seen = {},
    }, PlaybackServer)
end

function PlaybackServer:_reply(clientId, action, payload)
    if tonumber(clientId) ~= os.getComputerID() then return false end
    os.queueEvent(Protocol.PLAYBACK_EVENT, Protocol.message(action, payload, self.instanceId))
    return true
end

function PlaybackServer:_rememberSeen(key, action, payload)
    self.seen[key] = { action = action, payload = payload, updatedAt = now() }
end

function PlaybackServer:_pruneSeen()
    local current = now()
    for key, state in pairs(self.seen) do
        if TERMINAL_ACTIONS[state.action]
            and current - (tonumber(state.updatedAt) or current) > SEEN_TERMINAL_RETENTION_MS
        then
            self.seen[key] = nil
        end
    end
end

function PlaybackServer:_validate(sourceId, request)
    if type(request) ~= "table" then return false, "request must be a table" end
    if type(request.requestId) ~= "string" or request.requestId == "" then
        return false, "requestId is required"
    end
    if type(request.segments) ~= "table" or #request.segments == 0 then
        return false, "segments are required"
    end
    if tonumber(sourceId) == nil then return false, "sourceId is invalid" end
    return true
end

function PlaybackServer:_bestIndex()
    local bestIndex, bestPriority, bestSequence
    for index, request in ipairs(self.queue) do
        local priority = priorityOf(request)
        local sequence = tonumber(request.serverSequence) or math.huge
        if bestIndex == nil
            or priority > bestPriority
            or (priority == bestPriority and sequence < bestSequence)
        then
            bestIndex, bestPriority, bestSequence = index, priority, sequence
        end
    end
    return bestIndex
end

function PlaybackServer:_enqueue(request)
    self.sequence = self.sequence + 1
    request.serverSequence = self.sequence
    self.queue[#self.queue + 1] = request
    os.queueEvent(Protocol.SERVER_QUEUE_EVENT)

    if self.current and priorityOf(request) > priorityOf(self.current) then
        self.player:interruptBelow(priorityOf(request))
    end
end

function PlaybackServer:submit(sourceId, request)
    self:_pruneSeen()
    sourceId = tonumber(sourceId)
    local valid, reason = self:_validate(sourceId, request)
    if not valid then
        if sourceId then
            self:_reply(sourceId, Protocol.ACTION.PLAY_REJECTED, {
                requestId = type(request) == "table" and request.requestId or nil,
                reason = reason,
            })
        end
        return false
    end

    local seenKey = ("%s:%s"):format(tostring(sourceId), request.requestId)
    local seen = self.seen[seenKey]
    if seen then
        self:_reply(sourceId, seen.action or Protocol.ACTION.PLAY_ACCEPTED,
            seen.payload or { requestId = request.requestId, duplicate = true })
        return true
    end

    local queued = {
        requestId = request.requestId,
        sourceId = sourceId,
        priority = priorityOf(request),
        createdAt = tonumber(request.createdAt) or now(),
        expiresAt = tonumber(request.expiresAt),
        segments = request.segments,
        label = request.label,
    }

    local acceptedPayload = { requestId = queued.requestId, acceptedAt = now() }
    self:_rememberSeen(seenKey, Protocol.ACTION.PLAY_ACCEPTED, acceptedPayload)
    self:_reply(sourceId, Protocol.ACTION.PLAY_ACCEPTED, acceptedPayload)
    self:_enqueue(queued)
    return true
end

function PlaybackServer:cancel(sourceId, requestId, reason)
    sourceId = tonumber(sourceId)
    requestId = tostring(requestId or "")
    if not sourceId or requestId == "" then return false end

    for index = #self.queue, 1, -1 do
        local request = self.queue[index]
        if request.sourceId == sourceId and request.requestId == requestId then
            table.remove(self.queue, index)
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_CANCELLED, {
                requestId = requestId, cancelledAt = now(), reason = reason,
            })
            return true
        end
    end

    if self.current and self.current.sourceId == sourceId and self.current.requestId == requestId then
        self.current.cancelRequested = true
        self.current.superseded = reason == "superseded"
        self.player:interrupt()
        return true
    end

    return false
end

function PlaybackServer:_finishClientRequest(request, action, payload)
    local seenKey = ("%s:%s"):format(tostring(request.sourceId), request.requestId)
    self:_rememberSeen(seenKey, action, payload)
    self:_reply(request.sourceId, action, payload)
end

function PlaybackServer:_pop()
    while true do
        local index = self:_bestIndex()
        if not index then return nil end
        local request = table.remove(self.queue, index)
        if request.expiresAt and request.expiresAt < now() then
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_EXPIRED, {
                requestId = request.requestId, expiredAt = now(),
            })
        else
            return request
        end
    end
end

function PlaybackServer:_waitNext()
    while true do
        local request = self:_pop()
        if request then return request end
        os.pullEvent(Protocol.SERVER_QUEUE_EVENT)
    end
end

function PlaybackServer:_processQueue()
    while true do
        local request = self:_waitNext()
        self.current = request
        request.cancelRequested = false
        request.superseded = false

        if self.logger then
            self.logger.info(("Server dispatching: %s priority=%s request=%s"):format(
                requestLabel(request), tostring(request.priority), tostring(request.requestId)
            ))
        end

        local startedAt
        local ok, result = pcall(function()
            return self.player:playSegments(request.segments, request.priority, function(epoch)
                startedAt = tonumber(epoch) or now()
                local payload = { requestId = request.requestId, startedAt = startedAt }
                local key = ("%s:%s"):format(tostring(request.sourceId), request.requestId)
                self:_rememberSeen(key, Protocol.ACTION.PLAY_STARTED, payload)
                self:_reply(request.sourceId, Protocol.ACTION.PLAY_STARTED, payload)
            end)
        end)

        local completedAt = now()
        if not ok then
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_FAILED, {
                requestId = request.requestId, failedAt = completedAt, reason = tostring(result),
            })
        elseif result == true then
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_COMPLETED, {
                requestId = request.requestId, startedAt = startedAt, completedAt = completedAt,
            })
        elseif request.superseded then
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_INTERRUPTED, {
                requestId = request.requestId, startedAt = startedAt,
                interruptedAt = completedAt, reason = "superseded",
            })
        elseif request.cancelRequested then
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_CANCELLED, {
                requestId = request.requestId, startedAt = startedAt, cancelledAt = completedAt,
            })
        else
            self:_finishClientRequest(request, Protocol.ACTION.PLAY_INTERRUPTED, {
                requestId = request.requestId, startedAt = startedAt, interruptedAt = completedAt,
            })
        end

        self.current = nil
        self:_pruneSeen()
        os.queueEvent(Protocol.SERVER_QUEUE_EVENT)
    end
end

function PlaybackServer:run()
    self:_processQueue()
end

return PlaybackServer
