// ============================================================================
// vs-online-mod — core
// vivid/stasis custom-server backend (vs-server-go).
//
// Every custom-server behavior in this mod is gated by vs_online_is_custom(),
// which is true ONLY when:
//   - the player enabled the "Custom Server" option in Settings, AND
//   - a valid `vsonline` config file exists.
// When false, the game behaves exactly as vanilla (Steam path).
//
// Config file: <game save dir>/vsonline   (JSON, no extension)
// {
//   "server": "http://localhost:8226",        // vs-server-go base URL
//   "playerId": "...",                        // filled in by M2 (identity)
//   "token": "...",                           // bearer token
//   "refresh_token": "...",                   // device-flow refresh token
//   "name": "...",
//   "avatar": "..."
// }
// ============================================================================

// --- config ----------------------------------------------------------------

function vs_online_config_path()
{
    return working_directory + "vsonline";
}

// Read (and cache) the vsonline config. Creates a default file if missing.
function vs_online_get_config()
{
    if (variable_global_exists("vs_online_config"))
    {
        return variable_global_get("vs_online_config");
    }

    var cfg = { server: "http://localhost:8226" };
    var path = vs_online_config_path();
    if (file_exists(path))
    {
        var f = file_text_open_read(path);
        var raw = file_text_read_string(f);
        file_text_close(f);
        try
        {
            var parsed = json_parse(raw);
            if (parsed != undefined && typeof(parsed) == "struct")
            {
                cfg = parsed;
            }
        }
        catch (_e)
        {
            show_debug_message("VS Online: config parse error -> " + string(_e));
        }
    }
    else
    {
        var fw = file_text_open_write(path);
        file_text_write_string(fw, json_stringify(cfg));
        file_text_close(fw);
    }

    if (!variable_struct_exists(cfg, "server") || cfg.server == "")
    {
        cfg.server = "http://localhost:8226";
    }
    global.vs_online_config = cfg;
    return cfg;
}

function vs_online_server_url()
{
    return vs_online_get_config().server;
}

// Rewrite the current config back to the file (used once credentials exist).
function vs_online_save_config()
{
    var path = vs_online_config_path();
    var fw = file_text_open_write(path);
    file_text_write_string(fw, json_stringify(vs_online_get_config()));
    file_text_close(fw);
}

// --- mode switch -----------------------------------------------------------

// True only when the player opted into the custom server.
function vs_online_is_custom()
{
    if (!(variable_global_exists("op_vs_custom_server") && variable_global_get("op_vs_custom_server") == 1))
    {
        return false;
    }
    var cfg = vs_online_get_config();
    return cfg != undefined && variable_struct_exists(cfg, "server") && cfg.server != "";
}

// --- options ---------------------------------------------------------------

function vs_online_add_options()
{
    var cat = { title: "VS Online", options: [] };
    array_push(global.options_categories, cat);
    var ci = array_length(global.options_categories) - 1;

    var toggle = {
        name: "Custom Server",
        description: "Use a custom server instead of Steam for online features. Requires the vsonline config file.",
        type: 0,
        values: ["Steam", "Custom Server"],
        default_value: 0,
        varname: "op_vs_custom_server",
        key: ["custom_profile", "vsonline", "enabled"],
        on_change: function(_v) { global.op_vs_custom_server = _v; }
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, toggle);

    // --- account / login / logout options (type 3 = action rows) ------------

    // Live status display: mode + user + guest warning.
    var statusOpt = {
        name: "Account Status",
        type: 3,
        get_description: function() { return vs_online_auth_status_text(); },
        read_value: function() { },
        do_function: function() { } // display only
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, statusOpt);

    // Log in: opens the auth panel (device flow); guests upgrade to an account
    // here, which is also the way online features get unlocked.
    var loginOpt = {
        name: "Log In",
        type: 3,
        get_description: function()
        {
            return vs_online_is_account() ? "Already signed in - press to manage your account." : "Sign in with your account (device flow) to unlock online features.";
        },
        read_value: function() { },
        do_function: function()
        {
            if (!instance_exists(vs_auth_panel))
            {
                instance_create_depth(0, 0, -10000, vs_auth_panel);
            }
        }
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, loginOpt);

    // Log out: drop the account identity; back to guest (online features off).
    var logoutOpt = {
        name: "Log Out",
        type: 3,
        get_description: function()
        {
            return vs_online_is_account() ? "Sign out of the current account (falls back to guest)." : "You are a guest - there is no account to sign out of.";
        },
        read_value: function() { },
        do_function: function()
        {
            if (!vs_online_is_account())
            {
                show_message("You are a guest - there is no account to sign out of.\n\n游客/未登录状态没有账号可退出。");
                return;
            }
            vs_online_auth_logout(function(_ok)
            {
                show_message("Signed out - online features are now disabled until you log in again.\n\n已退出登录，在线功能已禁用，需重新登录才能使用。");
            });
        }
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, logoutOpt);
}

