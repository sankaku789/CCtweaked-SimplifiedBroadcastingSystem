local Speakers = {}
Speakers.__index = Speakers

local DRAIN_EVENT = "simplified_speaker_drain_complete"

-- function: Discover every currently attached speaker peripheral.
local function discover()
    local wrapped = { peripheral.find("speaker") }
    local result = {}
    for _, speaker in ipairs(wrapped) do
        local ok, name = pcall(peripheral.getName, speaker)
        if ok and name then result[#result + 1] = { name = name, peripheral = speaker } end
    end
    return result
end

-- function: Refresh wrapped speaker peripherals from the current attachment state.
function Speakers:_refresh()
    local devices = discover()
    if #devices == 0 then return false end
    self.devices = devices
    return true
end

-- function: Wait until at least one speaker is available for playback.
function Speakers:_waitForDevices(reason)
    if reason and self.logger then self.logger.warn(reason) end
    while not self:_refresh() do
        sleep(self.reconnectDelay)
    end
    if self.logger then self.logger.info(("Connected %d speaker(s)."):format(#self.devices)) end
end

-- function: Create and connect the physical speaker set owned by the server.
function Speakers.connect(options, logger)
    options = options or {}
    local self = setmetatable({
        devices = {},
        volume = options.volume or 3,
        reconnectDelay = math.max(0, tonumber(options.reconnectDelay) or 1),
        logger = logger,
        audioOutstanding = false,
    }, Speakers)
    self:_waitForDevices()
    return self
end

-- function: Stop playback on every currently wrapped speaker.
function Speakers:stop()
    for _, device in ipairs(self.devices) do pcall(device.peripheral.stop) end
    self.audioOutstanding = false
end

-- function: Drain stale speaker events before beginning a new playback session.
function Speakers:drainEvents()
    sleep(0)
    os.queueEvent(DRAIN_EVENT)
    while os.pullEvent() ~= DRAIN_EVENT do end
end

-- function: Refresh speakers and clear stale playback state before one announcement.
function Speakers:preparePlayback()
    self.audioOutstanding = false
    self:drainEvents()
    if not self:_refresh() then self:_waitForDevices("Speaker unavailable. Reconnecting...") end
end

-- function: Wait until every active speaker has consumed its current audio buffer.
function Speakers:_waitAllReady(interruptEventName)
    local pending = {}
    local count = 0
    for _, device in ipairs(self.devices) do pending[device.name] = true; count = count + 1 end

    while count > 0 do
        local event, name = os.pullEvent()
        if interruptEventName and event == interruptEventName then return false end
        if event == "peripheral_detach" and pending[name] then
            self:_waitForDevices("Speaker detached. Reconnecting...")
            return false
        end
        if event == "speaker_audio_empty" and pending[name] then
            pending[name] = nil
            count = count - 1
        end
    end
    self.audioOutstanding = false
    return true
end

-- function: Submit one PCM chunk to all connected speakers, waiting when they are busy.
function Speakers:playChunk(audio, interruptEventName)
    while true do
        local accepted = true
        for _, device in ipairs(self.devices) do
            local ok, result = pcall(device.peripheral.playAudio, audio, self.volume)
            if not ok then
                self:_waitForDevices("Speaker playback failed. Reconnecting...")
                accepted = false
                break
            elseif not result then
                accepted = false
            end
        end
        if accepted then
            self.audioOutstanding = true
            return true
        end
        if not self:_waitAllReady(interruptEventName) then return false end
    end
end

-- function: Wait until all submitted audio has finished playing.
function Speakers:finishPlayback(interruptEventName)
    if not self.audioOutstanding then return true end
    return self:_waitAllReady(interruptEventName)
end

return Speakers
