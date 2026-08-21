// ============================================================================
// vs-online-mod — core
// vivid/stasis custom-server backend (vs-server-go).
//
// UNDERANALYZER / vsml:
//   1) vsml must compile codes/ GlobalScripts and Object events in ONE
//      CodeImportGroup.Import() so Underanalyzer sees vs_* as global functions.
//      Isolated object Import compiles vs_* as instance-variable reads.
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
//   "server": "https://online-api.vividstasis.cn", // REST / API base URL
//   "frontend": "https://online.vividstasis.cn",   // device-flow / account website
//   "ws": "wss://online-api.vividstasis.cn",       // optional lobby WS (derived from server if omitted)
//   "playerId": "...",                        // filled in by M2 (identity)
//   "token": "...",                           // bearer token
//   "refresh_token": "...",                   // device-flow refresh token
//   "name": "...",
//   "avatar": "..."
// }
// ============================================================================

// UTF-8 bytes → GML Unicode. chr(byte) on UTF-8 makes Chinese Windows treat
// those bytes as GBK, so Worldcross names show as 乱码 instead of tofu.
function vs_utf8_from_buffer(_buf)
{
    if (_buf == undefined) return "";
    var n = buffer_get_size(_buf);
    var out = "";
    while (buffer_tell(_buf) < n)
    {
        var b0 = buffer_read(_buf, buffer_u8);
        var cp = 65533;
        if (b0 < 128)
        {
            cp = b0;
        }
        else if ((b0 & 224) == 192)
        {
            if (buffer_tell(_buf) < n)
            {
                var b1 = buffer_read(_buf, buffer_u8);
                if ((b1 & 192) == 128) cp = ((b0 & 31) << 6) | (b1 & 63);
            }
        }
        else if ((b0 & 240) == 224)
        {
            if (buffer_tell(_buf) + 1 < n)
            {
                var b1 = buffer_read(_buf, buffer_u8);
                var b2 = buffer_read(_buf, buffer_u8);
                if ((b1 & 192) == 128 && (b2 & 192) == 128)
                {
                    cp = ((b0 & 15) << 12) | ((b1 & 63) << 6) | (b2 & 63);
                }
            }
        }
        else if ((b0 & 248) == 240)
        {
            if (buffer_tell(_buf) + 2 < n)
            {
                var b1 = buffer_read(_buf, buffer_u8);
                var b2 = buffer_read(_buf, buffer_u8);
                var b3 = buffer_read(_buf, buffer_u8);
                if ((b1 & 192) == 128 && (b2 & 192) == 128 && (b3 & 192) == 128)
                {
                    cp = ((b0 & 7) << 18) | ((b1 & 63) << 12) | ((b2 & 63) << 6) | (b3 & 63);
                    if (cp > 65535) cp = 65533;
                }
            }
        }
        out += chr(cp);
    }
    return out;
}

function vs_utf8_fix_string(_s)
{
    if (_s == undefined) return "";
    var src = string(_s);
    var n = string_length(src);
    if (n <= 0) return src;
    var i = 1;
    var hasHigh = false;
    repeat (n)
    {
        var o = ord(string_char_at(src, i));
        if (o > 255) return src;
        if (o >= 128) hasHigh = true;
        i++;
    }
    if (!hasHigh) return src;
    var buf = buffer_create(n, buffer_fixed, 1);
    i = 1;
    repeat (n)
    {
        buffer_write(buf, buffer_u8, ord(string_char_at(src, i)));
        i++;
    }
    buffer_seek(buf, buffer_seek_start, 0);
    var out = vs_utf8_from_buffer(buf);
    buffer_delete(buf);
    return out;
}

// --- config ----------------------------------------------------------------

function vs_online_config_path()
{
    return working_directory + "vsonline";
}

function vs_online_default_server()
{
    return "https://online-api.vividstasis.cn";
}

function vs_online_default_frontend()
{
    return "https://online.vividstasis.cn";
}

function vs_online_trim_url(_s)
{
    var s = string(_s);
    while (string_length(s) > 0 && string_char_at(s, string_length(s)) == "/")
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    if (s != "" && string_pos("://", s) <= 0)
    {
        s = "https://" + s;
    }
    return s;
}

