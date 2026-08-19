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
// All cross-callback state here travels through dedicated global slots /
// FIFO queues (one HTTP request in flight; jobs carry their own on_done).
// ============================================================================

// --- URL / headers ---------------------------------------------------------

function vs_online_url_encode(_s)
{
    if (_s == undefined) return "";
    var raw = string(_s);
    var buf = buffer_create(string_byte_length(raw) + 1, buffer_fixed, 1);
    buffer_write(buf, buffer_string, raw);
    buffer_seek(buf, buffer_seek_start, 0);
    var out = "";
    var hex = "0123456789ABCDEF";
    var n = string_byte_length(raw);
    repeat (n)
    {
        var b = buffer_read(buf, buffer_u8);
        if ((b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
            || b == 45 || b == 46 || b == 95 || b == 126)
        {
            out += chr(b);
        }
        else
        {
            out += "%" + string_char_at(hex, (b >> 4) + 1) + string_char_at(hex, (b & 15) + 1);
        }
    }
    buffer_delete(buf);
    return out;
}

function vs_online_diff_api(_diff)
{
    var d = string_lower(string(_diff));
    if (d == "opening" || d == "middle" || d == "finale" || d == "encore" || d == "prelude")
    {
        return d;
    }
    return string(_diff);
}

function vs_online_chart_sha1(_chartId, _diff)
{
    if (_chartId == undefined || _chartId == "" || _diff == undefined || _diff == "") return "";
    var fileDiff = _diff;
    var low = string_lower(string(_diff));
    if (low == "opening") fileDiff = "OPENING";
    else if (low == "middle") fileDiff = "MIDDLE";
    else if (low == "finale") fileDiff = "FINALE";
    else if (low == "encore") fileDiff = "ENCORE";
    else if (low == "prelude") fileDiff = "PRELUDE";
    var loadDir = vs_csm_load_dir_from_id(_chartId);
    var p = "";
    if (loadDir != "")
    {
        p = loadDir + fileDiff + ".vsc";
        if (!file_exists(p)) p = loadDir + fileDiff + ".vsb";
    }
    if (p == "" || !file_exists(p))
    {
        var dir = "Custom Songs/" + _chartId + "/";
        p = dir + fileDiff + ".vsc";
        if (!file_exists(p)) p = dir + fileDiff + ".vsb";
    }
    if (!file_exists(p)) p = working_directory + "Charts/" + _chartId + "/" + fileDiff + ".vsb";
    if (!file_exists(p)) p = working_directory + "Charts/" + _chartId + "/" + fileDiff + ".vsc";
    if (!file_exists(p)) return "";
    return sha1_file(p);
}

function vs_online_get_my_chart_score(_chartId, _difficulty, _sha1, _on_done)
{
    if (!vs_online_is_account())
    {
        if (_on_done != undefined) { _on_done(false, undefined, 0); }
        return;
    }
    var url = "/api/v1/charts/scores/me?chartId=" + vs_online_url_encode(_chartId)
            + "&difficulty=" + vs_online_url_encode(vs_online_diff_api(_difficulty));
    if (_sha1 != undefined && _sha1 != "")
    {
        url += "&sha1=" + vs_online_url_encode(_sha1);
    }
    vs_online_get_json(url, true, _on_done);
}

function vs_http_headers_create(_spec)
{
    var hdr = ds_map_create();
    if (_spec == undefined)
    {
        ds_map_add(hdr, "Content-Type", "application/json");
        return hdr;
    }
    if (is_struct(_spec))
    {
        var names = variable_struct_get_names(_spec);
        var i = 0;
        repeat (array_length(names))
        {
            ds_map_add(hdr, names[i], string(variable_struct_get(_spec, names[i])));
            i++;
        }
        return hdr;
    }
    if (is_string(_spec) && _spec != "")
    {
        var raw = string_replace_all(_spec, "\r\n", "\n");
        var start = 1;
        var len = string_length(raw);
        while (start <= len)
        {
            var nl = string_pos_ext("\n", raw, start);
            var line = (nl <= 0) ? string_copy(raw, start, len) : string_copy(raw, start, nl - start);
            start = (nl <= 0) ? (len + 1) : (nl + 1);
            var colon = string_pos(":", line);
            if (colon > 0)
            {
                var k = string_replace_all(string_copy(line, 1, colon - 1), " ", "");
                var v = string_replace_all(string_copy(line, colon + 1, string_length(line)), "\r", "");
                while (string_pos(" ", v) == 1) v = string_delete(v, 1, 1);
                if (k != "") ds_map_add(hdr, k, v);
            }
        }
        return hdr;
    }
    return hdr;
}

function vs_http_q_init()
{
    if (!variable_global_exists("vs_http_q"))
    {
        global.vs_http_q = [];
        global.vs_http_busy = false;
        global.vs_http_cur = undefined;
        global.vs_http_gen = 0;
        global.vs_http_to = [];
    }
}

function vs_http_default_timeout()
{
    return 10000;
}

function vs_http_timeout_ms()
{
    var job = global.vs_http_cur;
    if (job != undefined && variable_struct_exists(job, "failed") && job.failed)
    {
        return 0;
    }
    if (job != undefined && variable_struct_exists(job, "timeout") && job.timeout > 0)
    {
        return job.timeout;
    }
    return vs_http_default_timeout();
}

// Fire an HTTP request. _on_done(ok, bodyOrJson, httpStatus).
// Jobs are serialized (one in flight) so callbacks cannot clobber each other.
function vs_http_request(_url, _method, _headers, _body, _on_done)
{
    vs_http_request_ex(_url, _method, _headers, _body, _on_done, false, "", "");
}

function vs_http_request_ex(_url, _method, _headers, _body, _on_done, _json, _after, _email, _timeout)
{
    vs_http_q_init();
    var to = vs_http_default_timeout();
    if (_timeout != undefined && _timeout > 0)
    {
        to = _timeout;
    }
    array_push(global.vs_http_q,
    {
        url: _url,
        method: _method,
        headers: _headers,
        body: (_body == undefined) ? "" : _body,
        on_done: _on_done,
        json: _json,
        after: (_after == undefined) ? "" : _after,
        email: (_email == undefined) ? "" : _email,
        timeout: to,
        rid: -1,
        hdr: undefined
    });
    vs_http_pump();
}

function vs_http_pump()
{
    vs_http_q_init();
    if (global.vs_http_busy) return;
    if (array_length(global.vs_http_q) == 0) return;
    global.vs_http_busy = true;
    global.vs_http_cur = global.vs_http_q[0];
    array_delete(global.vs_http_q, 0, 1);
    vs_http_start_current();
    var job = global.vs_http_cur;
    if (job == undefined) return;
    if (variable_struct_exists(job, "failed") && job.failed)
    {
        vs_http_complete(job, false, "", -1);
        return;
    }
    if (!variable_global_exists("vs_http_gen"))
    {
        global.vs_http_gen = 0;
        global.vs_http_to = [];
    }
    global.vs_http_gen += 1;
    job.gen = global.vs_http_gen;
    array_push(global.vs_http_to, job.gen);
    var frames = max(1, round(vs_http_timeout_ms() * 60 / 1000));
    call_later(frames, time_source_units_frames, vs_http_on_timeout);
}

function vs_http_start_current()
{
    var job = global.vs_http_cur;
    if (job == undefined)
    {
        global.vs_http_busy = false;
        return;
    }
    var hdr = vs_http_headers_create(job.headers);
    job.hdr = hdr;
    job.rid = http_request(job.url, job.method, hdr, job.body);
    if (job.rid == undefined || job.rid < 0)
    {
        job.rid = -1;
        job.failed = true;
        show_debug_message("VS Online: HTTP failed to start " + string(job.method) + " " + string(job.url));
        return;
    }
    job.failed = false;
    show_debug_message("VS Online: HTTP start " + string(job.method) + " " + string(job.url) + " rid=" + string(job.rid));
}

function vs_http_on_timeout()
{
    vs_http_q_init();
    if (!variable_global_exists("vs_http_to") || array_length(global.vs_http_to) == 0) return;
    var g = global.vs_http_to[0];
    array_delete(global.vs_http_to, 0, 1);
    var job = global.vs_http_cur;
    if (job == undefined) return;
    if (!variable_struct_exists(job, "gen") || job.gen != g) return;
    show_debug_message("VS Online: HTTP timeout " + string(job.method) + " " + string(job.url));
    vs_http_complete(job, false, "", -1);
}

// GameMaker HTTP async:
//   status      — 1 = still downloading, 0 = finished, <0 = transport error
//   http_status — actual HTTP code (200 / 201 / 404 / ...)
// Coroutine timeout invokes this with async_load == -1.
function vs_http_on_async()
{
    // File downloads share this official HTTP event. Handle them here so a
    // missed codepatch line cannot leave http_get_file waiting forever.
    vs_songstore_on_http();
    vs_media_on_http();
    var job = global.vs_http_cur;
    if (job == undefined)
    {
        return true;
    }
    if (variable_struct_exists(job, "failed") && job.failed)
    {
        vs_http_complete(job, false, "", -1);
        return true;
    }
    if (async_load == -1)
    {
        show_debug_message("VS Online: HTTP timeout " + string(job.method) + " " + string(job.url));
        vs_http_complete(job, false, "", -1);
        return true;
    }
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || rid != job.rid)
    {
        return false;
    }
    var gmStatus = ds_map_find_value(async_load, "status");
    var httpStatus = ds_map_find_value(async_load, "http_status");
    var text = ds_map_find_value(async_load, "result");
    if (gmStatus == 1)
    {
        var cl = ds_map_find_value(async_load, "contentLength");
        var got = ds_map_find_value(async_load, "sizeDownloaded");
        if (cl != undefined && got != undefined && real(got) < real(cl))
        {
            return false;
        }
        if ((text == undefined || text == "") && (httpStatus == undefined || httpStatus < 200))
        {
            return false;
        }
    }
    if (httpStatus == undefined)
    {
        httpStatus = (gmStatus < 0) ? gmStatus : 200;
    }
    var ok = (gmStatus >= 0 && httpStatus >= 200 && httpStatus < 300);
    show_debug_message("VS Online: HTTP done " + string(job.method) + " " + string(job.url) + " http=" + string(httpStatus) + " ok=" + string(ok));
    vs_http_complete(job, ok, text, httpStatus);
    return true;
}

