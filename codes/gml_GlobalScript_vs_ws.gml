// ============================================================================
// vs_ws.gml — GameMaker native WebSocket client (ws:// / wss://).
//
// Runner (2024.14) already has network_socket_ws / network_socket_wss.
// GM does the HTTP Upgrade, TLS, masking, and ping/pong. We send/receive
// application payloads only via network_send_raw / network_type_data.
//
// Connect must be async: network_connect_raw_async →
// network_type_non_blocking_connect ("succeeded").
// URL is a full ws(s)://host/path?query string; port is a separate arg
// (do not put :443 inside the URL — GM would append it again).
//
// Async delivery: a long-lived coroutine registered via
// __CoroutineAwaitAsync("networking", ...) receives every async networking
// event (oCoroutineManager_Other_68 -> CoroutineEventHook) and funnels it into
// vs_ws_handle_net_event().
// ============================================================================

// --- state -----------------------------------------------------------------

function vs_ws_state()
{
    if (!variable_global_exists("vs_ws"))
    {
        global.vs_ws =
        {
            socket: -1,
            state: 0,              // 0 idle, 1 connecting, 3 open
            host: "",
            port: 443,
            path: "",
            url: "",
            token: "",
            lastError: ""
        };
    }
    return variable_global_get("vs_ws");
}

function vs_ws_log(_msg)
{
    var line = "VS WS: " + string(_msg);
    show_debug_message(line);
    vs_songstore_log("WS " + string(_msg));
}

function vs_ws_url_redact(_url)
{
    var u = string(_url);
    var p = string_pos("token=", u);
    if (p <= 0) return u;
    return string_copy(u, 1, p + 5) + "***";
}

// --- URL helpers -----------------------------------------------------------

// scheme / host / port from vs_online_ws_url(). Path on the base URL is ignored
// (lobby always supplies /api/v1/lobbies/.../ws).
function vs_ws_parse_base()
{
    var raw = vs_online_ws_url();
    var u = string(raw);
    var low = string_lower(u);
    var scheme = "ws";
    var defPort = 80;
    if (string_pos("wss://", low) == 1)
    {
        scheme = "wss";
        defPort = 443;
        u = string_copy(u, 7, string_length(u) - 6);
    }
    else if (string_pos("ws://", low) == 1)
    {
        u = string_copy(u, 6, string_length(u) - 5);
    }
    else if (string_pos("https://", low) == 1)
    {
        scheme = "wss";
        defPort = 443;
        u = string_copy(u, 9, string_length(u) - 8);
    }
    else if (string_pos("http://", low) == 1)
    {
        u = string_copy(u, 8, string_length(u) - 7);
    }

    var slash = string_pos("/", u);
    if (slash > 0)
    {
        u = string_copy(u, 1, slash - 1);
    }

    var host = u;
    var port = defPort;
    var colon = string_pos(":", u);
    if (colon > 0)
    {
        host = string_copy(u, 1, colon - 1);
        port = vs_http_num(string_copy(u, colon + 1, string_length(u) - colon), defPort);
    }
    return { scheme: scheme, host: host, port: port, secure: (scheme == "wss") };
}

// --- lifecycle -------------------------------------------------------------

function vs_ws_start_listener()
{
    if (variable_global_exists("vs_ws_listener_started") && variable_global_get("vs_ws_listener_started"))
    {
        return;
    }
    global.vs_ws_listener_started = true;
    __CoroutineBegin(function()
    {
        __CoroutineAwaitAsync("networking", function()
        {
            vs_ws_handle_net_event();
            return false;
        });
    });
    __CoroutineEnd();
}

// Open a connection. _path is the full request path incl. query,
// e.g. "/api/v1/lobbies/ABC123/ws?token=…".
function vs_ws_connect(_path, _token)
{
    var ws = vs_ws_state();
    if (ws.socket >= 0)
    {
        vs_ws_log("connect replace existing state=" + string(ws.state));
        vs_ws_close();
    }
    var base = vs_ws_parse_base();
    ws.host = base.host;
    ws.port = base.port;
    ws.token = _token;
    var path = _path;
    if (_token == undefined || _token == "")
    {
        vs_ws_log("connect no token path=" + string(_path));
    }
    else
    {
        path += (string_pos("?", path) > 0 ? "&" : "?") + "token=" + vs_online_url_encode(_token);
    }
    if (string_pos("/", path) != 1)
    {
        path = "/" + path;
    }
    ws.path = path;
    ws.lastError = "";

    // Full URL without :port — GM appends the port argument itself.
    var url = base.scheme + "://" + base.host + path;
    ws.url = url;

    var sockType = base.secure ? network_socket_wss : network_socket_ws;
    ws.socket = network_create_socket(sockType);
    if (ws.socket < 0)
    {
        ws.lastError = "socket_create";
        vs_ws_log("network_create_socket failed type=" + string(sockType) + " secure=" + string(base.secure));
        return;
    }
    ws.state = 1;
    ws.asyncId = ws.socket;
    var rc = network_connect_raw_async(ws.socket, url, ws.port);
    if (rc < 0)
    {
        vs_ws_log("connect start failed " + vs_ws_url_redact(url) + " :" + string(ws.port) + " rc=" + string(rc));
        ws.lastError = "connect_start";
        vs_lobby_send_q_clear();
        vs_ws_reset();
        return;
    }
    vs_ws_log("connecting " + vs_ws_url_redact(url) + " :" + string(ws.port) + " path=" + string(_path));
}

function vs_ws_is_open()
{
    return vs_ws_state().state == 3;
}

