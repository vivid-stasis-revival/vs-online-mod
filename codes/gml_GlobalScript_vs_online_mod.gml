// ============================================================================
// vs-online-mod — core
// vivid/stasis custom-server backend (vs-server-go).
//
// UNDERANALYZER / vsml:
//   1) OUR object events cannot mention any vs_* script or our object names.
//      Those compile as instance variables and crash. Events only call
//      global.vs_fn.* (bound in vs_online_bind_hooks).
//   2) Anons do not capture enclosing `var` / args (they become self.xxx).
//   3) Do not use reserved names as locals (`all`, `other`, `self`, `id`).
//   4) Only call runner builtins that exist in vsml's BuiltinList.
//
// Every custom-server behavior in this mod is gated by vs_online_is_custom(),
// which is true ONLY when:
//   - the player enabled the "Custom Server" option in Settings, AND
//   - a valid `vsonline` config file exists.
// When false, the game behaves exactly as vanilla (Steam path).
//
// Config file: <game save dir>/vsonline   (JSON, no extension)
// {
//   "server": "https://online.vividstasis.cn", // REST base URL
//   "ws": "wss://online.vividstasis.cn",       // optional lobby WS (derived from server if omitted)
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

function vs_online_default_server()
{
    return "https://online.vividstasis.cn";
}

// Read (and cache) the vsonline config. Creates a default file if missing.
function vs_online_get_config()
{
    if (variable_global_exists("vs_online_config"))
    {
        return variable_global_get("vs_online_config");
    }

    var cfg = { server: vs_online_default_server() };
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
        cfg.server = vs_online_default_server();
    }
    global.vs_online_config = cfg;
    return cfg;
}

function vs_online_server_url()
{
    return vs_online_get_config().server;
}

// sha1 hex prefix as a non-negative real. string_hash is not a GML builtin
// (vsml compiles it as an instance variable).
function vs_online_str_hash(_s)
{
    var h = sha1_string_utf8(string(_s));
    var n = 0;
    var i = 1;
    repeat (8)
    {
        var c = string_ord_at(h, i);
        var v = 0;
        if (c >= 48 && c <= 57) v = c - 48;
        else if (c >= 97 && c <= 102) v = c - 87;
        else if (c >= 65 && c <= 70) v = c - 55;
        n = n * 16 + v;
        i++;
    }
    return n;
}

// Lobby uses native GameMaker WS. cfg.ws if set, otherwise same host as REST
// (https:// → wss://, http:// → ws://).
function vs_online_ws_url()
{
    var cfg = vs_online_get_config();
    if (variable_struct_exists(cfg, "ws") && cfg.ws != "")
    {
        return vs_online_ws_normalize(cfg.ws);
    }
    return vs_online_ws_normalize(string(cfg.server));
}

