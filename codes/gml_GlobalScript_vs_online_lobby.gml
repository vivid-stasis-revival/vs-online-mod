// ============================================================================
// vs_online_lobby.gml — lobby client over vs-server-go (REST + WS relay)
//
// Replaces the Steam lobby flow when vs_online_is_custom(). Lobby state is
// written straight into o_st_handle (lobbyId/lobbyCode/lobbyMembers/...) so the
// rest of the game's multiplayer code reads the same fields.
//
// Wire format on the WS relay:
//   binary frame = [u8 senderIdLen][senderId][game packet]  (server stamps sender)
//   text frame   = JSON control message from the server
// ============================================================================

function vs_lobby_in_lobby()
{
    return vs_ws_is_open();
}

// --- steam_* shims (used via codepatches so the WP UI reads server state) ---

function vs_lobby_lobby_id()
{
    if (vs_online_is_custom())
    {
        return (instance_exists(o_st_handle) && o_st_handle.lobbyId != undefined) ? o_st_handle.lobbyId : 0;
    }
    return steam_lobby_get_lobby_id();
}

function vs_lobby_is_owner()
{
    if (vs_online_is_custom())
    {
        return instance_exists(o_st_handle)
            && o_st_handle.vs_hostId != undefined
            && vs_online_player_id() == o_st_handle.vs_hostId;
    }
    return steam_lobby_is_owner();
}

function vs_lobby_owner_id()
{
    if (vs_online_is_custom())
    {
        return (instance_exists(o_st_handle) && o_st_handle.vs_hostId != undefined) ? o_st_handle.vs_hostId : "";
    }
    return steam_lobby_get_owner_id();
}

// The game's self-id; on the custom server it is the server playerId.
function vs_online_custom_id()
{
    if (vs_online_is_custom())
    {
        return vs_online_player_id();
    }
    return steam_get_user_steam_id();
}

function vs_online_is_connected()
{
    if (vs_online_is_custom())
    {
        return vs_online_is_account() || vs_online_player_id() != "" || vs_online_token() != "";
    }
    return steam_is_user_logged_on();
}

// vsml treats `score` as the built-in instance var. Never read/write
// member.score with the identifier — use these string-key helpers.
function vs_member_get_score(_m)
{
    if (_m == undefined) return 0;
    if (variable_struct_exists(_m, "score")) return variable_struct_get(_m, "score");
    if (variable_struct_exists(_m, "score_")) return variable_struct_get(_m, "score_");
    return 0;
}

function vs_member_set_score(_m, _v)
{
    if (_m == undefined) return;
    variable_struct_set(_m, "score", _v);
    variable_struct_set(_m, "score_", _v);
}

// --- member struct ---------------------------------------------------------

// Deterministic avatar fallback: hash(name) -> a jacket from global.song_list.
function vs_online_avatar_sprite(_name)
{
    if (!variable_global_exists("song_list") || array_length(global.song_list) == 0)
    {
        return undefined;
    }
    var idx = vs_online_str_hash(_name) % array_length(global.song_list);
    var song = global.song_list[idx];
    if (song == undefined) return undefined;
    var jk = song_get_info(song, "jacket", 0);
    return (jk == undefined) ? undefined : jk;
}

function vs_online_avatar_cache()
{
    if (!variable_global_exists("vs_avatar_spr"))
    {
        global.vs_avatar_spr = {};
        global.vs_avatar_q = [];
        global.vs_avatar_busy = false;
        global.vs_avatar_cur = "";
        global.vs_avatar_req = -1;
    }
    return global.vs_avatar_spr;
}

function vs_online_avatar_ensure(_playerId, _url)
{
    if (_playerId == undefined || _playerId == "" || _url == undefined || _url == "") return undefined;
    var cache = vs_online_avatar_cache();
    if (variable_struct_exists(cache, _playerId))
    {
        return variable_struct_get(cache, _playerId);
    }
    var i = 0;
    repeat (array_length(global.vs_avatar_q))
    {
        if (global.vs_avatar_q[i].id == _playerId) return undefined;
        i++;
    }
    array_push(global.vs_avatar_q, { id: _playerId, url: _url });
    vs_online_avatar_pump();
    return undefined;
}