function vs_http_complete(_job, _ok, _text, _status)
{
    if (_job == undefined) return;
    if (global.vs_http_cur != _job) return;
    if (_job.hdr != undefined)
    {
        ds_map_destroy(_job.hdr);
        _job.hdr = undefined;
    }
    global.vs_http_busy = false;
    global.vs_http_cur = undefined;
    vs_http_finish(_job, _ok, _text, _status);
    vs_http_pump();
}

function vs_http_finish(_job, _ok, _text, _status)
{
    var data = _text;
    if (_job.json)
    {
        data = undefined;
        if (_text != undefined && _text != "")
        {
            try { data = json_parse(_text); } catch (_e) { }
        }
    }
    var after = _job.after;
    var cb = _job.on_done;
    if (after == "create_player")
    {
        if (_ok && data != undefined)
        {
            var cfg = vs_online_get_config();
            cfg.playerId = data.playerId;
            cfg.token = data.token;
            cfg.email = "";
            if (variable_struct_exists(data, "name")) { cfg.name = data.name; }
            if (variable_struct_exists(data, "avatar")) { cfg.avatar = data.avatar; }
            vs_online_save_config();
        }
        if (cb != undefined) { cb(_ok, data); }
        return;
    }
    if (after == "refresh_me")
    {
        if (_ok && data != undefined)
        {
            vs_online_apply_me(data);
        }
        if (cb != undefined) { cb(_ok, data); }
        return;
    }
    if (cb != undefined) { cb(_ok, data, _status); }
}