function vs_online_config_write(_cfg)
{
    var path = vs_online_config_path();
    var fw = file_text_open_write(path);
    if (fw < 0)
    {
        show_debug_message("VS Online: could not write config " + path);
        return false;
    }
    file_text_write_string(fw, json_stringify(_cfg));
    file_text_close(fw);
    return true;
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
    var parsed_ok = false;
    if (file_exists(path))
    {
        var f = file_text_open_read(path);
        if (f >= 0)
        {
            var raw = file_text_read_string(f);
            file_text_close(f);
            try
            {
                var parsed = json_parse(raw);
                if (parsed != undefined && typeof(parsed) == "struct")
                {
                    cfg = parsed;
                    parsed_ok = true;
                }
            }
            catch (_e)
            {
                show_debug_message("VS Online: config parse error -> " + string(_e));
            }
        }
    }

    if (!variable_struct_exists(cfg, "server") || cfg.server == "")
    {
        cfg.server = vs_online_default_server();
    }
    if (!variable_struct_exists(cfg, "frontend") || cfg.frontend == "")
    {
        cfg.frontend = vs_online_default_frontend();
    }
    cfg.server = vs_online_trim_url(cfg.server);
    cfg.frontend = vs_online_trim_url(cfg.frontend);
    var migrated = false;
    if (vs_online_host_is_site(cfg.server))
    {
        cfg.server = vs_online_default_server();
        migrated = true;
    }
    if (variable_struct_exists(cfg, "ws") && cfg.ws != "" && vs_online_host_is_site(cfg.ws))
    {
        cfg.ws = "";
        migrated = true;
    }
    global.vs_online_config = cfg;
    if (!parsed_ok || migrated)
    {
        vs_online_config_write(cfg);
    }
    return cfg;
}

// online.vividstasis.cn is the account site, not the API. Old defaults
// pointed server/ws there; remap those to online-api.
function vs_online_host_is_site(_url)
{
    var s = string_lower(vs_online_trim_url(_url));
    var cut = string_pos("://", s);
    if (cut > 0)
    {
        s = string_copy(s, cut + 3, string_length(s));
    }
    return (s == "online.vividstasis.cn");
}

function vs_online_server_url()
{
    return vs_online_get_config().server;
}

function vs_online_endpoint_label()
{
    var s = vs_online_server_url();
    if (string_pos("https://", s) == 1) s = string_copy(s, 9, string_length(s));
    else if (string_pos("http://", s) == 1) s = string_copy(s, 8, string_length(s));
    while (string_length(s) > 0 && string_char_at(s, string_length(s)) == "/")
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    return s;
}

function vs_online_frontend_url()
{
    return vs_online_get_config().frontend;
}

function vs_online_preview_auto()
{
    var cfg = vs_online_get_config();
    if (!variable_struct_exists(cfg, "previewAuto")) return true;
    return (cfg.previewAuto == true || cfg.previewAuto == 1);
}

function vs_online_set_preview_auto(_on)
{
    var cfg = vs_online_get_config();
    cfg.previewAuto = _on ? true : false;
    vs_online_save_config();
}

function vs_online_device_page_url(_userCode)
{
    var page = vs_online_frontend_url() + "/device";
    if (_userCode != undefined && _userCode != "")
    {
        page += "?user_code=" + vs_online_url_encode(_userCode);
    }
    return page;
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
    vs_online_config_write(vs_online_get_config());
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
    var was = 0;
    if (variable_global_exists("op_vs_custom_server")) was = global.op_vs_custom_server;
    if (!is_real(_v) || _v != _v) _v = 0;
    _v = clamp(floor(_v), 0, 1);
    global.op_vs_custom_server = _v;
    if (_v == 1 && was != 1) vs_online_apply_custom_on();
    else if (_v != 1 && was == 1) vs_online_apply_custom_off();
}

function vs_online_highscore_base(_orig)
{
    var s = string(_orig);
    var p = string_last_pos("_vson", s);
    if (p > 0) return string_copy(s, 1, p - 1);
    return s;
}

function vs_online_apply_custom_on()
{
    vs_online_get_config();
    if (variable_global_exists("highscore_file"))
        global.highscore_file = vs_online_highscore_file(global.highscore_file);
    vs_csm_force_gm_audio();
    vs_online_ensure_identity(vs_online_init_on_identity);
}

