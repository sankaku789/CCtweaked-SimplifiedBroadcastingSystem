return {
    runtime = {
        restartDelaySeconds = 5,
        stableRunSeconds = 60,
        maxConsecutiveFailures = 5,
    },

    input = {
        bundled = {
            side = "top",
            releaseDelaySeconds = 0.15,
            lines = {
                { track = 1, color = colors.red },
                { track = 2, color = colors.blue },
            },
        },
    },

    speaker = {
        volume = 2,
        reconnectDelay = 1,
    },

    announcement = {
        melody = {
            -- Existing asset used as the approach chime in the original system.
            approachPath = "approach.dfpwm",

            -- Import destination for a standalone DFPWM file. Played optionally after the simple announcement.
            approachAfterPath = "approach_after.dfpwm",
            approachAfterEnabled = false,
        },
    },

    queue = {
        priorities = {
            approach = 2,
        },
        ttlMs = {
            approach = 30000,
        },
    },
}