// GET a JSON object; _on_done(ok, data, status). _authed appends ?token=.
function vs_online_get_json(_path, _authed, _on_done, _timeout)
{
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + _path;
    if (_authed && variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        url += (string_pos("?", url) > 0 ? "&" : "?") + "token=" + vs_online_url_encode(cfg.token);
    }
    vs_http_request_ex(url, "GET", { Accept: "application/json" }, "", _on_done, true, "", "", _timeout);
}

// POST a JSON body; _on_done(ok, data, status).
function vs_online_post_json(_path, _bodyStruct, _on_done)
{
    vs_online_post_json_ex(_path, _bodyStruct, _on_done, "");
}

function vs_online_post_json_ex(_path, _bodyStruct, _on_done, _after)
{
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + _path;
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        url += (string_pos("?", url) > 0 ? "&" : "?") + "token=" + vs_online_url_encode(cfg.token);
    }
    vs_http_request_ex(url, "POST", "Content-Type: application/json\r\n", json_stringify(_bodyStruct), _on_done, true, _after, "");
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

// Persist /players/me into the local config. OAuth login only stored tokens
// before — missing playerId made Worldcross show Disconnected and broke host checks.
function vs_online_apply_me(_data)
{
    if (_data == undefined) return;
    var cfg = vs_online_get_config();
    if (variable_struct_exists(_data, "playerId") && _data.playerId != "")
    {
        cfg.playerId = _data.playerId;
    }
    if (variable_struct_exists(_data, "name") && _data.name != "")
    {
        cfg.name = _data.name;
    }
    if (variable_struct_exists(_data, "avatar"))
    {
        cfg.avatar = _data.avatar;
    }
    if (variable_struct_exists(_data, "email") && _data.email != "")
    {
        cfg.email = _data.email;
    }
    vs_online_save_config();
}