function vs_online_apply_custom_off()
{
    global.vs_online_conn = 0;
    if (variable_global_exists("highscore_file"))
        global.highscore_file = vs_online_highscore_base(global.highscore_file);
}

function vs_online_opt_read_clamped(_file, _sec, _key, _def, _max, _varname)
{
    var v = _def;
    ini_open(_file);
    v = ini_read_real(_sec, _key, _def);
    ini_close();
    if (!is_real(v) || v != v) v = _def;
    v = clamp(floor(v), 0, _max);
    variable_global_set(_varname, v);
    return v;
}

function vs_online_opt_read_server()
{
    return vs_online_opt_read_clamped("custom_profile", "vsonline", "enabled", 0, 1, "op_vs_custom_server");
}

function vs_online_opt_read_legacy_lobby()
{
    return vs_online_opt_read_clamped("custom_profile", "vsonline", "legacy_lobby", 0, 1, "op_vs_legacy_lobby");
}

function vs_online_opt_read_countdown()
{
    return vs_online_opt_read_clamped("custom_profile", "betterWP", "countdown", 0, 2, "op_bwp_countdown_sound");
}

function vs_online_opt_read_hidelb()
{
    return vs_online_opt_read_clamped("custom_profile", "betterWP", "hide_leaderboard", 0, 1, "op_bwp_hide_leaderboard");
}

function vs_online_opt_noop()
{
}

function vs_online_opt_status_desc()
{
    return vs_online_auth_status_text();
}

function vs_online_opt_account_desc()
{
    var st = vs_online_auth_status_text();
    if (vs_online_is_account())
    {
        return st + " Press to manage the account or sign out.";
    }
    return st + " Press to sign in (device flow).";
}

function vs_online_opt_account_do()
{
    if (!vs_online_is_custom())
    {
        show_message("Enable Custom Server first.\n\n请先打开 Custom Server。");
        return;
    }
    if (!instance_exists(vs_auth_panel))
    {
        instance_create_depth(0, 0, -10000, vs_auth_panel);
        with (vs_auth_panel)
        {
            vs_auth_setup();
        }
    }
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
    if (!variable_global_exists("system_options") || !is_array(global.system_options)) return;
    if (!variable_global_exists("options_categories") || !is_array(global.options_categories)) return;

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
        read_value: vs_online_opt_read_server,
        on_change: vs_online_opt_toggle_change
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, toggle);

    var legacyLobbyOpt = {
        name: "Use Legacy Worldcross Lobby",
        description: "Restore the original Host / Paste / Join landing. Off = matchmaking lobby with public room list.",
        type: 0,
        values: ["Disabled", "Enabled"],
        default_value: 0,
        varname: "op_vs_legacy_lobby",
        key: ["custom_profile", "vsonline", "legacy_lobby"],
        read_value: vs_online_opt_read_legacy_lobby
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, legacyLobbyOpt);

    var accountOpt = {
        name: "Account Management",
        description: "Sign in or manage the custom-server account.",
        type: 3,
        get_description: vs_online_opt_account_desc,
        read_value: vs_online_opt_noop,
        do_function: vs_online_opt_account_do
    };
    array_push(global.options_categories[ci].options, array_length(global.system_options));
    array_push(global.system_options, accountOpt);

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
        key: ["custom_profile", "betterWP", "countdown"],
        read_value: vs_online_opt_read_countdown
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
        key: ["custom_profile", "betterWP", "hide_leaderboard"],
        read_value: vs_online_opt_read_hidelb
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

// Standalone betterWP / CSM inject unique scripts we do not ship. Those
// functions exist as soon as data.win loads, so this can run at the first
// line of initiategame — before CreateSongDictionary, which dual-patching
// will crash. Do not wait for vml_mods; other mods may register later in
// the same Create. Do not use show_message here: YYC often hard-crashes
// that builtin during the loading room instead of showing a dialog.
//
// parse_extra_value is official GML — never use it as a CSM fingerprint.
// CSM's unique GlobalScript is initSetting (force GM audio on boot).
function vs_online_has_fn(_name)
{
    return variable_global_exists(_name);
}

