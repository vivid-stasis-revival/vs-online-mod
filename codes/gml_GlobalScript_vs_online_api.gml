// ============================================================================
// vs_online_api.gml — REST layer + identity + achievements + leaderboards
//
// All HTTP goes through the game's coroutine library:
//   __CoroutineAwaitAsync("http", cb)  (async event 62 -> "http")
// Identity is a guest player minted by POST /api/v1/players; the playerId +
// bearer token are persisted into the `vsonline` config file.
//
// COMPILER NOTE (important): the vsml loader compiles mod code with
// Underanalyzer, which does NOT capture enclosing-function arguments or `var`
// locals into anonymous functions — every "captured" name compiles to a
// `self.<name>` instance-variable read and crashes at runtime. Anonymous
// function bodies may therefore only reference: their own parameters, their
// own `var` locals, globals, or instance vars via `self`/object access.
// All cross-callback state here travels through dedicated global slots.
// ============================================================================

// --- low-level HTTP --------------------------------------------------------

// Fire an HTTP request; _on_done(ok, body, status) runs on completion.
function vs_http_request(_url, _method, _headers, _body, _on_done)
{
    if (_headers == undefined)
    {
        _headers = "Content-Type: application/json\r\n";
    }
    if (!variable_global_exists("vs_http_state"))
    {
        global.vs_http_state = { rid: -1, url: "", method: "", headers: "", body: "", on_done: undefined };
    }
    global.vs_http_state.url = _url;
    global.vs_http_state.method = _method;
    global.vs_http_state.headers = _headers;
    global.vs_http_state.body = _body;
    global.vs_http_state.on_done = _on_done;

    __CoroutineBegin(function()
    {
        var st = global.vs_http_state;
        st.rid = http_request(st.url, st.method, st.headers, st.body);
        __CoroutineAwaitAsync("http", function()
        {
            var st = global.vs_http_state;
            if (async_load[? "id"] != st.rid)
            {
                return false;
            }
            var status = async_load[? "status"];
            var text = async_load[? "result"];
            var cb = st.on_done;
            st.on_done = undefined;
            if (cb != undefined) { cb((status >= 200 && status < 300), text, status); }
            return true;
        });
    });
    __CoroutineEnd();
}

// GET a JSON object; _on_done(ok, data, status). _authed appends ?token=.
function vs_online_get_json(_path, _authed, _on_done)
{
    if (!variable_global_exists("vs_api_cb"))
    {
        global.vs_api_cb = { on_done: undefined };
    }
    global.vs_api_cb.on_done = _on_done;
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + _path;
    if (_authed && variable_struct_exists(cfg, "token"))
    {
        url += (string_pos("?", url) > 0 ? "&" : "?") + "token=" + cfg.token;
    }
    vs_http_request(url, "GET", "Accept: application/json\r\n", "", function(_ok, _text, _status)
    {
        var data = undefined;
        if (_ok)
        {
            try { data = json_parse(_text); } catch (_e) { }
        }
        var cb = global.vs_api_cb.on_done;
        global.vs_api_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, data, _status); }
    });
}

// POST a JSON body; _on_done(ok, data, status).
function vs_online_post_json(_path, _bodyStruct, _on_done)
{
    if (!variable_global_exists("vs_api_cb"))
    {
        global.vs_api_cb = { on_done: undefined };
    }
    global.vs_api_cb.on_done = _on_done;
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + _path;
    if (variable_struct_exists(cfg, "token"))
    {
        url += (string_pos("?", url) > 0 ? "&" : "?") + "token=" + cfg.token;
    }
    vs_http_request(url, "POST", "Content-Type: application/json\r\n", json_stringify(_bodyStruct), function(_ok, _text, _status)
    {
        var data = undefined;
        if (_ok)
        {
            try { data = json_parse(_text); } catch (_e) { }
        }
        var cb = global.vs_api_cb.on_done;
        global.vs_api_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, data, _status); }
    });
}

// --- identity --------------------------------------------------------------

function vs_online_token()
{
    var cfg = vs_online_get_config();
    return (variable_struct_exists(cfg, "token")) ? cfg.token : "";
}

