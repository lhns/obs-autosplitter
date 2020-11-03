obs = obslua

local enabled = false
local interval = 60

function script_description()
    return "AutoSplitter\nSplit recordings at a specific interval"
end

function getInterval(settings)
    local seconds = obs.obs_data_get_int(settings, "interval_s")
    local minutes = obs.obs_data_get_int(settings, "interval_m")
    local hours = obs.obs_data_get_int(settings, "interval_h")
    return hours, minutes, seconds
end

function setInterval(settings, hours, minutes, seconds)
    obs.obs_data_set_int(settings, "interval_s", seconds)
    obs.obs_data_set_int(settings, "interval_m", minutes)
    obs.obs_data_set_int(settings, "interval_h", hours)
end

function toSeconds(hours, minutes, seconds)
    return seconds + (minutes + hours * 60) * 60
end

function fromSeconds(interval)
    local seconds = interval % 60
    local minutes = math.floor(interval / 60) % 60
    local hours = math.floor(math.floor(interval / 60 / 60))
    return hours, minutes, seconds
end

local cancelCheck = function()
end
local cancelRestart = function()
end

function script_update(settings)
    enabled = obs.obs_data_get_bool(settings, "enabled")
    interval = toSeconds(getInterval(settings))
    if interval <= 0 then
        interval = 1
    end

    cancelCheck()
    cancelRestart()

    if enabled then
        cancelCheck = onRecordingChanged(
                function(recording)
                    if recording then
                        cancelRestart = timer(recording_restart, interval * 1000)
                    else
                        cancelRestart()
                    end
                end
        )
    end
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "enabled", enabled)

    local hours, minutes, seconds = fromSeconds(interval)
    obs.obs_data_set_default_int(settings, "interval_s", seconds)
    obs.obs_data_set_default_int(settings, "interval_m", minutes)
    obs.obs_data_set_default_int(settings, "interval_h", hours)
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "enabled", "Enabled")
    local prop_interval_s = obs.obs_properties_add_int(props, "interval_s", "Seconds", -1, 60, 1)
    local prop_interval_m = obs.obs_properties_add_int(props, "interval_m", "Minutes", -1, 60, 1)
    local prop_interval_h = obs.obs_properties_add_int(props, "interval_h", "Hours", 0, 240, 1)

    function validate(props, prop, settings)
        local hours, minutes, seconds = getInterval(settings)
        local interval = toSeconds(hours, minutes, seconds)
        if interval <= 0 then
            interval = 1
        end
        local newHours, newMinutes, newSecods = fromSeconds(interval)

        if hours == newHours and
                minutes == newMinutes and
                seconds == newSecods then
            return false
        else
            setInterval(settings, newHours, newMinutes, newSecods)
            return true
        end
    end

    obs.obs_property_set_modified_callback(prop_interval_s, validate)
    obs.obs_property_set_modified_callback(prop_interval_m, validate)
    obs.obs_property_set_modified_callback(prop_interval_h, validate)

    return props
end

function timer(func, millis)
    local cancelled = false

    obs.timer_add(
            function()
                if not cancelled then
                    func()
                else
                    obs.remove_current_callback()
                end
            end,
            millis
    )

    return function()
        cancelled = true
    end
end

function delay(func, millis)
    return timer(
            function()
                obs.remove_current_callback()
                func()
            end,
            millis
    )
end

function delayUntil(func, condition, millis)
    local cancel
    cancel = timer(
            function()
                if condition() then
                    cancel()
                    func()
                end
            end,
            millis
    )

    return cancel
end

function timerWhile(func, condition, millis)
    local cancel
    cancel = timer(
            function()
                if condition() then
                    func()
                else
                    cancel()
                end
            end,
            millis
    )

    return cancel
end

function recording_stopped(func)
    delayUntil(
            func,
            function()
                return not obs.obs_frontend_recording_active()
            end,
            10
    )
end

function recording_restart()
    if obs.obs_frontend_recording_active() and not obs.obs_frontend_recording_paused() then
        obs.obs_frontend_recording_stop()

        recording_stopped(
                function()
                    timerWhile(
                            function()
                                obs.obs_frontend_recording_start()
                            end,
                            function()
                                return not obs.obs_frontend_recording_active()
                            end,
                            10
                    )
                end
        )
    end
end

function onRecordingChanged(func)
    local recording = not obs.obs_frontend_recording_active()

    return timer(
            function()
                if recording ~= obs.obs_frontend_recording_active() then
                    recording = not recording
                    func(recording)
                end
            end,
            200
    )
end