function vs_online_conflict_why()
{
    if (vs_online_has_fn("betterWP_add_options"))
    {
        return "VS Online 与 betterWP 不兼容，请移除其一后重试。\n\nVS Online is incompatible with betterWP — please remove one of them and restart.";
    }
    if (variable_global_exists("vml_mods") && is_struct(global.vml_mods) && variable_struct_exists(global.vml_mods, "betterWP_mod"))
    {
        return "VS Online 与 betterWP 不兼容，请移除其一后重试。\n\nVS Online is incompatible with betterWP — please remove one of them and restart.";
    }
    if (vs_online_has_fn("initSetting"))
    {
        return "VS Online 已内置 Custom Songs，请卸载独立的 Custom Songs Mod 后重试。\n\nVS Online already includes Custom Songs — please uninstall the standalone Custom Songs Mod and restart.";
    }
    if (variable_global_exists("vml_mods") && is_struct(global.vml_mods) && variable_struct_exists(global.vml_mods, "custom_song_mod"))
    {
        return "VS Online 已内置 Custom Songs，请卸载独立的 Custom Songs Mod 后重试。\n\nVS Online already includes Custom Songs — please uninstall the standalone Custom Songs Mod and restart.";
    }
    return "";
}

function vs_online_show_conflict(_why)
{
    show_debug_message("VS Online: conflict " + string(_why));
    if (instance_exists(vs_online_error))
    {
        with (vs_online_error) instance_destroy();
    }
    var e = instance_create_depth(0, 0, -16000, vs_online_error);
    with (e)
    {
        vs_online_error_bind();
        kind = "conflict";
        title = "Mod Conflict";
        buttons = ["退出 / Exit"];
        selected = 0;
        on_retry = undefined;
        retrying = false;
        server_url = "";
        message = string(_why);
    }
}

function vs_online_conflict_halt()
{
    var why = vs_online_conflict_why();
    if (why == "") return false;
    vs_online_show_conflict(why);
    return true;
}

function vs_online_bind_hooks()
{
    // Store on global (not a struct): official menu anons cannot name vs_*
    // scripts, and struct.fn() rebinds self to the struct.
    global.vs_dlbr_open = vs_dlbr_open_from_menu;
}