function vs_online_player_id()
{
    var cfg = vs_online_get_config();
    return (variable_struct_exists(cfg, "playerId")) ? cfg.playerId : "";
}

function vs_online_player_name()
{
    var cfg = vs_online_get_config();
    return (variable_struct_exists(cfg, "name")) ? cfg.name : "";
}

// Mint a fresh guest identity and persist it into the vsonline config.
function vs_online_create_player(_on_done)
{
    if (!variable_global_exists("vs_identity_cb"))
    {
        global.vs_identity_cb = { on_done: undefined };
    }
    global.vs_identity_cb.on_done = _on_done;
    vs_online_post_json("/api/v1/players", { name: "" }, function(_ok, _data, _status)
    {
        if (_ok)
        {
            var cfg = vs_online_get_config();
            cfg.playerId = _data.playerId;
            cfg.token = _data.token;
            cfg.email = ""; // a fresh guest is not an account
            if (variable_struct_exists(_data, "name")) { cfg.name = _data.name; }
            if (variable_struct_exists(_data, "avatar")) { cfg.avatar = _data.avatar; }
            vs_online_save_config();
        }
        var cb = global.vs_identity_cb.on_done;
        global.vs_identity_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, _data); }
    });
}

// --- OAuth2 device flow (RFC 8628) + refresh token rotation -----------------
//
// The server mints short-lived access tokens (24h) plus 30-day refresh tokens
// through /oauth2/*. The game shows a user_code, the player approves it on the
// verification page in a browser, and the client polls /oauth2/token. On every
// boot, ensure_identity() tries grant_type=refresh_token first, so the account
// session survives without re-login.

// POST an x-www-form-urlencoded body to _path; _on_done(ok, parsedBody, status).
// Unlike the JSON helpers, the body is parsed even on 4xx so OAuth error codes
// (authorization_pending, slow_down, invalid_grant) are visible.
function vs_online_oauth_post(_path, _formBody, _on_done)
{
    if (!variable_global_exists("vs_oauth_post_cb"))
    {
        global.vs_oauth_post_cb = { on_done: undefined };
    }
    global.vs_oauth_post_cb.on_done = _on_done;
    var url = vs_online_server_url() + _path;
    vs_http_request(url, "POST", "Content-Type: application/x-www-form-urlencoded\r\n", _formBody, function(_ok, _text, _status)
    {
        var parsed = undefined;
        try { parsed = json_parse(_text); } catch (_e) { }
        var cb = global.vs_oauth_post_cb.on_done;
        global.vs_oauth_post_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, parsed, _status); }
    });
}

// POST /oauth2/device_authorization (client_id=game)
// _on_done(ok, {device_code, user_code, verification_uri, expires_in, interval})
function vs_online_oauth_start(_on_done)
{
    if (!variable_global_exists("vs_oauth_cb"))
    {
        global.vs_oauth_cb = { on_done: undefined };
    }
    global.vs_oauth_cb.on_done = _on_done;
    vs_online_oauth_post("/oauth2/device_authorization", "client_id=game", function(_ok, _data, _status)
    {
        var cb = global.vs_oauth_cb.on_done;
        global.vs_oauth_cb.on_done = undefined;
        if (cb == undefined) { return; }
        if (_ok && _data != undefined && variable_struct_exists(_data, "device_code"))
        {
            cb(true, _data);
        }
        else
        {
            cb(false, _data);
        }
    });
}

// Poll /oauth2/token (grant_type=device_code). The server answers 400 with an
// "error" field until the player approves: authorization_pending / slow_down.
function vs_online_oauth_poll(_deviceCode, _on_done)
{
    if (!variable_global_exists("vs_oauth_cb"))
    {
        global.vs_oauth_cb = { on_done: undefined };
    }
    global.vs_oauth_cb.on_done = _on_done;
    vs_online_oauth_post("/oauth2/token", "grant_type=device_code&device_code=" + _deviceCode + "&client_id=game", function(_ok, _data, _status)
    {
        var cb = global.vs_oauth_cb.on_done;
        global.vs_oauth_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, _data, _status); }
    });
}