function vs_online_create_player(_on_done)
{
    vs_online_post_json_ex("/api/v1/players", { name: "" }, _on_done, "create_player");
}

// --- OAuth2 device flow (RFC 8628) + refresh token rotation -----------------

function vs_online_oauth_post(_path, _formBody, _on_done)
{
    var url = vs_online_server_url() + _path;
    vs_http_request_ex(url, "POST", "Content-Type: application/x-www-form-urlencoded\r\n", _formBody, _on_done, true, "", "");
}

function vs_online_oauth_start(_on_done)
{
    if (!variable_global_exists("vs_oauth_start_q"))
    {
        global.vs_oauth_start_q = [];
    }
    array_push(global.vs_oauth_start_q, _on_done);
    vs_online_oauth_post("/oauth2/device_authorization", "client_id=game", vs_online_oauth_start_done);
}

function vs_online_oauth_start_done(_ok, _data, _status)
{
    var cb = undefined;
    if (variable_global_exists("vs_oauth_start_q") && array_length(global.vs_oauth_start_q) > 0)
    {
        cb = global.vs_oauth_start_q[0];
        array_delete(global.vs_oauth_start_q, 0, 1);
    }
    if (cb == undefined) return;
    if (_ok && _data != undefined && variable_struct_exists(_data, "device_code"))
    {
        cb(true, _data);
    }
    else
    {
        cb(false, _data);
    }
}

function vs_online_oauth_poll(_deviceCode, _on_done)
{
    if (!variable_global_exists("vs_oauth_poll_q"))
    {
        global.vs_oauth_poll_q = [];
    }
    array_push(global.vs_oauth_poll_q, _on_done);
    vs_online_oauth_post("/oauth2/token",
        "grant_type=device_code&device_code=" + vs_online_url_encode(_deviceCode) + "&client_id=game",
        vs_online_oauth_poll_done);
}

function vs_online_oauth_poll_done(_ok, _data, _status)
{
    var cb = undefined;
    if (variable_global_exists("vs_oauth_poll_q") && array_length(global.vs_oauth_poll_q) > 0)
    {
        cb = global.vs_oauth_poll_q[0];
        array_delete(global.vs_oauth_poll_q, 0, 1);
    }
    if (cb != undefined) { cb(_ok, _data, _status); }
}

function vs_online_oauth_refresh(_refreshToken, _on_done)
{
    if (!variable_global_exists("vs_oauth_refresh_q"))
    {
        global.vs_oauth_refresh_q = [];
    }
    array_push(global.vs_oauth_refresh_q, _on_done);
    vs_online_oauth_post("/oauth2/token",
        "grant_type=refresh_token&refresh_token=" + vs_online_url_encode(_refreshToken) + "&client_id=game",
        vs_online_oauth_refresh_done);
}

function vs_online_oauth_refresh_done(_ok, _data, _status)
{
    var cb = undefined;
    if (variable_global_exists("vs_oauth_refresh_q") && array_length(global.vs_oauth_refresh_q) > 0)
    {
        cb = global.vs_oauth_refresh_q[0];
        array_delete(global.vs_oauth_refresh_q, 0, 1);
    }
    if (cb != undefined) { cb(_ok, _data, _status); }
}

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

function vs_online_refresh_me(_on_done)
{
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + "/api/v1/players/me";
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        url += "?token=" + vs_online_url_encode(cfg.token);
    }
    vs_http_request_ex(url, "GET", { Accept: "application/json" }, "", _on_done, true, "refresh_me", "");
}

function vs_online_ensure_identity(_on_done)
{
    if (!variable_global_exists("vs_identity_q"))
    {
        global.vs_identity_q = [];
    }
    array_push(global.vs_identity_q, _on_done);
    vs_online_ensure_identity_step();
}