function vs_online_init()
{
    vs_csm_force_gm_audio();
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

// Lightweight reachability probe: GET /healthz (no auth). Each attempt waits
// a bit longer than the HTTP timeout so TLS/cold-start to the API is not
// marked dead at 1s. Failures automatically retry (3 tries) before the
// on-screen Retry dialog.
//
// NOTE: probe state lives in a global struct, NOT a captured `var` local.
// Anonymous functions in the loader-injected scripts can capture arguments
// and locals of enclosing anonymous functions, but NOT `var` locals declared
// directly in a regular function (that compiled to an instance-variable read
// and crashed: "Variable obj_multiplayer_lobby.pending not set before
// reading it"). Globals are always reachable from any callback.
function vs_online_probe_max()
{
    return 3;
}

function vs_online_probe(_on_done)
{
    if (!variable_global_exists("vs_probe_q"))
    {
        global.vs_probe_q = [];
        global.vs_probe_inflight = false;
        global.vs_probe_gen = 0;
        global.vs_probe_to = [];
        global.vs_probe_http = [];
        global.vs_probe_st = { done: false, gen: 0, attempt: 0 };
    }
    if (!variable_global_exists("vs_probe_http") || !is_array(global.vs_probe_http))
    {
        global.vs_probe_http = [];
    }
    if (!variable_global_exists("vs_probe_st") || !is_struct(global.vs_probe_st))
    {
        global.vs_probe_st = { done: false, gen: 0, attempt: 0 };
    }
    if (!variable_struct_exists(global.vs_probe_st, "attempt")) global.vs_probe_st.attempt = 0;
    array_push(global.vs_probe_q, _on_done);
    if (global.vs_probe_inflight)
    {
        return;
    }
    global.vs_probe_inflight = true;
    global.vs_probe_st.done = false;
    global.vs_probe_st.attempt = 0;
    vs_online_probe_kick();
}

function vs_online_probe_kick()
{
    if (!variable_global_exists("vs_probe_st") || !is_struct(global.vs_probe_st)) return;
    if (global.vs_probe_st.done) return;
    global.vs_probe_st.attempt += 1;
    global.vs_probe_gen += 1;
    global.vs_probe_st.gen = global.vs_probe_gen;
    array_push(global.vs_probe_to, global.vs_probe_st.gen);
    array_push(global.vs_probe_http, global.vs_probe_st.gen);
    show_debug_message("VS Online: probe " + string(global.vs_probe_st.attempt) + "/" + string(vs_online_probe_max()) + " GET /healthz");
    vs_songstore_log("probe " + string(global.vs_probe_st.attempt) + "/" + string(vs_online_probe_max()) + " /healthz");
    vs_online_get_json("/healthz", false, vs_online_probe_http, 3000);
    // HTTP 3000ms → 180 frames at 60fps. Stay behind that so the request can
    // finish (or its own timeout can fire) before this fallback.
    call_later(210, time_source_units_frames, vs_online_probe_timeout);
}

function vs_online_probe_finish(_good)
{
    if (!variable_global_exists("vs_probe_st") || !is_struct(global.vs_probe_st)) return;
    if (global.vs_probe_st.done) return;
    global.vs_probe_st.done = true;
    global.vs_probe_inflight = false;
    global.vs_online_conn = _good ? 1 : -1;
    show_debug_message("VS Online: probe " + (_good ? "ok" : "fail") + " after " + string(global.vs_probe_st.attempt) + " attempt(s)");
    vs_songstore_log("probe " + (_good ? "ok" : "fail") + " n=" + string(global.vs_probe_st.attempt));
    var q = global.vs_probe_q;
    global.vs_probe_q = [];
    var i = 0;
    repeat (array_length(q))
    {
        if (q[i] != undefined) { q[i](_good); }
        i++;
    }
}

function vs_online_probe_settle(_good, _gen)
{
    if (!variable_global_exists("vs_probe_st") || !is_struct(global.vs_probe_st)) return;
    if (global.vs_probe_st.done) return;
    // A late success from an earlier attempt still counts — the server is up.
    if (_good)
    {
        vs_online_probe_finish(true);
        return;
    }
    if (_gen != undefined && _gen != global.vs_probe_st.gen) return;
    if (global.vs_probe_st.attempt < vs_online_probe_max())
    {
        // Invalidate leftover timeout/HTTP for this attempt, then retry.
        global.vs_probe_gen += 1;
        global.vs_probe_st.gen = global.vs_probe_gen;
        show_debug_message("VS Online: probe miss, auto-retry");
        call_later(30, time_source_units_frames, vs_online_probe_kick);
        return;
    }
    vs_online_probe_finish(false);
}

function vs_online_probe_http(_ok, _data, _status)
{
    var g = 0;
    if (variable_global_exists("vs_probe_http") && array_length(global.vs_probe_http) > 0)
    {
        g = global.vs_probe_http[0];
        array_delete(global.vs_probe_http, 0, 1);
    }
    var good = _ok && _data != undefined && variable_struct_exists(_data, "ok") && _data.ok;
    vs_online_probe_settle(good, g);
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
    var src = "";
    if (variable_global_exists("vs_with_conn_src"))
    {
        src = string(global.vs_with_conn_src);
        global.vs_with_conn_src = "";
    }
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
        vs_online_with_conn_abort();
        return;
    }
    var st = vs_online_conn_state();
    if (st == 1)
    {
        _fn();
        return;
    }
    if (!variable_global_exists("vs_with_conn_q"))
    {
        global.vs_with_conn_q = [];
        global.vs_with_conn_tag = [];
    }
    if (!variable_global_exists("vs_with_conn_tag") || !is_array(global.vs_with_conn_tag))
    {
        global.vs_with_conn_tag = [];
    }
    array_push(global.vs_with_conn_q, _fn);
    array_push(global.vs_with_conn_tag, src);
    if (array_length(global.vs_with_conn_q) == 1)
    {
        vs_online_probe(vs_online_with_conn_probed);
    }
}

function vs_online_with_conn_probed(_ok)
{
    var q = [];
    var tags = [];
    if (variable_global_exists("vs_with_conn_q"))
    {
        q = global.vs_with_conn_q;
        global.vs_with_conn_q = [];
    }
    if (variable_global_exists("vs_with_conn_tag") && is_array(global.vs_with_conn_tag))
    {
        tags = global.vs_with_conn_tag;
        global.vs_with_conn_tag = [];
    }
    var i = 0;
    var abortedDlbr = false;
    repeat (array_length(q))
    {
        if (q[i] == undefined) { i++; continue; }
        if (_ok) { q[i](); }
        else if (i < array_length(tags) && tags[i] == "dlbr")
        {
            if (!abortedDlbr)
            {
                vs_online_with_conn_abort();
                abortedDlbr = true;
            }
        }
        else { vs_online_show_error(q[i]); }
        i++;
    }
}