// Exchange a refresh token for a new access+refresh pair (rotation).
function vs_online_oauth_refresh(_refreshToken, _on_done)
{
    if (!variable_global_exists("vs_oauth_cb"))
    {
        global.vs_oauth_cb = { on_done: undefined };
    }
    global.vs_oauth_cb.on_done = _on_done;
    vs_online_oauth_post("/oauth2/token", "grant_type=refresh_token&refresh_token=" + _refreshToken + "&client_id=game", function(_ok, _data, _status)
    {
        var cb = global.vs_oauth_cb.on_done;
        global.vs_oauth_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, _data, _status); }
    });
}

// Store an OAuth token pair (access_token + refresh_token) in the config.
function vs_online_apply_oauth_tokens(_data)
{
    var cfg = vs_online_get_config();
    cfg.token = _data.access_token;
    if (variable_struct_exists(_data, "refresh_token"))
    {
        cfg.refresh_token = _data.refresh_token;
    }
    vs_online_save_config();
}

// GET /players/me with the current token and refresh the cached name/avatar.
// Uses its own slot (vs_me_cb) so it can be nested inside ensure_identity.
function vs_online_refresh_me(_on_done)
{
    if (!variable_global_exists("vs_me_cb"))
    {
        global.vs_me_cb = { on_done: undefined };
    }
    global.vs_me_cb.on_done = _on_done;
    vs_online_get_json("/api/v1/players/me", true, function(_ok, _data, _status)
    {
        var cb = global.vs_me_cb.on_done;
        global.vs_me_cb.on_done = undefined;
        if (_ok && _data != undefined)
        {
            var cfg = vs_online_get_config();
            if (variable_struct_exists(_data, "name")) { cfg.name = _data.name; }
            if (variable_struct_exists(_data, "avatar")) { cfg.avatar = _data.avatar; }
            vs_online_save_config();
        }
        if (cb != undefined) { cb(_ok, _data); }
    });
}

// Reuse a stored identity: refresh token first (device flow), then plain
// bearer token, then fall back to a fresh guest.
function vs_online_ensure_identity(_on_done)
{
    var cfg = vs_online_get_config();
    if (variable_struct_exists(cfg, "refresh_token") && cfg.refresh_token != "")
    {
        if (!variable_global_exists("vs_identity_cb"))
        {
            global.vs_identity_cb = { on_done: undefined };
        }
        global.vs_identity_cb.on_done = _on_done;
        vs_online_oauth_refresh(cfg.refresh_token, function(_ok, _data, _status)
        {
            if (_ok && _data != undefined && variable_struct_exists(_data, "access_token"))
            {
                // Rotated successfully: persist the new pair, then refresh the
                // cached profile and resume the original continuation.
                vs_online_apply_oauth_tokens(_data);
                vs_online_refresh_me(function(_ok2, _data2)
                {
                    var cb = global.vs_identity_cb.on_done;
                    global.vs_identity_cb.on_done = undefined;
                    if (cb != undefined) { cb(_ok2, _data2); }
                });
                return;
            }
            // Refresh token rejected: drop it and fall through to the plain
            // bearer/guest path.
            var cb = global.vs_identity_cb.on_done;
            global.vs_identity_cb.on_done = undefined;
            var cfg2 = vs_online_get_config();
            cfg2.refresh_token = "";
            vs_online_save_config();
            if (cb != undefined) { vs_online_ensure_identity(cb); }
        });
        return;
    }
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        if (!variable_global_exists("vs_identity_cb"))
        {
            global.vs_identity_cb = { on_done: undefined };
        }
        global.vs_identity_cb.on_done = _on_done;
        vs_online_get_json("/api/v1/players/me", true, function(_ok, _data, _status)
        {
            var cfg = vs_online_get_config();
            var cb = global.vs_identity_cb.on_done;
            global.vs_identity_cb.on_done = undefined;
            if (_ok)
            {
                if (variable_struct_exists(_data, "name") && cfg.name == "") { cfg.name = _data.name; }
                if (variable_struct_exists(_data, "avatar")) { cfg.avatar = _data.avatar; }
                if (cb != undefined) { cb(true, _data); }
            }
            else
            {
                // Token rejected (revoked/expired): fall back to a fresh guest.
                if (cb != undefined) { vs_online_create_player(cb); }
            }
        });
    }
    else
    {
        vs_online_create_player(_on_done);
    }
}

