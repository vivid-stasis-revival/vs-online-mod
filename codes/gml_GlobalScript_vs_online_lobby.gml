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
    return vs_online_is_custom() && vs_online_player_id() != "";
}

// --- member struct ---------------------------------------------------------

// Deterministic avatar fallback: hash(name) -> a jacket from global.song_list.
function vs_online_avatar_sprite(_name)
{
    if (!variable_global_exists("song_list") || array_length(global.song_list) == 0)
    {
        return undefined;
    }
    var idx = abs(string_hash(_name)) % array_length(global.song_list);
    var song = global.song_list[idx];
    if (song == undefined) return undefined;
    var jk = song_get_info(song, "jacket", 0);
    return (jk == undefined) ? undefined : jk;
}

// Build a game-style member from a server MemberView JSON object.
function vs_lobby_build_member(_mv)
{
    // Server avatar is a URL we don't fetch yet; an empty avatar falls back to
    // a deterministic jacket sprite (Plan: hash(name) -> jacket).
    var hasAvatar = variable_struct_exists(_mv, "avatar") && _mv.avatar != "";
    return
    {
        id: _mv.playerId,
        name: variable_struct_exists(_mv, "name") ? _mv.name : "",
        ready: variable_struct_exists(_mv, "ready") ? _mv.ready : 0,
        score: variable_struct_exists(_mv, "score") ? _mv.score : 0,
        scoreFlag: variable_struct_exists(_mv, "scoreFlag") ? _mv.scoreFlag : 1,
        avatar: hasAvatar ? undefined : vs_online_avatar_sprite(_mv.name),
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

function vs_lobby_create(_public, _on_done)
{
    vs_online_post_json("/api/v1/lobbies", { public: _public }, function(ok, data, status)
    {
        if (ok) { vs_lobby_enter(data); }
        if (_on_done != undefined) { _on_done(ok, data); }
    });
}

// Random matchmaking: join a random open public lobby, or create one.
function vs_lobby_matchmake(_on_done)
{
    vs_online_post_json("/api/v1/lobbies/matchmake", {}, function(ok, data, status)
    {
        if (ok) { vs_lobby_enter(data); }
        if (_on_done != undefined) { _on_done(ok, data); }
    });
}

function vs_lobby_join(_code, _on_done)
{
    vs_online_post_json("/api/v1/lobbies/join", { code: _code }, function(ok, data, status)
    {
        if (ok) { vs_lobby_enter(data); }
        if (_on_done != undefined) { _on_done(ok, data); }
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

// Fetch the list of discoverable (public) lobbies; _on_done(list|undefined).
function vs_lobby_list(_on_done)
{
    vs_online_get_json("/api/v1/lobbies", false, function(ok, data, status)
    {
        _on_done(ok ? data.lobbies : undefined);
    });
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
        receive_packet(_payload, senderId); // receive_packet deletes _payload
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
            }
            break;
        case "member_left":
            if (variable_struct_exists(_j, "playerId")) { vs_lobby_remove_member(_j.playerId); }
            if (variable_struct_exists(_j, "hostId")) { o_st_handle.vs_hostId = _j.hostId; vs_lobby_refresh_host_flags(_j.hostId); }
            break;
        case "host_changed":
            o_st_handle.vs_hostId = _j.hostId;
            vs_lobby_refresh_host_flags(_j.hostId);
            break;
        case "kicked":
        case "lobby_closed":
            vs_lobby_reset();
            break;
        case "error":
            show_debug_message("VS Online lobby error: " + string(_j.code) + " - " + string(_j.message));
            break;
    }
}
