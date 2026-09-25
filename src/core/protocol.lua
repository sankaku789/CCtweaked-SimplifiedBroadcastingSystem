local Protocol = {}

Protocol.SYSTEM = "simplified_broadcasting_cs"
Protocol.VERSION = 1
Protocol.PLAYBACK_EVENT = "simplified_playback_response"
Protocol.SERVER_QUEUE_EVENT = "simplified_server_queue_changed"

Protocol.ACTION = {
    PLAY_REQUEST = "PLAY_REQUEST",
    PLAY_CANCEL = "PLAY_CANCEL",
    PLAY_ACCEPTED = "PLAY_ACCEPTED",
    PLAY_STARTED = "PLAY_STARTED",
    PLAY_COMPLETED = "PLAY_COMPLETED",
    PLAY_INTERRUPTED = "PLAY_INTERRUPTED",
    PLAY_CANCELLED = "PLAY_CANCELLED",
    PLAY_FAILED = "PLAY_FAILED",
    PLAY_EXPIRED = "PLAY_EXPIRED",
    PLAY_REJECTED = "PLAY_REJECTED",
}

local messageSequence = 0

-- function: Build one local playback lifecycle message envelope.
function Protocol.message(action, payload, instanceId)
    messageSequence = messageSequence + 1
    return {
        system = Protocol.SYSTEM,
        version = Protocol.VERSION,
        action = action,
        senderId = os.getComputerID(),
        instanceId = instanceId,
        messageId = ("%s:%s:%s"):format(
            tostring(os.getComputerID()),
            tostring(os.epoch("utc")),
            tostring(messageSequence)
        ),
        sentAt = os.epoch("utc"),
        payload = payload or {},
    }
end

-- function: Check whether one message belongs to this simplified C/S protocol.
function Protocol.matches(message)
    return type(message) == "table"
        and message.system == Protocol.SYSTEM
        and message.version == Protocol.VERSION
        and type(message.action) == "string"
end

return Protocol
