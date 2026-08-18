// ============================================================================
// vs_ws.gml — pure GML WebSocket client (RFC 6455) over GameMaker raw TCP.
//
// GameMaker has no WebSocket support, so this hand-rolls it:
//   - network_connect_raw + network_send_raw (raw TCP)
//   - manual HTTP Upgrade handshake
//   - manual frame encode (client frames are MASKED) / decode (server frames
//     are unmasked), incl. ping/pong + close
//   - TCP stream reassembly (a frame may arrive split across async events)
//
// Async delivery: a long-lived coroutine registered via
// __CoroutineAwaitAsync("networking", ...) receives every async networking
// event (oCoroutineManager_Other_68 -> CoroutineEventHook) and funnels it into
// vs_ws_handle_net_event(). This is the game's own coroutine library.
//
// NOTE: pure-GML edge cases here need runtime verification against the real
// game + a live vs-server-go before relying on it (see "Runtime notes").
// ============================================================================

// --- state -----------------------------------------------------------------

function vs_ws_state()
{
    if (!variable_global_exists("vs_ws"))
    {
        global.vs_ws =
        {
            socket: -1,
            state: 0,              // 0 idle, 1 connecting, 2 handshaking, 3 open
            host: "",
            port: 80,
            path: "",
            token: "",
            rxBuf: buffer_create(8192, buffer_grow, 1),
            rxCount: 0,            // total bytes accumulated
            rxPos: 0,              // bytes already consumed
            frames: [],            // received payloads: { op: 1|2, buf: <buffer> }
            lastError: ""
        };
    }
    return variable_global_get("vs_ws");
}

// --- URL helpers -----------------------------------------------------------

// Derive host/port from the configured server URL.
function vs_ws_host_port()
{
    var url = vs_online_server_url();
    var defPort = 80;
    if (string_pos("https://", url) > 0)
    {
        defPort = 443;
        url = string_replace(url, "https://", "");
    }
    else
    {
        url = string_replace(url, "http://", "");
    }
    var slash = string_pos("/", url);
    if (slash > 0)
    {
        url = string_copy(url, 1, slash - 1);
    }
    var colon = string_pos(":", url);
    if (colon > 0)
    {
        return { host: string_copy(url, 1, colon - 1), port: real(string_copy(url, colon + 1, string_length(url) - colon)) };
    }
    return { host: url, port: defPort };
}

// --- lifecycle -------------------------------------------------------------

