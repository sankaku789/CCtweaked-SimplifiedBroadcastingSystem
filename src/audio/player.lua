local dfpwm = require("cc.audio.dfpwm")

local Player = {}
Player.__index = Player

local DFPWM_READ_SIZE = 4 * 1024
local PCM_CHUNK_SIZE = 128 * 1024
local PLAYBACK_COMPLETION_BARRIER = { 0 }
local INTERRUPT_EVENT = "simplified_player_interrupt"

local function audioPath(item)
    if type(item) == "string" then return item end
    if type(item) == "table" and item.kind == "audio" then return item.path end
    return nil
end

function Player.new(speakers, logger)
    return setmetatable({
        speakers = speakers,
        logger = logger,
        currentPriority = nil,
        interruptRequested = false,
    }, Player)
end

function Player:_validFile(path)
    return type(path) == "string" and path ~= "" and fs.exists(path) and not fs.isDir(path)
end

function Player:interrupt()
    if self.currentPriority == nil then return false end
    if self.interruptRequested then return true end
    self.interruptRequested = true
    self.speakers:stop()
    os.queueEvent(INTERRUPT_EVENT)
    return true
end

function Player:interruptBelow(priority)
    priority = tonumber(priority) or 0
    if self.currentPriority == nil or priority <= self.currentPriority then return false end
    return self:interrupt()
end

function Player:_playAudioRun(paths, onAudioStarted)
    local pcm = {}
    local pcmCount = 0
    local submittedAudio = false

    local function markStarted()
        if onAudioStarted then
            local callback = onAudioStarted
            onAudioStarted = nil
            callback(os.epoch("utc"))
        end
    end

    for _, path in ipairs(paths) do
        if self.interruptRequested then return false, "interrupted" end
        if not self:_validFile(path) then
            error("Audio file was not found: " .. tostring(path))
        end

        local decoder = dfpwm.make_decoder()
        for input in io.lines(path, DFPWM_READ_SIZE) do
            if self.interruptRequested then return false, "interrupted" end
            local decoded = decoder(input)
            for sampleIndex = 1, #decoded do
                pcmCount = pcmCount + 1
                pcm[pcmCount] = decoded[sampleIndex]
                if pcmCount == PCM_CHUNK_SIZE then
                    if not self.speakers:playChunk(pcm, INTERRUPT_EVENT) then
                        return false, "interrupted"
                    end
                    markStarted()
                    submittedAudio = true
                    pcm = {}
                    pcmCount = 0
                end
            end
        end
    end

    if pcmCount > 0 then
        if not self.speakers:playChunk(pcm, INTERRUPT_EVENT) then return false, "interrupted" end
        markStarted()
        submittedAudio = true
    end

    if submittedAudio then
        if not self.speakers:playChunk(PLAYBACK_COMPLETION_BARRIER, INTERRUPT_EVENT) then
            return false, "interrupted"
        end
    end

    return true
end

function Player:playSegments(segments, priority, onAudioStarted)
    self.currentPriority = tonumber(priority) or 0
    self.interruptRequested = false
    self.speakers:preparePlayback()

    local paths = {}
    for _, item in ipairs(segments or {}) do
        local path = audioPath(item)
        if not path then error("unknown playback item kind") end
        paths[#paths + 1] = path
    end

    local ok, reason = self:_playAudioRun(paths, onAudioStarted)
    local completed = ok and not self.interruptRequested
    if completed then completed = self.speakers:finishPlayback(INTERRUPT_EVENT) end
    if not completed then
        self.speakers:stop()
        self.speakers:drainEvents()
    end

    self.currentPriority = nil
    self.interruptRequested = false
    return completed, reason
end

return Player
