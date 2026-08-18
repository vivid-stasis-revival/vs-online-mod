// ============================================================================
// vs_auth.gml — vs_auth_panel actions as named scripts.
// Object-event anonymous functions cannot call mod GlobalScripts.
// ============================================================================

function vs_auth_flow_started(_ok, _data)
{
    busy = false;
    if (_ok && _data != undefined)
    {
        stage = 1;
        device_code = _data.device_code;
        user_code = _data.user_code;
        verification_uri = variable_struct_exists(_data, "verification_uri") ? _data.verification_uri : "";
        expires_at = current_time / 1000 + (variable_struct_exists(_data, "expires_in") ? _data.expires_in : 600);
        interval = variable_struct_exists(_data, "interval") ? max(_data.interval, 5) : 5;
        poll_at = current_time + interval * 1000;
        message = "Waiting for approval...";
        play_se(sfx_songsel_select);
    }
    else
    {
        stage = 0;
        message = "Could not start device flow. Is the server reachable?";
    }
}

function vs_auth_on_me(_ok2, _data2)
{
    play_se(sfx_songsel_select);
    instance_destroy();
}

function vs_auth_flow_polled(_ok, _data, _status)
{
    if (_ok && _data != undefined && variable_struct_exists(_data, "access_token"))
    {
        stage = 2;
        message = "Signed in!";
        vs_online_apply_oauth_tokens(_data);
        vs_online_refresh_me(method(self, vs_auth_on_me));
        return;
    }
    var err = "";
    if (_data != undefined && variable_struct_exists(_data, "error"))
    {
        err = string(_data.error);
    }
    if (err == "authorization_pending")
    {
        poll_at = current_time + interval * 1000;
        message = "Waiting for approval...";
        return;
    }
    if (err == "slow_down")
    {
        interval += 5;
        poll_at = current_time + interval * 1000;
        message = "Slow down - retrying...";
        return;
    }
    stage = 0;
    message = "Device flow failed (" + err + ") - press Enter to restart.";
}

function vs_auth_on_poll(_ok, _data, _status)
{
    busy = false;
    vs_auth_flow_polled(_ok, _data, _status);
}

function vs_auth_start_flow()
{
    if (busy) return;
    busy = true;
    stage = 1;
    message = "Requesting device code...";
    vs_online_oauth_start(method(self, vs_auth_flow_started));
}

function vs_auth_after_signout(_ok2, _data2)
{
    instance_destroy();
}

function vs_auth_auth_done(_ok, _data)
{
    busy = false;
    if (_ok)
    {
        play_se(sfx_songsel_select);
        instance_destroy();
    }
    else
    {
        message = "Sign-out failed (server unreachable?) - local session cleared anyway.";
        vs_online_drop_identity();
        vs_online_ensure_identity(method(self, vs_auth_after_signout));
    }
}

function vs_auth_do_signout()
{
    if (busy) return;
    busy = true;
    message = "Signing out...";
    vs_online_auth_logout(method(self, vs_auth_auth_done));
}
