// ============================================================================
// vs_online_api.gml — REST layer + identity + achievements + leaderboards
//
// All HTTP goes through the game's coroutine library:
//   __CoroutineAwaitAsync("http", cb)  (async event 62 -> "http")
// Identity is a guest player minted by POST /api/v1/players; the playerId +
// bearer token are persisted into the `vsonline` config file.
// ============================================================================

// --- low-level HTTP --------------------------------------------------------

// Fire an HTTP request; _on_done(ok, body, status) runs on completion.
function vs_http_request(_url, _method, _headers, _body, _on_done)
{
    if (_headers == undefined)
    {
        _headers = "Content-Type: application/json\r\n";
    }
    __CoroutineBegin(function()
    {
        var rid = http_request(_url, _method, _headers, _body);
        __CoroutineAwaitAsync("http", function()
        {
            if (async_load[? "id"] != rid)
            {
                return false;
            }
            var status = async_load[? "status"];
            var text = async_load[? "result"];
            _on_done((status >= 200 && status < 300), text, status);
            return true;
        });
    });
    __CoroutineEnd();
}

// GET a JSON object; _on_done(ok, data, status). _authed appends ?token=.
function vs_online_get_json(_path, _authed, _on_done)
{
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + _path;
    if (_authed && variable_struct_exists(cfg, "token"))
    {
        url += (string_pos("?", url) > 0 ? "&" : "?") + "token=" + cfg.token;
    }
    vs_http_request(url, "GET", "Accept: application/json\r\n", "", function(ok, text, status)
    {
        var data = undefined;
        if (ok)
        {
            try { data = json_parse(text); } catch (_e) { }
        }
        _on_done(ok, data, status);
    });
}

// POST a JSON body; _on_done(ok, data, status).
function vs_online_post_json(_path, _bodyStruct, _on_done)
{
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + _path;
    if (variable_struct_exists(cfg, "token"))
    {
        url += (string_pos("?", url) > 0 ? "&" : "?") + "token=" + cfg.token;
    }
    vs_http_request(url, "POST", "Content-Type: application/json\r\n", json_stringify(_bodyStruct), function(ok, text, status)
    {
        var data = undefined;
        if (ok)
        {
            try { data = json_parse(text); } catch (_e) { }
        }
        _on_done(ok, data, status);
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
    vs_online_post_json("/api/v1/players", { name: "" }, function(ok, data, status)
    {
        if (ok)
        {
            var cfg = vs_online_get_config();
            cfg.playerId = data.playerId;
            cfg.token = data.token;
            if (variable_struct_exists(data, "name")) { cfg.name = data.name; }
            if (variable_struct_exists(data, "avatar")) { cfg.avatar = data.avatar; }
            vs_online_save_config();
        }
        _on_done(ok, data);
    });
}

// Reuse a stored token if it still works, otherwise mint a new identity.
function vs_online_ensure_identity(_on_done)
{
    var cfg = vs_online_get_config();
    if (variable_struct_exists(cfg, "token") && cfg.token != "")
    {
        vs_online_get_json("/api/v1/players/me", true, function(ok, data, status)
        {
            if (ok)
            {
                if (variable_struct_exists(data, "name") && cfg.name == "") { cfg.name = data.name; }
                if (variable_struct_exists(data, "avatar")) { cfg.avatar = data.avatar; }
                _on_done(true, data);
            }
            else
            {
                vs_online_create_player(_on_done);
            }
        });
    }
    else
    {
        vs_online_create_player(_on_done);
    }
}

// --- achievements ----------------------------------------------------------

function vs_online_unlock_achievement(_name)
{
    vs_online_post_json("/api/v1/players/me/achievements/" + _name, {}, function(_ok, _data, _status) { });
}

function vs_online_clear_achievement(_name)
{
    var cfg = vs_online_get_config();
    var url = vs_online_server_url() + "/api/v1/players/me/achievements/" + _name + "?token=" + cfg.token;
    vs_http_request(url, "DELETE", "", "", function(_ok, _text, _status) { });
}

// --- leaderboards ----------------------------------------------------------

function vs_online_upload_score(_name, _score, _forceUpdate)
{
    vs_online_post_json("/api/v1/leaderboards/" + _name + "/scores",
        { score: _score, forceUpdate: _forceUpdate },
        function(_ok, _data, _status) { });
}

// _on_done(data) where data is the JSON the game's parse_leaderboard_into
// decodes ({ entries:[{rank,score,data,userID,name}...] } or { default:true }),
// or undefined on failure.
function vs_online_download_scores(_name, _start, _end, _on_done)
{
    vs_online_get_json("/api/v1/leaderboards/" + _name + "/scores?start=" + string(_start) + "&end=" + string(_end),
        false,
        function(ok, data, status)
        {
            _on_done(ok ? data : undefined);
        });
}

function vs_online_download_friends_scores(_name, _on_done)
{
    vs_online_get_json("/api/v1/leaderboards/" + _name + "/friends", true,
        function(ok, data, status)
        {
            _on_done(ok ? data : undefined);
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