function vs_online_ensure_identity_pop(_ok, _data)
{
    var cb = undefined;
    if (variable_global_exists("vs_identity_q") && array_length(global.vs_identity_q) > 0)
    {
        cb = global.vs_identity_q[0];
        array_delete(global.vs_identity_q, 0, 1);
    }
    if (cb != undefined) { cb(_ok, _data); }
}

function vs_online_ensure_identity_step()
{
    var cfg = vs_online_get_config();
    if (variable_struct_exists(cfg, "refresh_token") && cfg.refresh_token != "")
    {
        vs_online_oauth_refresh(cfg.refresh_token, vs_online_ensure_identity_refreshed);
        return;
    }
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        vs_online_get_json("/api/v1/players/me", true, vs_online_ensure_identity_me);
        return;
    }
    vs_online_create_player(vs_online_ensure_identity_created);
}

function vs_online_ensure_identity_refreshed(_ok, _data, _status)
{
    if (_ok && _data != undefined && variable_struct_exists(_data, "access_token"))
    {
        vs_online_apply_oauth_tokens(_data);
        vs_online_refresh_me(vs_online_ensure_identity_me_ok);
        return;
    }
    var cfg2 = vs_online_get_config();
    cfg2.refresh_token = "";
    vs_online_save_config();
    vs_online_ensure_identity_step();
}

function vs_online_ensure_identity_me(_ok, _data, _status)
{
    if (_ok)
    {
        vs_online_apply_me(_data);
        vs_online_ensure_identity_pop(true, _data);
    }
    else
    {
        vs_online_create_player(vs_online_ensure_identity_created);
    }
}

function vs_online_ensure_identity_me_ok(_ok, _data)
{
    vs_online_ensure_identity_pop(_ok, _data);
}

function vs_online_ensure_identity_created(_ok, _data)
{
    vs_online_ensure_identity_pop(_ok, _data);
}

function vs_online_drop_identity()
{
    var cfg = vs_online_get_config();
    cfg.playerId = "";
    cfg.token = "";
    cfg.email = "";
    cfg.refresh_token = "";
    vs_online_save_config();
}

// Mod logout discards the local token only (server contract: never call POST /auth/logout).
function vs_online_auth_logout(_on_done)
{
    vs_online_drop_identity();
    if (_on_done != undefined) { _on_done(true); }
}

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
    var ep = vs_online_endpoint_label();
    if (vs_online_is_account())
    {
        var nm = (variable_struct_exists(cfg, "name") && cfg.name != "") ? cfg.name : "Player";
        if (variable_struct_exists(cfg, "email") && cfg.email != "")
        {
            return ep + "  " + nm + " (" + cfg.email + ")  [" + conn + "]";
        }
        return ep + "  " + nm + "  [device · " + conn + "]";
    }
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
        return ep + "  Guest / not logged in - online features disabled.  [" + conn + "]";
    return ep + "  Not signed in yet - log in to use online features.";
}

// --- achievements ----------------------------------------------------------

function vs_online_unlock_achievement(_name)
{
    if (!vs_online_is_account()) return;
    vs_online_post_json("/api/v1/players/me/achievements/" + vs_online_url_encode(_name), {}, function(_ok, _data, _status) { });
}

function vs_online_clear_achievement(_name)
{
    if (!vs_online_is_account()) return;
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + "/api/v1/players/me/achievements/" + vs_online_url_encode(_name)
            + "?token=" + vs_online_url_encode(cfg.token);
    vs_http_request_ex(url, "DELETE", {}, "", undefined, false, "", "");
}

// --- per-chart leaderboards (/charts/scores) -------------------------------

function vs_online_score_log(_msg)
{
    show_debug_message("VS SCORE: " + string(_msg));
    vs_songstore_log("SCORE " + string(_msg));
}

function vs_online_score_play_flags()
{
    var gauge = "";
    var hasGauge = false;
    if (variable_global_exists("decrypt_mode") && is_struct(global.decrypt_mode))
    {
        gauge = string(struct_get_fallback(global.decrypt_mode, "name", ""));
        hasGauge = struct_get_fallback(global.decrypt_mode, "gauge", false);
    }
    var judged = 0;
    if (variable_global_exists("count_miss"))
        judged = global.count_acrit + global.count_crit + global.count_great + global.count_good + global.count_miss;
    var notes = variable_global_exists("notecount") ? global.notecount : -1;
    return "failed=" + string(variable_global_exists("failed") && global.failed)
        + " autoplay=" + string(variable_global_exists("op_autoplay") && global.op_autoplay)
        + " skip_results=" + string(variable_global_exists("skip_results") && global.skip_results)
        + " gauge=" + gauge
        + " has_gauge=" + string(hasGauge)
        + " judged=" + string(judged)
        + " notes=" + string(notes);
}