function vs_ws_close()
{
    var ws = vs_ws_state();
    if (ws.socket >= 0)
    {
        vs_ws_log("close sock=" + string(ws.socket) + " state=" + string(ws.state));
        network_destroy(ws.socket);
        ws.socket = -1;
    }
    else if (ws.state != 0)
    {
        vs_ws_log("close no sock state=" + string(ws.state));
    }
    ws.state = 0;
}

function vs_ws_reset()
{
    var ws = vs_ws_state();
    if (ws.socket >= 0)
    {
        network_destroy(ws.socket);
        ws.socket = -1;
    }
    ws.state = 0;
}

// --- async networking event -----------------------------------------------

function vs_ws_mark_open(_why)
{
    var ws = vs_ws_state();
    var was = ws.state;
    ws.state = 3;
    if (was != 3)
    {
        vs_ws_log("open (" + string(_why) + ") " + vs_ws_url_redact(ws.url));
        vs_lobby_send_q_flush();
    }
}

function vs_ws_handle_net_event()
{
    if (async_load == -1) return;
    var type = ds_map_find_value(async_load, "type");
    var socketId = vs_http_num(ds_map_find_value(async_load, "id"), -1);
    var sz = vs_http_num(ds_map_find_value(async_load, "size"), -1);
    var fp = string(type) + ":" + string(socketId) + ":" + string(sz) + ":" + string(current_time);
    if (variable_global_exists("vs_ws_evt_fp") && global.vs_ws_evt_fp == fp)
    {
        return;
    }
    global.vs_ws_evt_fp = fp;

    var ws = vs_ws_state();
    var sock = vs_http_num(ws.socket, -2);
    var succeeded = ds_map_find_value(async_load, "succeeded");
    if (ws.state != 3)
    {
        vs_ws_log("evt type=" + string(type) + " id=" + string(socketId) + " sock=" + string(sock)
            + " state=" + string(ws.state) + " ok=" + string(succeeded) + " size=" + string(sz));
    }
    if (ws.socket < 0)
    {
        return;
    }
    var id_ok = (socketId == sock);
    if (!id_ok && variable_struct_exists(ws, "asyncId") && socketId == vs_http_num(ws.asyncId, -3))
    {
        id_ok = true;
    }
    if (!id_ok)
    {
        // Runner WSS often reports a different async id than network_create_socket.
        if (ws.state == 1 && (type == network_type_non_blocking_connect
            || type == network_type_connect
            || type == network_type_data
            || type == network_type_disconnect))
        {
            ws.asyncId = socketId;
            id_ok = true;
            vs_ws_log("evt bind asyncId=" + string(socketId) + " sock=" + string(sock));
        }
        else
        {
            return;
        }
    }

    if (type == network_type_non_blocking_connect)
    {
        var ok = (succeeded == true) || (is_real(succeeded) && succeeded != 0);
        if (ok)
        {
            vs_ws_mark_open("async");
        }
        else
        {
            vs_ws_log("connect failed " + vs_ws_url_redact(ws.url) + " ok=" + string(succeeded));
            ws.lastError = "connect_failed";
            vs_lobby_send_q_clear();
            vs_ws_reset();
        }
    }
    else if (type == network_type_connect)
    {
        vs_ws_mark_open("sync");
    }
    else if (type == network_type_data)
    {
        // Welcome can arrive before the connect-succeeded event; ignoring it
        // leaves state=connecting forever (queue send, never recv).
        if (ws.state != 3)
        {
            vs_ws_mark_open("first data");
        }
        vs_ws_dispatch_payload();
    }
    else if (type == network_type_disconnect)
    {
        vs_ws_log("disconnected url=" + vs_ws_url_redact(ws.url));
        vs_lobby_send_q_clear();
        vs_ws_reset();
    }
    else
    {
        vs_ws_log("net event type=" + string(type) + " state=" + string(ws.state));
    }
}

// Native WS delivers one complete app message per event. Copy out — the
// async buffer is freed when the event ends.
function vs_ws_dispatch_payload()
{
    var dataBuf = ds_map_find_value(async_load, "buffer");
    var dataSize = ds_map_find_value(async_load, "size");
    if (dataSize < 0)
    {
        dataSize = 0;
    }
    // Classify by payload, not message_type. Runner WSS often tags binary
    // relay frames as text; sender-len 36 is ASCII `$`, which is not JSON.
    var first = 0;
    if (dataSize > 0)
    {
        first = buffer_peek(dataBuf, 0, buffer_u8);
    }
    var opcode = 2;
    if (first == 123 || first == 91)
    {
        opcode = 1;
    }

    var payload = buffer_create(max(dataSize, 1), buffer_fixed, 1);
    if (dataSize > 0)
    {
        buffer_copy(dataBuf, 0, dataSize, payload, 0);
    }
    buffer_seek(payload, buffer_seek_start, 0);
    vs_online_on_ws_frame(opcode, payload);
}

// --- send ------------------------------------------------------------------

function vs_ws_send_binary(_buffer)
{
    var ws = vs_ws_state();
    if (ws.socket < 0 || ws.state != 3)
    {
        vs_ws_log("send skip state=" + string(ws.state) + " sock=" + string(ws.socket));
        return;
    }
    network_send_raw(ws.socket, _buffer, buffer_get_size(_buffer));
}

function vs_ws_send_text(_str)
{
    var ws = vs_ws_state();
    if (ws.socket < 0 || ws.state != 3)
    {
        return;
    }
    var buf = buffer_create(string_length(_str) + 1, buffer_fixed, 1);
    buffer_write(buf, buffer_string, _str);
    // 3-arg network_send_raw (vsml arity); default on WS sockets is binary.
    // Control JSON from this client is unused; server text frames still arrive
    // via message_type on receive.
    network_send_raw(ws.socket, buf, string_length(_str));
    buffer_delete(buf);
}