// --- account gate -----------------------------------------------------------
//
// Online features (web chart catalog, downloads, lobby, leaderboards,
// achievements) require a signed-in ACCOUNT — a bare auto-minted guest can
// only play already-downloaded charts. "Logged in" = an OAuth refresh token
// (device flow) or an email (account) is present.
function vs_online_is_account()
{
    if (!vs_online_is_custom()) return false;
    var cfg = vs_online_get_config();
    if (variable_struct_exists(cfg, "refresh_token") && cfg.refresh_token != "") return true;
    if (variable_struct_exists(cfg, "email") && cfg.email != "") return true;
    return false;
}

// --- init ------------------------------------------------------------------

function vs_online_init()
{
    vs_online_get_config();
    vs_ws_start_listener();
    // Local Charts jump state (consumed by the patched song-select create).
    global.vs_local_jump_pack = -1;
    global.vs_local_jump_pos = -1;
    global.vs_local_jump_diff = -1;
    if (vs_online_is_custom())
    {
        vs_online_ensure_identity(function(_ok, _data)
        {
            show_debug_message("VS Online: identity " + (_ok ? ("ok " + vs_online_player_id()) : "failed"));
            // Keep the game's self-id in sync (member lookups use it).
            if (instance_exists(o_st_handle))
            {
                o_st_handle.steamId = vs_online_player_id();
            }
            // Custom server + real account: after identity refresh, probe the
            // server and automatically check local charts for server updates.
            if (vs_online_is_account())
            {
                vs_online_probe(function(_conn)
                {
                    if (_conn)
                    {
                        vs_localcharts_auto_check();
                    }
                });
            }
        });
    }
}

// --- connection health -----------------------------------------------------
//
// Tracks whether the custom server is reachable. State is global.vs_online_conn:
//   0 = unknown, 1 = reachable, -1 = unreachable.
// All custom-server entry points go through vs_online_with_conn(), so a dead
// server raises a recoverable on-screen dialog (vs_online_error) instead of
// failing silently.

function vs_online_conn_state()
{
    if (!variable_global_exists("vs_online_conn"))
    {
        global.vs_online_conn = 0;
    }
    return variable_global_get("vs_online_conn");
}