function vs_online_avatar_pump()
{
    vs_online_avatar_cache();
    if (global.vs_avatar_busy) return;
    if (array_length(global.vs_avatar_q) == 0) return;
    var job = global.vs_avatar_q[0];
    array_delete(global.vs_avatar_q, 0, 1);
    global.vs_avatar_busy = true;
    global.vs_avatar_cur = job.id;
    if (!directory_exists("vs_avatars")) directory_create("vs_avatars");
    var dest = "vs_avatars/" + job.id + ".png";
    global.vs_avatar_req = http_get_file(job.url, dest);
    __CoroutineBegin(function()
    {
        __CoroutineAwaitAsync("http", vs_online_avatar_http);
    });
    __CoroutineEnd();
}

function vs_online_avatar_http()
{
    if (async_load == -1)
    {
        vs_online_avatar_finish(false);
        return true;
    }
    if (ds_map_find_value(async_load, "id") != global.vs_avatar_req) return false;
    var httpSt = ds_map_find_value(async_load, "http_status");
    var st = ds_map_find_value(async_load, "status");
    vs_online_avatar_finish(httpSt == 200 || st == 0);
    return true;
}

function vs_online_avatar_finish(_ok)
{
    var pid = global.vs_avatar_cur;
    var dest = "vs_avatars/" + pid + ".png";
    if (_ok && file_exists(dest))
    {
        var spr = sprite_add(dest, 1, false, false, 0, 0);
        if (spr != -1)
        {
            variable_struct_set(vs_online_avatar_cache(), pid, spr);
            if (instance_exists(o_st_handle))
            {
                var m = o_st_handle.getMember(pid);
                if (m != undefined) m.avatar = spr;
            }
        }
    }
    global.vs_avatar_busy = false;
    global.vs_avatar_cur = "";
    vs_online_avatar_pump();
}

// Build a game-style member from a server MemberView JSON object.
function vs_lobby_build_member(_mv)
{
    // Server avatar URL is fetched into a sprite; empty/failed falls back to
    // a deterministic jacket (hash(name) -> song_list jacket).
    var hasAvatar = variable_struct_exists(_mv, "avatar") && _mv.avatar != "";
    var av = vs_online_avatar_sprite(_mv.name);
    if (hasAvatar)
    {
        var fetched = vs_online_avatar_ensure(_mv.playerId, _mv.avatar);
        if (fetched != undefined) av = fetched;
    }
    var m =
    {
        id: _mv.playerId,
        name: variable_struct_exists(_mv, "name") ? _mv.name : "",
        ready: variable_struct_exists(_mv, "ready") ? _mv.ready : 0,
        scoreFlag: variable_struct_exists(_mv, "scoreFlag") ? _mv.scoreFlag : 1,
        avatar: av,
        reportedScore: true,
        host: variable_struct_exists(_mv, "host") ? _mv.host : false,
        npc: false,
        rate: variable_struct_exists(_mv, "rate") ? _mv.rate : 0,
        class: variable_struct_exists(_mv, "class") ? _mv.class : 0,
        sticker_scale: 0,
        sticker_alpha: 0,
        sticker_id: 0,
        sticker_timer: 0,
        is_winner: false,
        order: variable_struct_exists(_mv, "order") ? _mv.order : 0,
        remove_sticker: function()
        {
            var _m = o_st_handle.getMember(self.id);
            if (_m != undefined)
            {
                TweenFire(_m, EaseOutBack, 0, true, 0, 0.5, "sticker_scale", 0, 1);
                TweenFire(_m, EaseOutExpo, 0, true, 0, 0.5, "sticker_alpha", 0, 1);
            }
        }
    };
    var sc = variable_struct_exists(_mv, "score") ? variable_struct_get(_mv, "score") : 0;
    vs_member_set_score(m, sc);
    return m;
}

function vs_lobby_apply_roster(_members)
{
    if (!instance_exists(o_st_handle)) return;
    var arr = [];
    var i = 0;
    repeat (array_length(_members))
    {
        arr[i] = vs_lobby_build_member(_members[i]);
        i++;
    }
    o_st_handle.lobbyMembers = arr;
}

