import obspython as obs

enabled = False
interval = 60


def script_description():
    return "Restarts recording"


def script_update(settings):
    global enabled
    global interval

    enabled = obs.obs_data_get_bool(settings, "enabled")

    interval = get_interval(settings)
    if interval == 0:
        interval = 1

    def doRestart():
        if enabled:
            recording_restart()

    def onStart():
        obs.timer_remove(doRestart)
        if enabled:
            obs.timer_add(doRestart, interval * 1000)

    def onStop():
        obs.timer_remove(doRestart)

    check_recording(onStart, onStop)


def script_defaults(settings):
    global enabled
    global interval

    obs.obs_data_set_default_bool(settings, "enabled", enabled)
    obs.obs_data_set_default_int(settings, "interval_s", interval % 60)
    obs.obs_data_set_default_int(settings, "interval_m", int(interval / 60))
    obs.obs_data_set_default_int(settings, "interval_h", int(int(interval / 60) / 60))


def script_properties():
    props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "enabled", "Enabled")
    prop_interval_s = obs.obs_properties_add_int(props, "interval_s", "Seconds", 0, 59, 1)
    prop_interval_m = obs.obs_properties_add_int(props, "interval_m", "Minutes", 0, 59, 1)
    prop_interval_h = obs.obs_properties_add_int(props, "interval_h", "Hours", 0, 240, 1)

    def validate(props, prop, settings):
        if get_interval(settings) == 0:
            obs.obs_data_set_int(settings, "interval_s", 1)
            return True
        else:
            return False

    obs.obs_property_set_modified_callback(prop_interval_s, validate)
    obs.obs_property_set_modified_callback(prop_interval_m, validate)
    obs.obs_property_set_modified_callback(prop_interval_h, validate)

    return props


# ------------------------------------------------------------

def runAfter(millis, callback):
    def do():
        obs.remove_current_callback()
        callback()

    obs.timer_add(do, millis)


def runWhen(interval, condition, callback):
    def check():
        if condition():
            obs.remove_current_callback()
            callback()

    obs.timer_add(check, interval)


def runWhile(interval, condition, callback):
    def check():
        if condition():
            callback()
        else:
            obs.remove_current_callback()

    obs.timer_add(check, interval)


def recording_stopped(callback):
    runWhen(10, lambda: not obs.obs_frontend_recording_active(), callback)


def recording_restart():
    if obs.obs_frontend_recording_active():
        obs.obs_frontend_recording_stop()
        recording_stopped(lambda: runWhile(
            10,
            lambda: not obs.obs_frontend_recording_active(),
            lambda: obs.obs_frontend_recording_start()
        ))


def check_recording(onStart, onStop):
    def check_active():
        if obs.obs_frontend_recording_active():
            obs.remove_current_callback()
            obs.timer_add(check_inactive, 200)
            onStart()

    def check_inactive():
        if not obs.obs_frontend_recording_active():
            obs.remove_current_callback()
            obs.timer_add(check_active, 200)
            onStop()

    obs.timer_remove(check_active)
    obs.timer_remove(check_inactive)
    obs.timer_add(check_active, 200)


def get_interval(settings):
    interval_s = obs.obs_data_get_int(settings, "interval_s")
    interval_m = obs.obs_data_get_int(settings, "interval_m")
    interval_h = obs.obs_data_get_int(settings, "interval_h")
    return interval_s + (interval_m + interval_h * 60) * 60

# ------------------------------------------------------------
