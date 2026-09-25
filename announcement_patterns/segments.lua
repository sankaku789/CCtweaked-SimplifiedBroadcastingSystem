return {
    approach_chime = {
        resolver = "config_path",
        directory = "audio/melody",
        configPath = "announcement.melody.approachPath",
        defaultPath = "approach.dfpwm",
    },

    soon = "audio/approach/soon.dfpwm",

    track_ni = {
        resolver = "track",
        directory = "audio/track/ni",
    },

    train = "audio/approach/train.dfpwm",
    warning = "audio/approach/warning.dfpwm",

    approach_after_melody = {
        resolver = "config_path",
        directory = "audio/melody",
        configPath = "announcement.melody.approachAfterPath",
        defaultPath = "approach_after.dfpwm",
        enabled = {
            path = "announcement.melody.approachAfterEnabled",
            default = true,
        },
    },
}