function vs_online_with_conn_abort()
{
    if (variable_global_exists("vs_dlmgr_cb") && global.vs_dlmgr_cb != undefined
        && variable_struct_exists(global.vs_dlmgr_cb, "on_done") && global.vs_dlmgr_cb.on_done != undefined)
    {
        var cb = global.vs_dlmgr_cb.on_done;
        global.vs_dlmgr_cb.on_done = undefined;
        cb(false, undefined);
    }
    if (variable_global_exists("vs_lobby_cb") && global.vs_lobby_cb != undefined
        && variable_struct_exists(global.vs_lobby_cb, "on_done") && global.vs_lobby_cb.on_done != undefined)
    {
        var lb = global.vs_lobby_cb.on_done;
        global.vs_lobby_cb.on_done = undefined;
        lb(false, undefined);
    }
}

// Guests / not-logged-in can't use online features. Tells the player and, when
// possible, opens the account panel so they can log in.
function vs_online_show_account_required()
{
    show_message("Guest / not logged in.\n\nOnline features (lobby, leaderboards, web chart downloads) need a signed-in account. Guests can only play already-downloaded charts.\n\n游客/未登录：在线功能已禁用，只能游玩已下载的谱面。请到 设置 → VS Online → Account Management 登录。");
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

function vs_online_error_bind()
{
    do_step = method(id, vs_online_error_step);
    do_draw = method(id, vs_online_error_draw);
}

function vs_online_error_setup(_on_retry)
{
    vs_online_error_bind();
    kind = "connect";
    title = "Cannot Connect to Server";
    buttons = ["Retry", "Disable Custom Server"];
    on_retry = _on_retry;
    server_url = vs_online_server_url();
    message = "The custom server could not be reached.\n" +
        server_url + "\n" +
        "Retry, or switch back to Steam.";
}

function vs_online_show_score_error(_why)
{
    if (instance_exists(vs_online_error))
    {
        return;
    }
    var e = instance_create_depth(0, 0, -10000, vs_online_error);
    with (e)
    {
        vs_online_error_bind();
        kind = "score";
        title = "Score Upload Failed";
        buttons = ["取消", "重试"];
        on_retry = undefined;
        retrying = false;
        selected = 1;
        server_url = vs_online_server_url();
        message = string(_why) + "\n取消 = stay on results.\n重试 = retry upload.";
    }
}

function vs_online_score_retry_upload()
{
    if (!variable_global_exists("vs_score_up") || !is_struct(global.vs_score_up)) return;
    var u = global.vs_score_up;
    if (!variable_struct_exists(u, "chartId") || string(u.chartId) == "") return;
    vs_online_score_log("retry upload chart=" + string(u.chartId) + " pts=" + string(u.pts));
    vs_online_upload_score(u.chartId, u.difficulty, u.sha1, u.pts, "");
}

function vs_online_diff_index(_diff)
{
    var d = string_upper(string(_diff));
    if (d == "OPENING") return 0;
    if (d == "MIDDLE") return 1;
    if (d == "FINALE") return 2;
    if (d == "ENCORE") return 3;
    if (d == "PRELUDE") return 4;
    return 0;
}

function vs_online_error_break(_text, _maxw)
{
    var src = string(_text);
    var out = "";
    var line = "";
    var i = 1;
    var n = string_length(src);
    while (i <= n)
    {
        var c = string_char_at(src, i);
        if (c == "\n" || c == chr(10) || c == chr(13))
        {
            if (c != chr(13))
            {
                out += line + "\n";
                line = "";
            }
        }
        else if (line != "" && string_width(line + c) > _maxw)
        {
            out += line + "\n";
            line = c;
        }
        else line += c;
        i++;
    }
    return out + line;
}

function vs_online_error_clip(_text, _maxw)
{
    var s = string(_text);
    if (string_width(s) <= _maxw) return s;
    while (string_length(s) > 1 && string_width(s + "..") > _maxw)
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    return s + "..";
}

function vs_online_error_font()
{
    if (variable_global_exists("default_font")) return global.default_font;
    return fnt_monacovs;
}

function vs_online_error_draw()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var conflict = (kind == "conflict");
    var bw = min(conflict ? 420 : 280, max(80, cw - 8));
    var bh = min(conflict ? 210 : 130, max(70, ch - 8));
    var bx = (cw - bw) / 2;
    var by = (ch - bh) / 2;
    var pad = 8;
    var maxw = bw - pad * 2;
    var btn_h = 18;
    var yb = by + bh - btn_h - pad;
    var sep = 11;

    draw_set_alpha(0.7);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);

    draw_set_color(c_black);
    draw_rectangle(bx - 2, by - 2, bx + bw + 2, by + bh + 2, false);
    draw_set_color(c_white);
    draw_rectangle(bx, by, bx + bw, by + bh, true);

    draw_set_halign(fa_center);
    draw_set_valign(fa_top);
    draw_set_font(fnt_monacovs);
    draw_set_color(c_red);
    var ttl = vs_online_error_clip(title, maxw);
    draw_text(bx + bw / 2, by + 5, ttl);

    draw_set_font(vs_online_error_font());
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    var msg = vs_online_error_break(message, maxw);
    var msgTop = by + 22;
    var msgH = yb - msgTop - 4;
    var maxLines = max(1, floor(msgH / sep));
    var shown = "";
    var line = "";
    var used = 0;
    var i = 1;
    var n = string_length(msg);
    while (i <= n && used < maxLines)
    {
        var c = string_char_at(msg, i);
        if (c == "\n")
        {
            if (used > 0) shown += "\n";
            shown += line;
            line = "";
            used += 1;
        }
        else line += c;
        i++;
    }
    if (line != "" && used < maxLines)
    {
        if (used > 0) shown += "\n";
        shown += line;
    }
    draw_text_ext(bx + pad, msgTop, shown, sep, maxw);

    var nbtn = array_length(buttons);
    var btn_w = (nbtn <= 1) ? (bw - pad * 2) : floor((bw - pad * (nbtn + 1)) / nbtn);
    var bi = 0;
    repeat (nbtn)
    {
        var xb = bx + pad + bi * (btn_w + pad);
        var isSel = (bi == selected);
        if (isSel)
        {
            draw_set_color(c_yellow);
            draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, false);
            draw_set_color(c_black);
        }
        else
        {
            draw_set_color(make_color_rgb(48, 48, 48));
            draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, false);
            draw_set_color(c_gray);
            draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, true);
            draw_set_color(c_white);
        }
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(xb + btn_w / 2, yb + btn_h / 2, vs_online_error_clip(buttons[bi], btn_w - 4));
        bi++;
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