// Lightweight reachability probe: GET /healthz (no auth). Falls back to
// "unreachable" after ~1s (60 frames) even if the coroutine dispatcher never
// responds, so the player is never left waiting forever.
//
// NOTE: probe state lives in a global struct, NOT a captured `var` local.
// Anonymous functions in the loader-injected scripts can capture arguments
// and locals of enclosing anonymous functions, but NOT `var` locals declared
// directly in a regular function (that compiled to an instance-variable read
// and crashed: "Variable obj_multiplayer_lobby.pending not set before
// reading it"). Globals are always reachable from any callback.
function vs_online_probe(_on_done)
{
    if (!variable_global_exists("vs_online_probe"))
    {
        global.vs_online_probe = { done: false, on_done: undefined };
    }
    var st = global.vs_online_probe;
    st.done = false;
    st.on_done = _on_done;

    vs_online_get_json("/healthz", false, function(_ok, _data, _status)
    {
        var st = global.vs_online_probe;
        if (st.done) { return; }               // timeout already settled it
        st.done = true;
        var good = _ok && _data != undefined && _data.ok;
        global.vs_online_conn = good ? 1 : -1;
        var cb = st.on_done;
        st.on_done = undefined;
        if (cb != undefined) { cb(good); }
    });
    call_later(60, time_source_units_frames, function()
    {
        var st = global.vs_online_probe;
        if (st.done) { return; }               // response already arrived
        st.done = true;
        global.vs_online_conn = -1;
        var cb = st.on_done;
        st.on_done = undefined;
        if (cb != undefined) { cb(false); }
    });
}

// Run _fn only while the custom server is reachable. In Steam mode this is a
// pass-through. On failure (or unverified state) it probes first and, if the
// probe fails, raises the error dialog whose Retry re-runs _fn.
//
// NOTE: _fn is stashed in a global slot — anonymous functions in injected
// scripts can't capture the enclosing `_fn` argument (it would compile to a
// `self._fn` read and crash).
function vs_online_with_conn(_fn)
{
    if (!vs_online_is_custom())
    {
        _fn();
        return;
    }
    // Guests / not-logged-in may only play downloaded charts — every online
    // entry point gated here (lobby, downloads, catalog) requires an account.
    if (!vs_online_is_account())
    {
        vs_online_show_account_required();
        return;
    }
    var st = vs_online_conn_state();
    if (st == 1)
    {
        _fn();
        return;
    }
    if (st == -1)
    {
        vs_online_show_error(_fn);
        return;
    }
    if (!variable_global_exists("vs_online_with_conn_fn"))
    {
        global.vs_online_with_conn_fn = undefined;
    }
    global.vs_online_with_conn_fn = _fn;
    vs_online_probe(function(_ok)
    {
        var fn = global.vs_online_with_conn_fn;
        global.vs_online_with_conn_fn = undefined;
        if (fn == undefined) { return; }
        if (_ok)
        {
            fn();
        }
        else
        {
            vs_online_show_error(fn);
        }
    });
}

// Guests / not-logged-in can't use online features. Tells the player and, when
// possible, opens the account panel so they can log in.
function vs_online_show_account_required()
{
    show_message("Guest / not logged in.\n\nOnline features (lobby, leaderboards, web chart downloads) need a signed-in account. Guests can only play already-downloaded charts.\n\n游客/未登录：在线功能已禁用，只能游玩已下载的谱面。请到 设置 → VS Online → Log In 登录。");
}

// Spawn the custom-server error dialog. Idempotent: one dialog at a time.
function vs_online_show_error(_on_retry)
{
    if (instance_exists(vs_online_error))
    {
        return;
    }
    var e = instance_create_depth(0, 0, -10000, vs_online_error);
    e.on_retry = _on_retry;
}

// Player chose to fall back to Steam. Persist the toggle (custom_profile ini,
// section vsonline, key enabled) and reset the connection state so the next
// enable re-probes.
function vs_online_disable_custom()
{
    global.op_vs_custom_server = 0;
    ini_open("custom_profile");
    ini_write_real("vsonline", "enabled", 0);
    ini_close();
    global.vs_online_conn = 0;
    // (The old Web Charts in-select browser was removed; the home Chart
    // Downloader overlay closes itself on disable via vs_online_error flow.)
    show_debug_message("VS Online: custom server disabled by player.");
}

// --- packet out (M3: WebSocket binary frame to the lobby relay) -------------

// Called from the patched send_packet while on the custom server.
function vs_online_send_packet(_type, _buffer)
{
    vs_lobby_send_packet(_type, _buffer);
}
