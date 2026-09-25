local Protocol = require("core.protocol")

local PlaybackClient = {}
PlaybackClient.__index = PlaybackClient

local TERMINAL_ACTIONS = {
    [Protocol.ACTION.PLAY_COMPLETED] = true,
    [Protocol.ACTION.PLAY_INTERRUPTED] = true,
    [Protocol.ACTION.PLAY_CANCELLED] = true,
    [Protocol.ACTION.PLAY_FAILED] = true,
    [Protocol.ACTION.PLAY_EXPIRED] = true,
    [Protocol.ACTION.PLAY_REJECTED] = true,
}

function PlaybackClient.new(options)
    assert(options.localServer, "local playback server is required")
    return setmetatable({
        instanceId = options.instanceId,
        localServer = options.localServer,
        logger = options.logger,
        requestSequence = 0,
        current = nil,
    }, PlaybackClient)
end

function PlaybackClient:_nextRequestId()
    self.requestSequence = self.requestSequence + 1
    return ("%s:%s"):format(tostring(self.instanceId), tostring(self.requestSequence))
end

function PlaybackClient:_submit(payload)
    self.localServer:submit(os.getComputerID(), payload)
    return true
end

function PlaybackClient:_sendCancel(requestId, reason)
    return self.localServer:cancel(os.getComputerID(), requestId, reason)
end

function PlaybackClient:interruptBelow(priority)
    priority = tonumber(priority) or 0
    if not self.current or priority <= self.current.priority then return false end
    if self.current.cancelRequested then return true end
    self.current.cancelRequested = true
    self.current.cancelReason = "superseded"
    self:_sendCancel(self.current.requestId, self.current.cancelReason)
    return true
end

function PlaybackClient:_waitResponse(requestId)
    while true do
        local event = { os.pullEvent() }
        if event[1] == Protocol.PLAYBACK_EVENT then
            local message = event[2]
            if Protocol.matches(message)
                and type(message.payload) == "table"
                and message.payload.requestId == requestId
            then
                return message
            end
        end
    end
end

function PlaybackClient:playSegments(segments, priority, onAudioStarted, announcementType, expiresAt)
    local requestId = self:_nextRequestId()
    local request = {
        requestId = requestId,
        priority = tonumber(priority) or 0,
        createdAt = os.epoch("utc"),
        expiresAt = tonumber(expiresAt),
        segments = segments,
        label = type(announcementType) == "string" and announcementType or nil,
    }

    self.current = {
        requestId = requestId,
        priority = request.priority,
        cancelRequested = false,
    }

    self:_submit(request)
    local started = false

    while true do
        local message = self:_waitResponse(requestId)
        if message.action == Protocol.ACTION.PLAY_STARTED and not started then
            started = true
            if onAudioStarted then
                onAudioStarted(tonumber(message.payload.startedAt) or os.epoch("utc"))
            end
        elseif TERMINAL_ACTIONS[message.action] then
            self.current = nil
            return message.action == Protocol.ACTION.PLAY_COMPLETED
        end
    end
end

return PlaybackClient