function vs_online_error_step()
{
    if (kind == "conflict")
    {
        if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space) || keyboard_check_pressed(vk_escape))
        {
            game_end();
        }
        return;
    }
    if (retrying)
    {
        return;
    }

    if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_tab) || input_check_pressed(11))
    {
        selected = (selected + 1) % array_length(buttons);
        play_se(sfx_songsel_cursor);
    }
    else if (keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_right) || input_check_pressed(12))
    {
        selected = (selected + array_length(buttons) - 1) % array_length(buttons);
        play_se(sfx_songsel_cursor);
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space) || input_check_pressed(4))
    {
        play_se(sfx_songsel_select);
        if (kind == "score")
        {
            var btn = buttons[selected];
            instance_destroy();
            if (btn == "重试") vs_online_score_retry_upload();
        }
        else if (selected == 0)
        {
            retrying = true;
            message = "Retrying...";
            vs_online_probe(vs_online_error_on_probe);
        }
        else
        {
            vs_online_with_conn_abort();
            vs_online_disable_custom();
            instance_destroy();
        }
    }
    else if (keyboard_check_pressed(vk_escape) || input_check_pressed(5))
    {
        vs_online_with_conn_abort();
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
            if (cb != undefined) { cb(); }
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
    vs_online_apply_custom_off();
    show_debug_message("VS Online: custom server disabled by player.");
}

// --- packet out (M3: WebSocket binary frame to the lobby relay) -------------

// Called from the patched send_packet while on the custom server.
function vs_online_send_packet(_type, _buffer)
{
    vs_lobby_send_packet(_type, _buffer);
}