// Start the persistent async-networking listener coroutine (idempotent).
function vs_ws_start_listener()
{
    if (variable_global_exists("vs_ws_listener_started") && variable_global_get("vs_ws_listener_started"))
    {
        return;
    }
    global.vs_ws_listener_started = true;
    __CoroutineBegin(function()
    {
        // Never-completing await: stays registered so every networking async
        // event reaches the WS handler.
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
        vs_ws_close();
    }
    var hp = vs_ws_host_port();
    ws.host = hp.host;
    ws.port = hp.port;
    ws.path = _path;
    ws.token = _token;
    ws.rxPos = 0;
    ws.rxCount = 0;
    ws.lastError = "";
    ws.socket = network_create_socket();
    ws.state = 1;
    network_connect_raw(ws.socket, ws.host, ws.port);
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
        // best-effort masked close frame
        var f = buffer_create(6, buffer_fixed, 1);
        buffer_write(f, buffer_u8, 0x88);                       // FIN + close
        buffer_write(f, buffer_u8, 0x80);                       // masked, len 0
        buffer_write(f, buffer_u8, 0); buffer_write(f, buffer_u8, 0);
        buffer_write(f, buffer_u8, 0); buffer_write(f, buffer_u8, 0);
        network_send_raw(ws.socket, f, buffer_get_size(f));
        buffer_delete(f);
        network_destroy(ws.socket);
        ws.socket = -1;
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
    ws.rxPos = 0;
    ws.rxCount = 0;
}

// Pop the next received frame, or undefined. Frame = { op, buf }.
function vs_ws_poll()
{
    var ws = vs_ws_state();
    if (array_length(ws.frames) == 0)
    {
        return undefined;
    }
    var f = ws.frames[0];
    array_delete(ws.frames, 0, 1);
    return f;
}

// --- async networking event (called from the coroutine listener) -----------

function vs_ws_handle_net_event()
{
    var ws = vs_ws_state();
    var type = async_load[? "type"];
    var socketId = async_load[? "id"];   // 'id' is a GML builtin; can't shadow it as a local
    if (ws.socket < 0 || socketId != ws.socket)
    {
        return; // not our socket
    }

    if (type == network_type_connect)
    {
        ws.state = 2;
        vs_ws_send_handshake();
    }
    else if (type == network_type_data)
    {
        var dataBuf = async_load[? "buffer"];
        var dataSize = async_load[? "size"];
        if (dataSize > 0)
        {
            buffer_copy(dataBuf, 0, ws.rxBuf, ws.rxCount, dataSize);
            ws.rxCount += dataSize;
        }
        if (ws.state == 2)
        {
            vs_ws_try_finish_handshake();
        }
        if (ws.state == 3)
        {
            vs_ws_parse_frames();
            vs_ws_compact();
        }
    }
    else if (type == network_type_disconnect)
    {
        show_debug_message("VS WS: disconnected");
        vs_ws_reset();
    }
}

// --- handshake -------------------------------------------------------------

function vs_ws_send_handshake()
{
    var ws = vs_ws_state();
    var keyBuf = buffer_create(16, buffer_fixed, 1);
    var i = 0;
    repeat (16)
    {
        buffer_write(keyBuf, buffer_u8, irandom_range(0, 255));
    }
    var key = buffer_base64_encode(keyBuf, 0, 16);
    buffer_delete(keyBuf);

    var req =
        "GET " + ws.path + " HTTP/1.1\r\n" +
        "Host: " + ws.host + ":" + string(ws.port) + "\r\n" +
        "Upgrade: websocket\r\n" +
        "Connection: Upgrade\r\n" +
        "Sec-WebSocket-Key: " + key + "\r\n" +
        "Sec-WebSocket-Version: 13\r\n\r\n";

    var buf = buffer_create(string_length(req) + 1, buffer_fixed, 1);
    buffer_write(buf, buffer_string, req);
    network_send_raw(ws.socket, buf, string_length(req)); // send without the trailing null
    buffer_delete(buf);
}

// Scan rxBuf for "\r\n\r\n"; on finding it, verify "101" and switch to open.
function vs_ws_try_finish_handshake()
{
    var ws = vs_ws_state();
    var i = 0;
    while (i < ws.rxCount - 3)
    {
        if (buffer_peek(ws.rxBuf, i, buffer_u8) == 13
         && buffer_peek(ws.rxBuf, i + 1, buffer_u8) == 10
         && buffer_peek(ws.rxBuf, i + 2, buffer_u8) == 13
         && buffer_peek(ws.rxBuf, i + 3, buffer_u8) == 10)
        {
            // "HTTP/1.1 101" — check the three status digits at offset 9..11
            var ok101 = (buffer_peek(ws.rxBuf, 9, buffer_u8) == 49)
                     && (buffer_peek(ws.rxBuf, 10, buffer_u8) == 48)
                     && (buffer_peek(ws.rxBuf, 11, buffer_u8) == 49);
            ws.rxPos = i + 4;
            if (ok101)
            {
                ws.state = 3;
                show_debug_message("VS WS: open (" + ws.host + ":" + string(ws.port) + ws.path + ")");
                vs_ws_parse_frames();
                vs_ws_compact();
            }
            else
            {
                show_debug_message("VS WS: handshake rejected");
                ws.lastError = "handshake_rejected";
                vs_ws_reset();
            }
            return;
        }
        i++;
    }
}

// --- frame receive ---------------------------------------------------------

function vs_ws_parse_frames()
{
    var ws = vs_ws_state();
    while (ws.rxCount - ws.rxPos >= 2)
    {
        var b0 = buffer_peek(ws.rxBuf, ws.rxPos, buffer_u8);
        var b1 = buffer_peek(ws.rxBuf, ws.rxPos + 1, buffer_u8);
        var opcode = b0 & 0x0f;
        var masked = (b1 & 0x80) != 0;
        var len = b1 & 0x7f;
        var headerLen = 2;

        if (len == 126)
        {
            if (ws.rxCount - ws.rxPos < 4) return;
            var hi = buffer_peek(ws.rxBuf, ws.rxPos + 2, buffer_u8);
            var lo = buffer_peek(ws.rxBuf, ws.rxPos + 3, buffer_u8);
            len = (hi << 8) | lo;
            headerLen = 4;
        }
        else if (len == 127)
        {
            if (ws.rxCount - ws.rxPos < 10) return;
            len = 0;
            var k = 0;
            repeat (8)
            {
                len = len * 256 + buffer_peek(ws.rxBuf, ws.rxPos + 2 + k, buffer_u8);
                k++;
            }
            headerLen = 10;
        }

        var maskPos = ws.rxPos + headerLen;
        var payloadPos = maskPos + (masked ? 4 : 0);
        var totalLen = headerLen + (masked ? 4 : 0) + len;
        if (ws.rxCount - ws.rxPos < totalLen)
        {
            return; // incomplete frame, wait for more data
        }

        // extract payload
        var payload = buffer_create(len, buffer_fixed, 1);
        if (masked)
        {
            var mk0 = buffer_peek(ws.rxBuf, maskPos + 0, buffer_u8);
            var mk1 = buffer_peek(ws.rxBuf, maskPos + 1, buffer_u8);
            var mk2 = buffer_peek(ws.rxBuf, maskPos + 2, buffer_u8);
            var mk3 = buffer_peek(ws.rxBuf, maskPos + 3, buffer_u8);
            var mk = [mk0, mk1, mk2, mk3];
            var j = 0;
            repeat (len)
            {
                var raw = buffer_peek(ws.rxBuf, payloadPos + j, buffer_u8);
                buffer_write(payload, buffer_u8, raw ^ mk[j % 4]);
                j++;
            }
        }
        else
        {
            buffer_copy(ws.rxBuf, payloadPos, payload, 0, len);
        }

        switch (opcode)
        {
            case 1: // text
            case 2: // binary
                // Hand payload ownership to the mod dispatcher (it parses the
                // [len][playerId] prefix / JSON control frame and deletes buf).
                vs_online_on_ws_frame(opcode, payload);
                break;
            case 9: // ping -> pong
                vs_ws_send_frame(0xA, payload);
                buffer_delete(payload);
                break;
            case 8: // close
                vs_ws_close();
                buffer_delete(payload);
                break;
            default:
                buffer_delete(payload);
                break;
        }

        ws.rxPos += totalLen;
    }
}

// Drop consumed bytes from rxBuf periodically.
function vs_ws_compact()
{
    var ws = vs_ws_state();
    if (ws.rxPos == 0)
    {
        return;
    }
    if (ws.rxPos == ws.rxCount)
    {
        ws.rxPos = 0;
        ws.rxCount = 0;
        return;
    }
    if (ws.rxPos > 65536)
    {
        var rem = ws.rxCount - ws.rxPos;
        var tmp = buffer_create(rem, buffer_fixed, 1);
        buffer_copy(ws.rxBuf, ws.rxPos, tmp, 0, rem);
        buffer_copy(tmp, 0, ws.rxBuf, 0, rem);
        buffer_delete(tmp);
        ws.rxCount = rem;
        ws.rxPos = 0;
    }
}

// --- frame send ------------------------------------------------------------

// Send one masked frame. _payload is a buffer (may be empty).
function vs_ws_send_frame(_opcode, _payload)
{
    var ws = vs_ws_state();
    if (ws.socket < 0 || ws.state != 3)
    {
        return;
    }
    var len = buffer_get_size(_payload);
    var headerLen = 2;
    var ext = 0;
    if (len >= 126 && len < 65536)
    {
        ext = 2;
        headerLen = 4;
    }
    else if (len >= 65536)
    {
        ext = 8;
        headerLen = 10;
    }

    var frame = buffer_create(headerLen + 4 + len, buffer_fixed, 1);
    buffer_write(frame, buffer_u8, 0x80 | (_opcode & 0x0f));   // FIN + opcode
    if (ext == 0)
    {
        buffer_write(frame, buffer_u8, 0x80 | len);
    }
    else if (ext == 2)
    {
        buffer_write(frame, buffer_u8, 0x80 | 126);
        buffer_write(frame, buffer_u8, (len >> 8) & 0xff);
        buffer_write(frame, buffer_u8, len & 0xff);
    }
    else
    {
        buffer_write(frame, buffer_u8, 0x80 | 127);
        var k = 7;
        repeat (8)
        {
            buffer_write(frame, buffer_u8, (len >> (8 * k)) & 0xff);
            k--;
        }
    }

    var mk = [irandom_range(0, 255), irandom_range(0, 255), irandom_range(0, 255), irandom_range(0, 255)];
    buffer_write(frame, buffer_u8, mk[0]);
    buffer_write(frame, buffer_u8, mk[1]);
    buffer_write(frame, buffer_u8, mk[2]);
    buffer_write(frame, buffer_u8, mk[3]);

    var i = 0;
    repeat (len)
    {
        var raw = buffer_peek(_payload, i, buffer_u8);
        buffer_write(frame, buffer_u8, raw ^ mk[i % 4]);
        i++;
    }

    network_send_raw(ws.socket, frame, buffer_get_size(frame));
    buffer_delete(frame);
}

function vs_ws_send_binary(_buffer)
{
    vs_ws_send_frame(2, _buffer);
}

function vs_ws_send_text(_str)
{
    var buf = buffer_create(string_length(_str) + 1, buffer_fixed, 1);
    buffer_write(buf, buffer_string, _str);
    vs_ws_send_frame(1, buf);
    buffer_delete(buf);
}

// ============================================================================
// Runtime notes (verify with a live game + vs-server-go):
//  - async_load keys for raw sockets: "type"/"id"/"buffer"/"size"
//  - network_type_connect / network_type_data / network_type_disconnect values
//  - buffer_copy growing a buffer_grow destination
//  - buffer_base64_encode output is standard padded base64 (16-byte key)
// ============================================================================