function vs_online_upload_score_done(_ok, _data, _status)
{
    vs_online_score_log("POST result ok=" + string(_ok) + " http=" + string(_status));
}

function vs_online_upload_score(_chartId, _difficulty, _sha1, _score, _data)
{
    if (!vs_online_is_account())
    {
        vs_online_score_log("skip no account chart=" + string(_chartId) + " diff=" + string(_difficulty) + " " + vs_online_score_play_flags());
        return;
    }
    var body = { chartId: _chartId, difficulty: vs_online_diff_api(_difficulty), sha1: _sha1 };
    variable_struct_set(body, "score", _score);
    if (_data != undefined && _data != "")
    {
        body.data = _data;
    }
    vs_online_score_log("POST /charts/scores chart=" + string(_chartId)
        + " diff=" + string(vs_online_diff_api(_difficulty))
        + " sha=" + string_copy(string(_sha1), 1, 8)
        + " pts=" + string(_score)
        + " " + vs_online_score_play_flags());
    vs_online_post_json("/api/v1/charts/scores", body, vs_online_upload_score_done);
}

function vs_online_upload_chart(_songIndex, _difficulty, _score)
{
    if (!vs_online_is_custom())
    {
        vs_online_score_log("skip custom-server off idx=" + string(_songIndex));
        return;
    }
    if (!vs_online_is_account())
    {
        vs_online_score_log("skip guest idx=" + string(_songIndex) + " " + vs_online_score_play_flags());
        return;
    }
    if (!variable_global_exists("song_list"))
    {
        vs_online_score_log("skip no song_list");
        return;
    }
    if (_songIndex < 0 || _songIndex >= array_length(global.song_list))
    {
        vs_online_score_log("skip bad idx=" + string(_songIndex));
        return;
    }
    var song = global.song_list[_songIndex];
    if (song == undefined || !variable_struct_exists(song, "chart_id") || song.chart_id == "")
    {
        vs_online_score_log("skip no chart_id idx=" + string(_songIndex));
        return;
    }
    var sname = variable_struct_exists(song, "name") ? string(song.name) : "";
    vs_online_score_log("resolve idx=" + string(_songIndex)
        + " name=" + sname
        + " chart=" + string(song.chart_id)
        + " diff=" + string(_difficulty)
        + " pts=" + string(_score)
        + " " + vs_online_score_play_flags());
    if (variable_global_exists("failed") && global.failed)
    {
        vs_online_score_log("failed/gauge-death still uploads (same as official Steam)");
    }
    var sha = vs_online_chart_sha1(song.chart_id, _difficulty);
    if (sha == "")
    {
        vs_online_score_log("skip no sha1 chart=" + string(song.chart_id) + " diff=" + string(_difficulty) + " " + vs_online_score_play_flags());
        return;
    }
    vs_online_upload_score(song.chart_id, _difficulty, sha, round(_score), "");
}

function vs_online_download_scores(_chartId, _difficulty, _sha1, _start, _end, _on_done)
{
    if (!vs_online_is_account())
    {
        if (_on_done != undefined) { _on_done(undefined); }
        return;
    }
    if (!variable_global_exists("vs_score_q"))
    {
        global.vs_score_q = [];
    }
    array_push(global.vs_score_q, _on_done);
    var url = "/api/v1/charts/scores?chartId=" + vs_online_url_encode(_chartId)
            + "&difficulty=" + vs_online_url_encode(vs_online_diff_api(_difficulty))
            + "&start=" + string(_start)
            + "&end=" + string(_end);
    if (_sha1 != undefined && _sha1 != "")
    {
        url += "&sha1=" + vs_online_url_encode(_sha1);
    }
    vs_online_get_json(url, false, vs_online_download_scores_done);
}

function vs_online_download_scores_done(_ok, _data, _status)
{
    var cb = undefined;
    if (variable_global_exists("vs_score_q") && array_length(global.vs_score_q) > 0)
    {
        cb = global.vs_score_q[0];
        array_delete(global.vs_score_q, 0, 1);
    }
    if (cb != undefined) { cb(_ok ? _data : undefined); }
}