// --- account auth (email + password via /api/v1/auth/*) --------------------

// Write a server-issued identity into the vsonline config (account login).
function vs_online_apply_identity(_data, _email)
{
    var cfg = vs_online_get_config();
    cfg.playerId = _data.playerId;
    cfg.token = _data.token;
    cfg.email = _email;
    if (variable_struct_exists(_data, "name")) { cfg.name = _data.name; }
    if (variable_struct_exists(_data, "avatar")) { cfg.avatar = _data.avatar; }
    vs_online_save_config();
}

// Drop the stored identity (used on logout; a fresh guest is minted next boot
// or right after, so the current session keeps working).
function vs_online_drop_identity()
{
    var cfg = vs_online_get_config();
    cfg.playerId = "";
    cfg.token = "";
    cfg.email = "";
    cfg.refresh_token = "";
    vs_online_save_config();
}

// POST /api/v1/auth/login {email, password} -> {playerId, name, avatar, token}
// On success the identity is persisted; _on_done(ok, data).
function vs_online_auth_login(_email, _password, _on_done)
{
    if (!variable_global_exists("vs_auth_cb"))
    {
        global.vs_auth_cb = { on_done: undefined, email: "" };
    }
    global.vs_auth_cb.on_done = _on_done;
    global.vs_auth_cb.email = _email;
    vs_online_post_json("/api/v1/auth/login", { email: _email, password: _password }, function(_ok, _data, _status)
    {
        if (_ok && _data != undefined)
        {
            vs_online_apply_identity(_data, global.vs_auth_cb.email);
        }
        var cb = global.vs_auth_cb.on_done;
        global.vs_auth_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, _data); }
    });
}

// POST /api/v1/auth/register {email, password, name?} -> identity
function vs_online_auth_register(_email, _password, _name, _on_done)
{
    if (!variable_global_exists("vs_auth_cb"))
    {
        global.vs_auth_cb = { on_done: undefined, email: "" };
    }
    global.vs_auth_cb.on_done = _on_done;
    global.vs_auth_cb.email = _email;
    vs_online_post_json("/api/v1/auth/register", { email: _email, password: _password, name: _name }, function(_ok, _data, _status)
    {
        if (_ok && _data != undefined)
        {
            vs_online_apply_identity(_data, global.vs_auth_cb.email);
        }
        var cb = global.vs_auth_cb.on_done;
        global.vs_auth_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok, _data); }
    });
}

// POST /api/v1/auth/logout (best-effort), then drop the local identity so a
// fresh guest is minted afterwards. _on_done(ok).
function vs_online_auth_logout(_on_done)
{
    if (!variable_global_exists("vs_auth_cb"))
    {
        global.vs_auth_cb = { on_done: undefined };
    }
    global.vs_auth_cb.on_done = _on_done;
    var cfg = vs_online_get_config();
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        vs_online_post_json("/api/v1/auth/logout", {}, function(_ok, _data, _status)
        {
            vs_online_drop_identity();
            var cb = global.vs_auth_cb.on_done;
            global.vs_auth_cb.on_done = undefined;
            if (cb != undefined) { cb(_ok); }
        });
    }
    else
    {
        vs_online_drop_identity();
        var cb = global.vs_auth_cb.on_done;
        global.vs_auth_cb.on_done = undefined;
        if (cb != undefined) { cb(true); }
    }
}

// Human-readable auth state, shown as the option description in Settings.
function vs_online_auth_status_text()
{
    var cfg = vs_online_get_config();
    if (!vs_online_is_custom())
    {
        return "Custom Server is off - enable it above to sign in.";
    }
    var conn = "server ?";
    switch (vs_online_conn_state())
    {
        case 1: conn = "online"; break;
        case -1: conn = "offline"; break;
    }
    if (vs_online_is_account())
    {
        if (variable_struct_exists(cfg, "email") && cfg.email != "")
        {
            var nm = (variable_struct_exists(cfg, "name") && cfg.name != "") ? cfg.name : "Player";
            return "Signed in: " + nm + " (" + cfg.email + ")  [" + conn + "]";
        }
        return "Signed in (device flow)  [" + conn + "]";
    }
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
        return "Guest / not logged in - online features disabled, only play downloaded charts.  [" + conn + "]";
    return "Not signed in yet - log in to use online features.";
}