function vs_online_ws_normalize(_url)
{
    var s = string(_url);
    var low = string_lower(s);
    if (string_pos("wss://", low) == 1 || string_pos("ws://", low) == 1)
    {
        return s;
    }
    if (string_pos("https://", low) == 1)
    {
        var rest = string_copy(s, 9, string_length(s) - 8);
        if (string_ends_with(rest, ":443"))
        {
            rest = string_copy(rest, 1, string_length(rest) - 4);
        }
        return "wss://" + rest;
    }
    if (string_pos("http://", low) == 1)
    {
        var rest = string_copy(s, 8, string_length(s) - 7);
        if (string_ends_with(rest, ":80"))
        {
            rest = string_copy(rest, 1, string_length(rest) - 3);
        }
        return "ws://" + rest;
    }
    return s;
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
// Reads custom_profile.ini when the option global is not loaded yet
// (obj_pre_init / define_options Dev Highscores run before our option row).
function vs_online_is_custom()
{
    var enabled = false;
    if (variable_global_exists("op_vs_custom_server"))
    {
        enabled = (variable_global_get("op_vs_custom_server") == 1);
    }
    else
    {
        ini_open("custom_profile");
        enabled = (ini_read_real("vsonline", "enabled", 0) == 1);
        ini_close();
    }
    if (!enabled)
    {
        return false;
    }
    var cfg = vs_online_get_config();
    return cfg != undefined && variable_struct_exists(cfg, "server") && cfg.server != "";
}

// --- options ---------------------------------------------------------------

function vs_online_opt_toggle_change(_v)
{
    global.op_vs_custom_server = _v;
}

function vs_online_opt_noop()
{
}

function vs_online_opt_status_desc()
{
    return vs_online_auth_status_text();
}

function vs_online_opt_login_desc()
{
    return vs_online_is_account() ? "Already signed in - press to manage your account." : "Sign in with your account (device flow) to unlock online features.";
}

function vs_online_opt_login_do()
{
    if (!instance_exists(vs_auth_panel))
    {
        var inst = instance_create_depth(0, 0, -10000, vs_auth_panel);
        with (inst)
        {
            vs_auth_setup();
        }
    }
}

function vs_online_opt_logout_desc()
{
    return vs_online_is_account() ? "Sign out of the current account (falls back to guest)." : "You are a guest - there is no account to sign out of.";
}

function vs_online_opt_logout_done(_ok)
{
    show_message("Signed out - online features are now disabled until you log in again.\n\n已退出登录，在线功能已禁用，需重新登录才能使用。");
}

function vs_online_opt_logout_do()
{
    if (!vs_online_is_account())
    {
        show_message("You are a guest - there is no account to sign out of.\n\n游客/未登录状态没有账号可退出。");
        return;
    }
    vs_online_auth_logout(vs_online_opt_logout_done);
}

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
        on_change: vs_online_opt_toggle_change
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, toggle);

    var statusOpt = {
        name: "Account Status",
        type: 3,
        get_description: vs_online_opt_status_desc,
        read_value: vs_online_opt_noop,
        do_function: vs_online_opt_noop
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, statusOpt);

    var loginOpt = {
        name: "Log In",
        type: 3,
        get_description: vs_online_opt_login_desc,
        read_value: vs_online_opt_noop,
        do_function: vs_online_opt_login_do
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, loginOpt);

    var logoutOpt = {
        name: "Log Out",
        type: 3,
        get_description: vs_online_opt_logout_desc,
        read_value: vs_online_opt_noop,
        do_function: vs_online_opt_logout_do
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, logoutOpt);

    var bwpCat = { title: "Better Worldcross Play", options: [] };
    array_push(global.options_categories, bwpCat);
    var bi = array_length(global.options_categories) - 1;

    var countdownOpt = {
        name: "Countdown Sounds",
        description: "Toggle different types of countdown sounds in worldcross play.",
        type: 0,
        values: ["Original", "Type 2", "Type 3"],
        default_value: 0,
        varname: "op_bwp_countdown_sound",
        key: ["custom_profile", "betterWP", "countdown"]
    };
    array_push(global.options_categories[bi].options, array_length(global.system_options));
    array_push(global.system_options, countdownOpt);

    var hideLbOpt = {
        name: "Hide Leaderboard",
        description: "Hide the real-time Worldcross leaderboard during gameplay.",
        type: 0,
        values: ["Disabled", "Enabled"],
        default_value: 0,
        varname: "op_bwp_hide_leaderboard",
        key: ["custom_profile", "betterWP", "hide_leaderboard"]
    };
    array_push(global.options_categories[bi].options, array_length(global.system_options));
    array_push(global.system_options, hideLbOpt);
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

function vs_online_bind_hooks()
{
    global.vs_fn = {
        dlbr_open: vs_dlbr_open_from_menu,
        dlbr_step: vs_dlbr_step,
        dlbr_draw: vs_dlbr_draw,
        auth_step: vs_auth_step,
        auth_draw: vs_auth_draw,
        err_step: vs_online_error_step
    };
}

function vs_online_init()
{
    vs_online_bind_hooks();
    vs_online_get_config();
    if (!instance_exists(oCoroutineManager))
    {
        var _cm = instance_create_depth(0, 0, 0, oCoroutineManager);
        _cm.persistent = true;
    }
    vs_ws_start_listener();
    if (vs_online_is_custom())
    {
        vs_online_ensure_identity(vs_online_init_on_identity);
    }
}

function vs_online_init_on_probe(_conn)
{
    if (_conn)
    {
        vs_localcharts_auto_check();
        vs_online_rating_refresh();
    }
}