function vs_online_download_friends_scores(_chartId, _difficulty, _sha1, _on_done)
{
    if (!vs_online_is_account())
    {
        if (_on_done != undefined) { _on_done(undefined); }
        return;
    }
    if (!variable_global_exists("vs_score_q"))
    {
        global.vs_score_q = [];
    }
    array_push(global.vs_score_q, _on_done);
    var url = "/api/v1/charts/scores/friends?chartId=" + vs_online_url_encode(_chartId)
            + "&difficulty=" + vs_online_url_encode(vs_online_diff_api(_difficulty));
    if (_sha1 != undefined && _sha1 != "")
    {
        url += "&sha1=" + vs_online_url_encode(_sha1);
    }
    vs_online_get_json(url, true, vs_online_download_scores_done);
}

function vs_online_lb_bind_download()
{
    data = [];
    if (vs_online_is_custom())
    {
        vs_online_lb_download(id, false);
        canExtend = false;
        return;
    }
    lbId = steam_download_scores(name, 1, maxScores);
    canExtend = true;
}

function vs_online_lb_bind_download_friends()
{
    data = [];
    if (vs_online_is_custom())
    {
        vs_online_lb_download(id, true);
        canExtend = false;
        return;
    }
    lbId = steam_download_friends_scores(name);
    canExtend = false;
}

function vs_online_lb_download(_inst, _friends)
{
    if (!instance_exists(_inst)) return;
    _inst.data = [];
    if (!variable_instance_exists(_inst, "song") || !variable_instance_exists(_inst, "difficulty"))
    {
        return;
    }
    var diffs = ["OPENING", "MIDDLE", "FINALE", "ENCORE"];
    var di = _inst.difficulty;
    if (di < 0 || di >= array_length(diffs)) return;
    var diffName = diffs[di];
    var chartId = _inst.song.chart_id;
    var sha = vs_online_chart_sha1(chartId, diffName);
    if (!variable_global_exists("vs_lb_q"))
    {
        global.vs_lb_q = [];
    }
    array_push(global.vs_lb_q, _inst);
    if (_friends)
    {
        vs_online_download_friends_scores(chartId, diffName, sha, vs_online_lb_apply);
    }
    else
    {
        vs_online_download_scores(chartId, diffName, sha, 1, 50, vs_online_lb_apply);
    }
}

function vs_online_lb_apply(_data)
{
    var inst = undefined;
    if (variable_global_exists("vs_lb_q") && array_length(global.vs_lb_q) > 0)
    {
        inst = global.vs_lb_q[0];
        array_delete(global.vs_lb_q, 0, 1);
    }
    if (inst == undefined || !instance_exists(inst)) return;
    inst.data = [];
    if (_data == undefined || !variable_struct_exists(_data, "entries") || !is_array(_data.entries)) return;
    var i = 0;
    repeat (array_length(_data.entries))
    {
        var e = _data.entries[i];
        var nm = (variable_struct_exists(e, "name") && e.name != "") ? e.name : e.playerId;
        var row =
        {
            userid: e.playerId,
            name: nm,
            rank: e.rank,
            timestamp: variable_struct_exists(e, "uploadedAt") ? e.uploadedAt : 0
        };
        variable_struct_set(row, "score", variable_struct_exists(e, "score") ? variable_struct_get(e, "score") : 0);
        array_push(inst.data, row);
        i++;
    }
}

// --- score suffix isolation ------------------------------------------------

function vs_online_highscore_file(_orig)
{
    if (vs_online_is_custom())
    {
        return _orig + "_vson" + string_copy(sha1_string_utf8(vs_online_server_url()), 1, 8);
    }
    return _orig;
}

function vs_online_highscore_is_dev()
{
    return string_pos("highscore_table_dev", string(global.highscore_file)) > 0;
}

// --- B40 / rating (server projection) --------------------------------------

function vs_online_rating_refresh()
{
    if (!vs_online_is_account()) return;
    var pid = vs_online_player_id();
    if (pid == "") return;
    vs_online_get_json("/api/v1/players/" + vs_online_url_encode(pid) + "/rating-card", false, vs_online_rating_card_done);
}

function vs_online_rating_window_refresh()
{
    vs_online_rating_refresh();
}

