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

function script_update(settings)
    enabled = obs.obs_data_get_bool(settings, "enabled")
    interval = toSeconds(getInterval(settings))
    if interval <= 0 then
        interval = 1
    end

    function doRestart()
        if enabled then
            recording_restart()
        end
    end

    check_recording(
            function()
                obs.timer_remove(doRestart)
                if enabled then
                    obs.timer_add(doRestart, interval * 1000)
                end
            end,
            function()
                obs.timer_remove(doRestart)
            end
    )
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

function runAfter(millis, callback)
    obs.timer_add(
            function()
                obs.remove_current_callback()
                callback()
            end,
            millis
    )
end

function runWhen(interval, condition, callback)
    obs.timer_add(
            function()
                if condition() then
                    obs.remove_current_callback()
                    callback()
                end
            end,
            interval
    )
end

function runWhile(interval, condition, callback)
    obs.timer_add(
            function()
                if condition() then
                    callback()
                else
                    obs.remove_current_callback()
                end
            end,
            interval
    )
end

function recording_stopped(callback)
    runWhen(
            10,
            function()
                return not obs.obs_frontend_recording_active()
            end,
            callback
    )
end

function recording_restart()
    if obs.obs_frontend_recording_active() then
        obs.obs_frontend_recording_stop()

        recording_stopped(
                function()
                    runWhile(
                            10,
                            function()
                                return not obs.obs_frontend_recording_active()
                            end,
                            function()
                                obs.obs_frontend_recording_start()
                            end
                    )
                end
        )
    end
end

function check_recording(onStart, onStop)
    function check_active()
        if obs.obs_frontend_recording_active() then
            obs.remove_current_callback()
            obs.timer_add(check_inactive, 200)
            onStart()
        end
    end

    function check_inactive()
        if not obs.obs_frontend_recording_active() then
            obs.remove_current_callback()
            obs.timer_add(check_active, 200)
            onStop()
        end
    end

    obs.timer_remove(check_active)
    obs.timer_remove(check_inactive)
    obs.timer_add(check_active, 200)
end
