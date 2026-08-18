// VS Online account panel — Create
// Modal shown from Settings -> VS Online -> "VS Online Account".
// Two views:
//   - signed out: OAuth2 device flow (RFC 8628) — the server hands out a
//     user_code + verification URL, the player approves it in a browser, the
//     panel polls /oauth2/token until the access+refresh pair arrives.
//   - signed in: account summary (name / playerId) with Sign out.
// All network calls go through vs_online_oauth_* which use global slots, so no
// closure capture is needed anywhere in this object.
depth = -10000;

cfg = vs_online_get_config();
signed_in = (variable_struct_exists(cfg, "refresh_token") && cfg.refresh_token != "")
         || (variable_struct_exists(cfg, "email") && cfg.email != "");

// device-flow state
stage = 0;            // 0 = idle, 1 = waiting for approval, 2 = finished/error
device_code = "";
user_code = "";
verification_uri = "";
expires_at = 0;       // unix seconds when the user_code expires
poll_at = 0;          // game current_time (ms) when the next poll is due
interval = 5;         // seconds between polls
message = "";
busy = false;

// account view state
sel = 0;

// --- device flow ------------------------------------------------------------

self.flow_started = function(_ok, _data)
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
};

self.flow_polled = function(_ok, _data, _status)
{
    if (_ok && _data != undefined && variable_struct_exists(_data, "access_token"))
    {
        // Approved! Persist the token pair, refresh the profile, close.
        stage = 2;
        message = "Signed in!";
        vs_online_apply_oauth_tokens(_data);
        vs_online_refresh_me(method(self, function(_ok2, _data2)
        {
            play_se(sfx_songsel_select);
            instance_destroy();
        }));
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
    // terminal failure: invalid_grant, expired_token, network error...
    stage = 0;
    message = "Device flow failed (" + err + ") - press Enter to restart.";
};

self.start_flow = function()
{
    if (busy) { return; }
    busy = true;
    stage = 1;
    message = "Requesting device code...";
    vs_online_oauth_start(method(self, flow_started));
};

// --- account view -----------------------------------------------------------

self.auth_done = function(_ok, _data)
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
        vs_online_ensure_identity(method(self, function(_ok2, _data2)
        {
            instance_destroy();
        }));
    }
};

self.do_signout = function()
{
    if (busy) { return; }
    busy = true;
    message = "Signing out...";
    vs_online_auth_logout(method(self, auth_done));
};

// kick off the flow when opened while signed out
if (!signed_in)
{
    start_flow();
}