function vs_online_rating_card_done(_ok, _data, _status)
{
    if (!_ok || _data == undefined) return;
    if (variable_struct_exists(_data, "rating"))
    {
        global.rscore = _data.rating;
        if (variable_global_exists("profile_file") && global.profile_file != undefined)
        {
            ini_open(global.profile_file);
            ini_write_real("profile", "ratinglast", global.rscore);
            ini_close();
        }
        if (global.rscore >= 2000) unlock_achievement("rating_2000");
        if (global.rscore >= 5000) unlock_achievement("rating_5000");
        if (global.rscore >= 8000) unlock_achievement("rating_8000");
        if (global.rscore >= 10000) unlock_achievement("rating_10000");
        if (global.rscore >= 13000) unlock_achievement("rating_13000");
    }
    if (variable_struct_exists(_data, "completionBonus"))
    {
        global.completion_bonus = _data.completionBonus / 1000;
    }
    vs_online_rating_fill_window(_data);
}

function vs_online_rating_diff_index(_name)
{
    var d = string_lower(string(_name));
    if (d == "opening") return 1;
    if (d == "middle") return 2;
    if (d == "finale") return 3;
    if (d == "encore" || d == "backstage") return 4;
    return 1;
}

function vs_online_rating_lamp(_name)
{
    var n = string_lower(string(_name));
    if (string_pos("critical", n) > 0) return 2;
    if (string_pos("combo", n) > 0 || string_pos("full", n) > 0) return 1;
    return 0;
}

function vs_online_rating_fill_window(_data)
{
    if (!variable_global_exists("rsw_table")) return;
    global.rsw_table = [];
    global.rsw_ex_table = [];
    if (variable_struct_exists(_data, "top") && is_array(_data.top))
    {
        var i = 0;
        repeat (array_length(_data.top))
        {
            var e = _data.top[i];
            var sid = get_song_id_from_name(variable_struct_exists(e, "song") ? e.song : "");
            var sc = variable_struct_exists(e, "score") ? variable_struct_get(e, "score") : 0;
            var df = vs_online_rating_diff_index(variable_struct_exists(e, "difficulty") ? e.difficulty : "");
            var rt = variable_struct_exists(e, "rating") ? (e.rating * 1000) : 0;
            var lp = vs_online_rating_lamp(variable_struct_exists(e, "lamp") ? e.lamp : "");
            array_push(global.rsw_table, new rating_entry(sid, sc, df, rt, lp));
            i++;
        }
    }
    if (variable_struct_exists(_data, "exTop") && is_array(_data.exTop))
    {
        var j = 0;
        repeat (array_length(_data.exTop))
        {
            var xe = _data.exTop[j];
            var xid = get_song_id_from_name(variable_struct_exists(xe, "song") ? xe.song : "");
            var xp = variable_struct_exists(xe, "exPercent") ? (xe.exPercent / 100) : 0;
            var xr = variable_struct_exists(xe, "rating") ? (xe.rating * 1000) : 0;
            var xd = vs_online_rating_diff_index(variable_struct_exists(xe, "difficulty") ? xe.difficulty : "");
            array_push(global.rsw_ex_table, new ex_rating_entry(xid, xp, 0, xd, xr));
            j++;
        }
    }
    global.rsw_top30 = [];
    global.rsw_ex_top10 = [];
    array_copy(global.rsw_top30, 0, global.rsw_table, 0, 30);
    array_copy(global.rsw_ex_top10, 0, global.rsw_ex_table, 0, 10);
    while (array_length(global.rsw_top30) < 30)
    {
        array_push(global.rsw_top30, new rating_entry(0, 0, 1, 0, 0));
    }
    while (array_length(global.rsw_ex_top10) < 10)
    {
        array_push(global.rsw_ex_top10, new ex_rating_entry(0, 0, 0, 1, 0));
    }
}

function vs_online_countdown_sound(_n)
{
    if (variable_global_exists("op_bwp_countdown_sound") && global.op_bwp_countdown_sound > 0)
    {
        var alt = "bwp_countdown" + string(global.op_bwp_countdown_sound) + "_" + string(_n);
        var idx = asset_get_index(alt);
        if (idx != -1) return idx;
    }
    return asset_get_index("sfx_count" + string(_n));
}

function vs_online_start_sound()
{
    if (variable_global_exists("op_bwp_countdown_sound") && global.op_bwp_countdown_sound == 2)
    {
        var idx = asset_get_index("bwp_countdown2_0");
        if (idx != -1) return idx;
    }
    return sfx_startsong_2024;
}