function vs_lobby_remove_member(_id)
{
    if (!instance_exists(o_st_handle)) return;
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        if (o_st_handle.lobbyMembers[i].id == _id)
        {
            array_delete(o_st_handle.lobbyMembers, i, 1);
            break;
        }
        i++;
    }
    var j = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        o_st_handle.lobbyMembers[j].order = j;
        j++;
    }
}

function vs_lobby_refresh_host_flags(_hostId)
{
    if (!instance_exists(o_st_handle)) return;
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        o_st_handle.lobbyMembers[i].host = (o_st_handle.lobbyMembers[i].id == _hostId);
        i++;
    }
}

// --- REST entry points -----------------------------------------------------
//
// COMPILER NOTE: anonymous functions in loader-injected scripts cannot capture
// enclosing arguments/`var` locals (they compile to `self.<name>` reads and
// crash). Cross-callback state travels through dedicated global slots here.

function vs_lobby_create(_public, _on_done)
{
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { public: true, code: "", on_done: undefined };
    }
    global.vs_lobby_cb.public = _public;
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        vs_online_post_json("/api/v1/lobbies", { public: global.vs_lobby_cb.public }, function(_ok, _data, _status)
        {
            var cb = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (_ok) { vs_lobby_enter(_data); }
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

// Random matchmaking: join a random open public lobby, or create one.
function vs_lobby_matchmake(_on_done)
{
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { public: true, code: "", on_done: undefined };
    }
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        vs_online_post_json("/api/v1/lobbies/matchmake", {}, function(_ok, _data, _status)
        {
            var cb = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (_ok) { vs_lobby_enter(_data); }
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

function vs_lobby_join(_code, _on_done)
{
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { public: true, code: "", on_done: undefined };
    }
    global.vs_lobby_cb.code = _code;
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        vs_online_post_json("/api/v1/lobbies/join", { code: global.vs_lobby_cb.code }, function(_ok, _data, _status)
        {
            var cb = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (_ok) { vs_lobby_enter(_data); }
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

function vs_lobby_leave()
{
    if (instance_exists(o_st_handle) && o_st_handle.lobbyCode != undefined)
    {
        vs_online_post_json("/api/v1/lobbies/" + o_st_handle.lobbyCode + "/leave", {}, function(_ok, _data, _s) { });
    }
    vs_lobby_reset();
}

function vs_lobby_refresh_count()
{
    if (!vs_online_is_account()) return;
    vs_online_get_json("/api/v1/lobbies", false, vs_lobby_count_done);
}

function vs_lobby_count_done(_ok, _data, _status)
{
    var n = 0;
    if (_ok && _data != undefined && variable_struct_exists(_data, "lobbies") && is_array(_data.lobbies))
    {
        n = array_length(_data.lobbies);
    }
    if (instance_exists(obj_multiplayer_lobby))
    {
        obj_multiplayer_lobby.lobbyCount = n;
    }
}

// --- state ----------------------------------------------------------------

// Apply the lobby shape from create/join/matchmake, then open the WS channel.
function vs_lobby_enter(_lobbyJson)
{
    if (instance_exists(o_st_handle))
    {
        o_st_handle.lobbyId = _lobbyJson.lobbyId;
        o_st_handle.lobbyCode = _lobbyJson.code;
        vs_lobby_apply_roster(_lobbyJson.members);
        var you = vs_online_player_id();
        o_st_handle.currentMember = o_st_handle.getMember(you);
        o_st_handle.vs_hostId = _lobbyJson.hostId;
        vs_lobby_refresh_host_flags(_lobbyJson.hostId);
    }
    vs_ws_connect("/api/v1/lobbies/" + string(_lobbyJson.code) + "/ws", vs_online_token());
}

function vs_lobby_reset()
{
    vs_ws_close();
    if (instance_exists(o_st_handle))
    {
        o_st_handle.leaveLobby();
        o_st_handle.vs_hostId = undefined;
    }
}

// --- packet send -----------------------------------------------------------

// Called from the patched send_packet while on the custom server.
function vs_lobby_send_packet(_type, _buffer)
{
    if (vs_lobby_in_lobby())
    {
        vs_ws_send_binary(_buffer);
    }
    else
    {
        show_debug_message("VS Online: dropping packet type " + string(_type) + " (not in a lobby)");
    }
}

// --- WS frame dispatch (called by vs_ws after parsing a frame) -------------

function vs_online_on_ws_frame(_op, _payload)
{
    if (_op == 2) // binary = stamped game packet
    {
        var senderLen = buffer_read(_payload, buffer_u8);
        var senderId = "";
        var i = 0;
        repeat (senderLen)
        {
            senderId += chr(buffer_read(_payload, buffer_u8));
            i++;
        }
        // payload position is now exactly at the packet type byte.
        var got = receive_packet(_payload, senderId);
        // receive_packet only deletes on unknown/empty; we own this buffer.
        if (got != undefined)
        {
            buffer_delete(_payload);
        }
    }
    else if (_op == 1) // text = JSON control message
    {
        var text = "";
        var count = buffer_get_size(_payload);
        var k = 0;
        repeat (count)
        {
            text += chr(buffer_read(_payload, buffer_u8));
            k++;
        }
        buffer_delete(_payload);
        var json = undefined;
        try { json = json_parse(text); } catch (_e) { }
        if (json != undefined)
        {
            vs_lobby_handle_control(json);
        }
    }
    else
    {
        buffer_delete(_payload);
    }
}

// --- WS control messages ---------------------------------------------------

function vs_lobby_handle_control(_j)
{
    var t = variable_struct_exists(_j, "type") ? _j.type : "";
    switch (t)
    {
        case "welcome":
            if (instance_exists(o_st_handle))
            {
                o_st_handle.lobbyId = _j.lobbyId;
                o_st_handle.lobbyCode = _j.code;
                vs_lobby_apply_roster(_j.members);
                var you = variable_struct_exists(_j, "you") ? _j.you : vs_online_player_id();
                if (you == undefined || you == "") { you = vs_online_player_id(); }
                o_st_handle.currentMember = o_st_handle.getMember(you);
                o_st_handle.vs_hostId = _j.hostId;
                vs_lobby_refresh_host_flags(_j.hostId);
                send_packet(SendPlayerInfoPacket); // mirror the Steam "lobby_created/joined" flow
            }
            if (instance_exists(obj_multiplayer_lobby))
            {
                with (obj_multiplayer_lobby) { unmute_bgm(); }
            }
            break;
        case "member_joined":
            if (instance_exists(o_st_handle) && variable_struct_exists(_j, "member"))
            {
                array_push(o_st_handle.lobbyMembers, vs_lobby_build_member(_j.member));
                var i = 0;
                repeat (array_length(o_st_handle.lobbyMembers))
                {
                    o_st_handle.lobbyMembers[i].order = i;
                    i++;
                }
                if (vs_lobby_is_owner())
                {
                    send_packet(SendQueuePacket);
                    send_packet(SendPlayerInfoPacket);
                    if (o_st_handle.currentMember != undefined)
                    {
                        send_packet(UpdateScorePacket,
                        {
                            score_: vs_member_get_score(o_st_handle.currentMember),
                            flag: o_st_handle.currentMember.scoreFlag
                        });
                    }
                }
            }
            break;
        case "member_left":
            if (variable_struct_exists(_j, "playerId")) { vs_lobby_remove_member(_j.playerId); }
            if (variable_struct_exists(_j, "hostId") && instance_exists(o_st_handle))
            {
                o_st_handle.vs_hostId = _j.hostId;
                vs_lobby_refresh_host_flags(_j.hostId);
            }
            break;
        case "host_changed":
            if (instance_exists(o_st_handle))
            {
                o_st_handle.vs_hostId = _j.hostId;
                vs_lobby_refresh_host_flags(_j.hostId);
            }
            break;
        case "kicked":
            vs_lobby_reset();
            show_message("You were kicked from the lobby.\n\n你已被踢出房间。");
            if (instance_exists(obj_multiplayer_lobby))
            {
                with (obj_multiplayer_lobby) { updateButtons(); }
            }
            break;
        case "lobby_closed":
            vs_lobby_reset();
            show_message("The lobby was closed.\n\n房间已关闭。");
            if (instance_exists(obj_multiplayer_lobby))
            {
                with (obj_multiplayer_lobby) { updateButtons(); }
            }
            break;
        case "error":
            show_debug_message("VS Online lobby error: " + string(_j.code) + " - " + string(_j.message));
            break;
    }
}