// --- achievements ----------------------------------------------------------
// Guests / not-logged-in players may not touch the server: only playing
// locally-downloaded charts is allowed. Account sessions pass through.

function vs_online_unlock_achievement(_name)
{
    if (!vs_online_is_account()) return;
    vs_online_post_json("/api/v1/players/me/achievements/" + _name, {}, function(_ok, _data, _status) { });
}

function vs_online_clear_achievement(_name)
{
    if (!vs_online_is_account()) return;
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + "/api/v1/players/me/achievements/" + _name + "?token=" + cfg.token;
    vs_http_request(url, "DELETE", "", "", function(_ok, _text, _status) { });
}

// --- per-chart leaderboards (/charts/scores) -------------------------------
// Name-based /leaderboards/* are deprecated on vs-server-go main (501). Scores
// are per-chart + per-difficulty, versioned by the chart's sha1:
//   POST /charts/scores {chartId, difficulty, sha1, score, data}
//   GET  /charts/scores?chartId=&difficulty=&sha1=&start=&end=
//        -> { entries:[{rank,score,playerId,uploadedAt}], sha1 }

function vs_online_upload_score(_chartId, _difficulty, _sha1, _score, _data)
{
    if (!vs_online_is_account()) return;
    var body = { chartId: _chartId, difficulty: _difficulty, sha1: _sha1, score: _score };
    if (_data != undefined && _data != "")
    {
        body.data = _data;
    }
    vs_online_post_json("/api/v1/charts/scores", body, function(_ok, _data, _status) { });
}

// _on_done(data) = { entries:[...], sha1 } or undefined on failure / guest.
function vs_online_download_scores(_chartId, _difficulty, _sha1, _start, _end, _on_done)
{
    if (!vs_online_is_account())
    {
        if (_on_done != undefined) { _on_done(undefined); }
        return;
    }
    if (!variable_global_exists("vs_score_cb"))
    {
        global.vs_score_cb = { on_done: undefined };
    }
    global.vs_score_cb.on_done = _on_done;
    var url = "/api/v1/charts/scores?chartId=" + _chartId
            + "&difficulty=" + _difficulty
            + "&start=" + string(_start)
            + "&end=" + string(_end);
    if (_sha1 != undefined && _sha1 != "")
    {
        url += "&sha1=" + _sha1;
    }
    vs_online_get_json(url, false, function(_ok, _data, _status)
    {
        var cb = global.vs_score_cb.on_done;
        global.vs_score_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok ? _data : undefined); }
    });
}

// GET /charts/scores/friends?chartId=&difficulty=&sha1=  (auth)
// -> { entries:[{rank,score,playerId,uploadedAt,name?,avatar?}], sha1 }
// Friends + self only.
function vs_online_download_friends_scores(_chartId, _difficulty, _sha1, _on_done)
{
    if (!vs_online_is_account())
    {
        if (_on_done != undefined) { _on_done(undefined); }
        return;
    }
    if (!variable_global_exists("vs_score_cb"))
    {
        global.vs_score_cb = { on_done: undefined };
    }
    global.vs_score_cb.on_done = _on_done;
    var url = "/api/v1/charts/scores/friends?chartId=" + _chartId
            + "&difficulty=" + _difficulty;
    if (_sha1 != undefined && _sha1 != "")
    {
        url += "&sha1=" + _sha1;
    }
    vs_online_get_json(url, true, function(_ok, _data, _status)
    {
        var cb = global.vs_score_cb.on_done;
        global.vs_score_cb.on_done = undefined;
        if (cb != undefined) { cb(_ok ? _data : undefined); }
    });
}

// --- score suffix isolation ------------------------------------------------

// Custom-server scores live in a separate highscore file tagged with the
// server address, so they never pollute the vanilla save. Also lets different
// servers keep distinct score tables.
function vs_online_highscore_file(_orig)
{
    if (vs_online_is_custom())
    {
        return _orig + "_vson" + string(abs(string_hash(vs_online_server_url())));
    }
    return _orig;
}
