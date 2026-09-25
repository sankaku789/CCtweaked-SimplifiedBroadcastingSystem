local SOURCE = debug.getinfo(1, "S").source
local ROOT = SOURCE:sub(1, 1) == "@" and fs.getDir(SOURCE:sub(2)) or ""
if ROOT == "" then ROOT = "." end

package.path = table.concat({
    fs.combine(ROOT, "?.lua"),
    fs.combine(ROOT, "src/?.lua"),
    fs.combine(ROOT, "src/?/init.lua"),
    package.path,
}, ";")

local config = require("config")

local failures = 0
while true do
    local startedAt = os.epoch("utc")
    local ok, err = pcall(function()
        package.loaded["app"] = nil
        require("app").run()
    end)

    if ok then return end

    -- Treat a user-requested Ctrl+T termination as a normal shutdown.
    if tostring(err) == "Terminated" then
        return
    end

    local runtime = config.runtime or {}
    local stableMs = math.max(0, tonumber(runtime.stableRunSeconds) or 60) * 1000
    if os.epoch("utc") - startedAt >= stableMs then failures = 0 end
    failures = failures + 1

    printError("Simplified Broadcasting System crashed: " .. tostring(err))
    if failures >= (tonumber(runtime.maxConsecutiveFailures) or 5) then
        printError("Too many consecutive failures; startup stopped.")
        return
    end

    sleep(math.max(0, tonumber(runtime.restartDelaySeconds) or 5))
end
