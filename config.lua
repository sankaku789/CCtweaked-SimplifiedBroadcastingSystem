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
            -- 元システムでは接近チャイムとして使用する既存asset。
            approachPath = "approach.dfpwm",

            -- 単独DFPWM import先。簡易放送の後に任意再生する。
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