function vs_online_init_on_identity(_ok, _data)
{
    show_debug_message("VS Online: identity " + (_ok ? ("ok " + vs_online_player_id()) : "failed"));
    if (instance_exists(o_st_handle))
    {
        o_st_handle.steamId = vs_online_player_id();
    }
    if (vs_online_is_account())
    {
        vs_online_probe(vs_online_init_on_probe);
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
    if (!variable_global_exists("vs_probe_q"))
    {
        global.vs_probe_q = [];
        global.vs_probe_inflight = false;
        global.vs_probe_gen = 0;
        global.vs_probe_to = [];
        global.vs_online_probe = { done: false, gen: 0 };
    }
    array_push(global.vs_probe_q, _on_done);
    if (global.vs_probe_inflight)
    {
        return;
    }
    global.vs_probe_inflight = true;
    global.vs_probe_gen += 1;
    global.vs_online_probe.done = false;
    global.vs_online_probe.gen = global.vs_probe_gen;
    array_push(global.vs_probe_to, global.vs_probe_gen);
    vs_online_get_json("/healthz", false, vs_online_probe_http);
    call_later(60, time_source_units_frames, vs_online_probe_timeout);
}

function vs_online_probe_settle(_good, _gen)
{
    if (!variable_global_exists("vs_online_probe")) return;
    if (global.vs_online_probe.done) return;
    if (_gen != undefined && _gen != global.vs_online_probe.gen) return;
    global.vs_online_probe.done = true;
    global.vs_probe_inflight = false;
    global.vs_online_conn = _good ? 1 : -1;
    var q = global.vs_probe_q;
    global.vs_probe_q = [];
    var i = 0;
    repeat (array_length(q))
    {
        if (q[i] != undefined) { q[i](_good); }
        i++;
    }
}

function vs_online_probe_http(_ok, _data, _status)
{
    var good = _ok && _data != undefined && variable_struct_exists(_data, "ok") && _data.ok;
    vs_online_probe_settle(good, global.vs_online_probe.gen);
}

function vs_online_probe_timeout()
{
    var g = 0;
    if (variable_global_exists("vs_probe_to") && array_length(global.vs_probe_to) > 0)
    {
        g = global.vs_probe_to[0];
        array_delete(global.vs_probe_to, 0, 1);
    }
    vs_online_probe_settle(false, g);
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
    if (!variable_global_exists("vs_with_conn_q"))
    {
        global.vs_with_conn_q = [];
    }
    array_push(global.vs_with_conn_q, _fn);
    if (array_length(global.vs_with_conn_q) == 1)
    {
        vs_online_probe(vs_online_with_conn_probed);
    }
}

function vs_online_with_conn_probed(_ok)
{
    var q = [];
    if (variable_global_exists("vs_with_conn_q"))
    {
        q = global.vs_with_conn_q;
        global.vs_with_conn_q = [];
    }
    var i = 0;
    repeat (array_length(q))
    {
        if (q[i] == undefined) { i++; continue; }
        if (_ok) { q[i](); }
        else { vs_online_show_error(q[i]); }
        i++;
    }
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
    with (e)
    {
        vs_online_error_setup(_on_retry);
    }
}

function vs_online_error_setup(_on_retry)
{
    on_retry = _on_retry;
    server_url = vs_online_server_url();
    message = "The custom server could not be reached.\n\n" +
        "Address: " + server_url + "\n\n" +
        "Check that vs-server-go is running, then retry.\n" +
        "Or switch back to Steam.";
}

function vs_online_error_step()
{
    if (retrying)
    {
        return;
    }

    if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_tab))
    {
        selected = (selected + 1) % array_length(buttons);
        play_se(sfx_songsel_cursor);
    }
    else if (keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_right))
    {
        selected = (selected + array_length(buttons) - 1) % array_length(buttons);
        play_se(sfx_songsel_cursor);
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        play_se(sfx_songsel_select);
        if (selected == 0)
        {
            retrying = true;
            message = "Retrying...";
            vs_online_probe(vs_online_error_on_probe);
        }
        else
        {
            vs_online_disable_custom();
            instance_destroy();
        }
    }
    else if (keyboard_check_pressed(vk_escape))
    {
        instance_destroy();
    }
}

function vs_online_error_on_probe(_ok)
{
    if (!instance_exists(vs_online_error)) return;
    with (vs_online_error)
    {
        if (_ok)
        {
            var cb = on_retry;
            instance_destroy();
            if (is_method(cb)) cb();
        }
        else
        {
            retrying = false;
            message = "Still unreachable. Is vs-server-go running?";
        }
    }
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
