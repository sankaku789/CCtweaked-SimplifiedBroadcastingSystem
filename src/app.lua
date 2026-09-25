local config = require("config")
local announcementPatterns = require("announcement_patterns.main")
local segmentDefinitions = require("announcement_patterns.segments")

local log = require("util.log")
local ApproachInput = require("hardware.approach_input")
local Speakers = require("hardware.speakers")
local Segment = require("audio.segment")
local Composer = require("core.composer")
local Player = require("audio.player")
local PlaybackClient = require("core.client.playback")
local Scheduler = require("core.client.scheduler")
local PlaybackServer = require("core.server.playback")

local app = {}

-- function: Build a boot-unique instance ID for local playback request IDs.
local function bootInstanceId()
    return ("%s:%s"):format(tostring(os.getComputerID()), tostring(os.epoch("utc")))
end

-- function: Build the local Client/Server stack and run input monitoring with playback processing.
function app.run()
    log.info("Simplified Broadcasting System starting.")

    local speakers = Speakers.connect(config.speaker, log)
    local physicalPlayer = Player.new(speakers, log)
    local instanceId = bootInstanceId()

    local playbackServer = PlaybackServer.new({
        player = physicalPlayer,
        logger = log,
        instanceId = instanceId,
    })

    local playbackClient = PlaybackClient.new({
        localServer = playbackServer,
        logger = log,
        instanceId = instanceId,
    })

    local input = ApproachInput.new(config.input)
    local resolver = Segment.new(config, segmentDefinitions)
    local composer = Composer.new(announcementPatterns, resolver)
    local scheduler = Scheduler.new({
        config = config,
        logger = log,
        input = input,
        composer = composer,
        player = playbackClient,
    })

    parallel.waitForAll(
        function() scheduler:run() end,
        function() playbackServer:run() end
    )
end

return app
