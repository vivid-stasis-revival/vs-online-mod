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
//   "server": "http://localhost:8080",        // vs-server-go base URL
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

    var cfg = { server: "http://localhost:8080" };
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
        cfg.server = "http://localhost:8080";
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
}

// --- init ------------------------------------------------------------------

function vs_online_init()
{
    vs_online_get_config();
    vs_ws_start_listener();
    if (vs_online_is_custom())
    {
        vs_online_ensure_identity(function(_ok, _data)
        {
            show_debug_message("VS Online: identity " + (_ok ? ("ok " + vs_online_player_id()) : "failed"));
        });
    }
}

// --- packet out (M3 wires the real WebSocket transport) --------------------

// Called from the patched send_packet while on the custom server.
function vs_online_send_packet(_type, _buffer)
{
    // M0 stub — M3 replaces this with a WebSocket binary frame to the lobby relay.
    show_debug_message("VS Online: send_packet type=" + string(_type) + " not wired yet (M3)");
}
