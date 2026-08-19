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

function vs_lobby_send_q_init()
{
    if (!variable_global_exists("vs_lobby_send_q"))
    {
        global.vs_lobby_send_q = [];
    }
}

function vs_lobby_send_q_clear()
{
    vs_lobby_send_q_init();
    var i = 0;
    repeat (array_length(global.vs_lobby_send_q))
    {
        var item = global.vs_lobby_send_q[i];
        if (item != undefined && variable_struct_exists(item, "buf") && item.buf != undefined)
        {
            buffer_delete(item.buf);
        }
        i++;
    }
    global.vs_lobby_send_q = [];
}

function vs_lobby_send_q_flush()
{
    vs_lobby_send_q_init();
    if (!vs_ws_is_open()) return;
    var n = array_length(global.vs_lobby_send_q);
    if (n <= 0) return;
    vs_lobby_log("flush queued n=" + string(n));
    var i = 0;
    repeat (n)
    {
        var item = global.vs_lobby_send_q[i];
        if (item != undefined && variable_struct_exists(item, "buf") && item.buf != undefined)
        {
            if (!vs_lobby_pkt_quiet(item.type))
            {
                vs_lobby_log("flush " + vs_lobby_pkt_name(item.type) + " bytes=" + string(buffer_get_size(item.buf)));
            }
            vs_ws_send_binary(item.buf);
            buffer_delete(item.buf);
        }
        i++;
    }
    global.vs_lobby_send_q = [];
}

function vs_lobby_has_code()
{
    return instance_exists(o_st_handle)
        && o_st_handle.lobbyCode != undefined
        && string(o_st_handle.lobbyCode) != "";
}

function vs_online_song_id_from_chart(_chart)
{
    if (_chart == undefined || _chart == "") return -1;
    if (!variable_global_exists("song_list")) return -1;
    var i = 0;
    repeat (array_length(global.song_list))
    {
        var s = global.song_list[i];
        if (s != undefined && variable_struct_exists(s, "chart_id") && s.chart_id == _chart)
        {
            return i;
        }
        i++;
    }
    return -1;
}

function vs_online_song_from_id(_songId)
{
    if (!variable_global_exists("song_list")) return undefined;
    if (!is_real(_songId) || _songId < 0 || _songId >= array_length(global.song_list))
    {
        return undefined;
    }
    return global.song_list[_songId];
}

function vs_online_missing_song()
{
    return { name: "Missing chart", chart_id: "", is_missing: true };
}

function vs_online_chart_id_of_song(_songId)
{
    var s = vs_online_song_from_id(_songId);
    if (s == undefined || !variable_struct_exists(s, "chart_id") || s.chart_id == undefined)
    {
        return "";
    }
    return string(s.chart_id);
}

// --- steam_* shims (used via codepatches so the WP UI reads server state) ---

function vs_lobby_lobby_id()
{
    if (vs_online_is_custom())
    {
        if (!instance_exists(o_st_handle) || o_st_handle.lobbyId == undefined) return 0;
        return vs_http_num(o_st_handle.lobbyId, 0);
    }
    return steam_lobby_get_lobby_id();
}

function vs_lobby_get_host_id()
{
    if (!instance_exists(o_st_handle)) return "";
    if (!variable_instance_exists(o_st_handle, "vs_hostId")) return "";
    if (o_st_handle.vs_hostId == undefined) return "";
    return string(o_st_handle.vs_hostId);
}

function vs_lobby_sender_ok(_id)
{
    var s = string(_id);
    var n = string_length(s);
    if (n < 8 || n > 64) return false;
    if (string_pos("\"", s) > 0 || string_pos("{", s) > 0 || string_pos(":", s) > 0) return false;
    return true;
}

function vs_lobby_suggest_q()
{
    if (!instance_exists(o_st_handle)) return [];
    if (!variable_instance_exists(o_st_handle, "suggestQueue") || !is_array(o_st_handle.suggestQueue))
    {
        o_st_handle.suggestQueue = [];
    }
    return o_st_handle.suggestQueue;
}

function vs_lobby_is_owner()
{
    if (vs_online_is_custom())
    {
        var hid = vs_lobby_get_host_id();
        return hid != "" && vs_online_player_id() == hid;
    }
    return steam_lobby_is_owner();
}

function vs_lobby_owner_id()
{
    if (vs_online_is_custom())
    {
        return vs_lobby_get_host_id();
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

function vs_member_get_flag(_m)
{
    if (_m == undefined) return 1;
    if (variable_struct_exists(_m, "scoreFlag")) return variable_struct_get(_m, "scoreFlag");
    return 1;
}

function vs_member_set_flag(_m, _v)
{
    if (_m == undefined) return;
    variable_struct_set(_m, "scoreFlag", _v);
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
        global.vs_avatar_got = 0;
        global.vs_avatar_total = 0;
        global.vs_avatar_dest = "";
        global.vs_avatar_pending = {};
        global.vs_avatar_fail = {};
    }
    return global.vs_avatar_spr;
}

function vs_online_avatar_rel(_playerId)
{
    return "vs_avatars/" + string(_playerId) + ".png";
}

function vs_online_avatar_file(_playerId)
{
    var rel = vs_online_avatar_rel(_playerId);
    if (file_exists(rel)) return rel;
    var abs = vs_songstore_install_path(rel);
    if (file_exists(abs)) return abs;
    return "";
}

function vs_online_avatar_load_file(_playerId)
{
    var p = vs_online_avatar_file(_playerId);
    if (p == "") return undefined;
    var spr = sprite_add(p, 1, false, false, 0, 0);
    if (spr == -1 || !sprite_exists(spr)) return undefined;
    variable_struct_set(vs_online_avatar_cache(), _playerId, spr);
    return spr;
}

function vs_online_avatar_abs_url(_url)
{
    return vs_songstore_abs_url(_url);
}

function vs_online_my_avatar()
{
    var cfg = vs_online_get_config();
    var name = (variable_struct_exists(cfg, "name") && cfg.name != "") ? cfg.name : "Player";
    var av = vs_online_avatar_sprite(name);
    var pid = (variable_struct_exists(cfg, "playerId")) ? cfg.playerId : "";
    var url = (variable_struct_exists(cfg, "avatar")) ? cfg.avatar : "";
    if ((url == undefined || url == "") && pid != "")
        url = vs_online_server_url() + "/avatars/" + pid + ".png";
    if (url != "" && pid != "")
    {
        var fetched = vs_online_avatar_ensure(pid, vs_online_avatar_abs_url(url));
        if (fetched != undefined) av = fetched;
    }
    return av;
}

function vs_online_avatar_ensure(_playerId, _url)
{
    if (_playerId == undefined || _playerId == "" || _url == undefined || _url == "") return undefined;
    var cache = vs_online_avatar_cache();
    if (variable_struct_exists(cache, _playerId))
        return variable_struct_get(cache, _playerId);
    var loaded = vs_online_avatar_load_file(_playerId);
    if (loaded != undefined) return loaded;
    if (variable_struct_exists(global.vs_avatar_fail, _playerId)
        && variable_struct_get(global.vs_avatar_fail, _playerId) == true)
        return undefined;
    if (variable_struct_exists(global.vs_avatar_pending, _playerId)
        && variable_struct_get(global.vs_avatar_pending, _playerId) == true)
        return undefined;
    variable_struct_set(global.vs_avatar_pending, _playerId, true);
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
    global.vs_avatar_got = 0;
    global.vs_avatar_total = 0;
    if (!directory_exists("vs_avatars")) directory_create("vs_avatars");
    var dest = vs_online_avatar_rel(job.id);
    global.vs_avatar_dest = dest;
    global.vs_avatar_req = http_get_file(job.url, dest);
    if (global.vs_avatar_req == undefined || global.vs_avatar_req < 0)
    {
        show_debug_message("VS Online: avatar http_get_file failed " + string(job.url));
        vs_online_avatar_finish(false);
    }
}

// Same HTTP event as jackets/previews: wait until the file is actually on
// disk. The old coroutine handler treated the first progress packet (status=1)
// as failure, so settings always kept the hash-jacket fallback.
function vs_online_avatar_on_http()
{
    vs_online_avatar_cache();
    if (!global.vs_avatar_busy || global.vs_avatar_req < 0) return;
    if (async_load == -1) return;
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || string(rid) != string(global.vs_avatar_req)) return;
    var gmStatus = vs_http_num(ds_map_find_value(async_load, "status"), -1);
    var got = vs_http_num(ds_map_find_value(async_load, "sizeDownloaded"), -1);
    var tot = vs_http_num(ds_map_find_value(async_load, "contentLength"), -1);
    if (got >= 0) global.vs_avatar_got = got;
    if (tot >= 0) global.vs_avatar_total = tot;
    var doneProg = (global.vs_avatar_total > 0 && global.vs_avatar_got >= global.vs_avatar_total);
    if (gmStatus == 1 && !doneProg) return;
    var httpStatus = vs_http_num(ds_map_find_value(async_load, "http_status"), -1);
    var httpOk = (httpStatus < 0 || (httpStatus >= 200 && httpStatus < 300));
    var dest = global.vs_avatar_dest;
    var here = (dest != "" && (file_exists(dest) || file_exists(vs_songstore_install_path(dest))));
    var ok = httpOk && ((gmStatus >= 0) || doneProg || here);
    show_debug_message("VS Online: avatar done pid=" + string(global.vs_avatar_cur)
        + " ok=" + string(ok) + " http=" + string(httpStatus) + " st=" + string(gmStatus));
    vs_online_avatar_finish(ok);
}

function vs_online_avatar_finish(_ok)
{
    var pid = global.vs_avatar_cur;
    if (_ok)
    {
        var spr = vs_online_avatar_load_file(pid);
        if (spr != undefined)
        {
            if (instance_exists(o_st_handle))
            {
                var m = o_st_handle.getMember(pid);
                if (m != undefined) m.avatar = spr;
            }
        }
        else _ok = false;
    }
    if (pid != "")
    {
        variable_struct_set(global.vs_avatar_pending, pid, false);
        if (!_ok) variable_struct_set(global.vs_avatar_fail, pid, true);
    }
    global.vs_avatar_busy = false;
    global.vs_avatar_cur = "";
    global.vs_avatar_req = -1;
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
        var fetched = vs_online_avatar_ensure(_mv.playerId, vs_online_avatar_abs_url(_mv.avatar));
        if (fetched != undefined) av = fetched;
    }
    var m =
    {
        id: variable_struct_exists(_mv, "playerId") ? string(_mv.playerId) : "",
        name: variable_struct_exists(_mv, "name") ? _mv.name : "",
        ready: variable_struct_exists(_mv, "ready") ? _mv.ready : 0,
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
        connected: variable_struct_exists(_mv, "connected") ? vs_lobby_json_true(_mv.connected) : false,
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
    var fl = 1;
    if (variable_struct_exists(_mv, "scoreFlag")) fl = variable_struct_get(_mv, "scoreFlag");
    vs_member_set_flag(m, fl);
    return m;
}

function vs_lobby_apply_roster(_members)
{
    if (!instance_exists(o_st_handle)) return;
    var prevById = {};
    var pidx = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var pm = o_st_handle.lobbyMembers[pidx];
        if (pm != undefined)
        {
            variable_struct_set(prevById, string(pm.id), pm);
        }
        pidx++;
    }
    var arr = [];
    var i = 0;
    repeat (array_length(_members))
    {
        var src = _members[i];
        var m = vs_lobby_build_member(src);
        var pid = string(m.id);
        if (variable_struct_exists(prevById, pid) && vs_member_get_score(m) == 0)
        {
            var old = variable_struct_get(prevById, pid);
            var oldSc = vs_member_get_score(old);
            if (oldSc != 0)
            {
                vs_member_set_score(m, oldSc);
                if (variable_struct_exists(old, "scoreFlag")) vs_member_set_flag(m, vs_member_get_flag(old));
            }
        }
        arr[i] = m;
        i++;
    }
    o_st_handle.lobbyMembers = arr;
}

function vs_lobby_touch_member(_mv)
{
    if (!instance_exists(o_st_handle) || _mv == undefined) return;
    if (!variable_struct_exists(_mv, "playerId")) return;
    var pid = string(_mv.playerId);
    if (pid == "" || pid == "?") return;
    var ex = o_st_handle.getMember(pid);
    if (ex == undefined)
    {
        array_push(o_st_handle.lobbyMembers, vs_lobby_build_member(_mv));
        var j = 0;
        repeat (array_length(o_st_handle.lobbyMembers))
        {
            o_st_handle.lobbyMembers[j].order = j;
            j++;
        }
        return;
    }
    if (variable_struct_exists(_mv, "name") && string(_mv.name) != "") ex.name = _mv.name;
    if (variable_struct_exists(_mv, "ready")) ex.ready = _mv.ready;
    if (variable_struct_exists(_mv, "host")) ex.host = _mv.host;
    if (variable_struct_exists(_mv, "rate")) ex.rate = _mv.rate;
    if (variable_struct_exists(_mv, "class")) ex.class = _mv.class;
    if (variable_struct_exists(_mv, "score"))
    {
        var sc = variable_struct_get(_mv, "score");
        if (sc != 0) vs_member_set_score(ex, sc);
    }
    if (variable_struct_exists(_mv, "scoreFlag")) vs_member_set_flag(ex, variable_struct_get(_mv, "scoreFlag"));
    if (variable_struct_exists(_mv, "connected")) ex.connected = vs_lobby_json_true(_mv.connected);
}

function vs_lobby_json_true(_v)
{
    if (_v == undefined) return false;
    if (_v == true) return true;
    if (is_real(_v) && _v != 0) return true;
    if (is_string(_v) && (_v == "true" || _v == "1")) return true;
    return false;
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

// --- logging (same convention as VS PLAY / VS SCORE: console + vsonline.dl.log)

function vs_lobby_log(_msg)
{
    var line = "VS MP: " + string(_msg);
    show_debug_message(line);
    vs_songstore_log("MP " + string(_msg));
}

function vs_lobby_refresh_ui()
{
    if (instance_exists(vs_online_error))
    {
        with (vs_online_error) instance_destroy();
    }
    if (instance_exists(obj_multiplayer_lobby))
    {
        with (obj_multiplayer_lobby)
        {
            updateButtons();
            unmute_bgm();
        }
    }
}

function vs_lobby_rest_leave(_code)
{
    if (_code == undefined || string(_code) == "") return;
    vs_lobby_log("REST leave extra code=" + string(_code));
    vs_online_post_json("/api/v1/lobbies/" + string(_code) + "/leave", {}, function(_ok, _data, _s)
    {
        vs_lobby_log("leave extra " + vs_lobby_http_why(_ok, _data, _s));
    });
}

// Do not name this global the same as a function — GM puts scripts in the
// global namespace, so `global.vs_lobby_create_busy` was the function itself
// (always truthy) and every Host click skipped the POST.
function vs_lobby_is_create_pending()
{
    return variable_global_exists("vs_lobby_create_pending") && global.vs_lobby_create_pending == true;
}

function vs_lobby_set_create_pending(_on)
{
    global.vs_lobby_create_pending = (_on == true);
}

function vs_lobby_norm_code(_code)
{
    var s = string_upper(string(_code));
    var out = "";
    var i = 1;
    repeat (string_length(s))
    {
        var ch = string_char_at(s, i);
        var ordv = ord(ch);
        var ok = (ordv >= 48 && ordv <= 57) || (ordv >= 65 && ordv <= 90);
        if (ok) out += ch;
        i++;
    }
    if (string_length(out) > 6) out = string_copy(out, 1, 6);
    return out;
}

function vs_lobby_flags()
{
    var n = 0;
    var code = "";
    var host = "";
    if (instance_exists(o_st_handle))
    {
        if (o_st_handle.lobbyMembers != undefined) n = array_length(o_st_handle.lobbyMembers);
        if (o_st_handle.lobbyCode != undefined) code = string(o_st_handle.lobbyCode);
        host = string(vs_lobby_get_host_id());
    }
    return "custom=" + string(vs_online_is_custom())
        + " account=" + string(vs_online_is_account())
        + " conn=" + string(vs_online_conn_state())
        + " ws=" + string(vs_ws_state().state)
        + " in=" + string(vs_lobby_in_lobby())
        + " pend=" + string(vs_lobby_is_create_pending())
        + " code=" + code
        + " host=" + host
        + " members=" + string(n)
        + " me=" + vs_online_player_id();
}

function vs_lobby_fmt(_data)
{
    if (_data == undefined) return "data=?";
    if (is_string(_data)) return "msg=" + _data;
    if (!is_struct(_data)) return "data=" + string(_data);
    var code = variable_struct_exists(_data, "code") ? string(_data.code) : "?";
    var lid = variable_struct_exists(_data, "lobbyId") ? string(_data.lobbyId) : "?";
    var host = variable_struct_exists(_data, "hostId") ? string(_data.hostId) : "?";
    var n = 0;
    if (variable_struct_exists(_data, "members") && is_array(_data.members)) n = array_length(_data.members);
    var why = "";
    if (variable_struct_exists(_data, "type")) why += " type=" + string(_data.type);
    if (variable_struct_exists(_data, "reason")) why += " reason=" + string(_data.reason);
    if (variable_struct_exists(_data, "message")) why += " err=" + string(_data.message);
    if (variable_struct_exists(_data, "error")) why += " error=" + string(_data.error);
    if (variable_struct_exists(_data, "created")) why += " created=" + string(_data.created);
    return "lobbyId=" + lid + " code=" + code + " host=" + host + " members=" + string(n) + why;
}

function vs_lobby_pkt_name(_type)
{
    if (_type == 4 || _type == AddSongPacket) return "AddSong";
    if (_type == 6 || _type == SendQueuePacket) return "SendQueue";
    if (_type == 10 || _type == StartCountdownPacket) return "StartCountdown";
    if (_type == 11 || _type == StartGamePacket) return "StartGame";
    if (_type == 12 || _type == SendReadyPacket) return "SendReady";
    if (_type == 20 || _type == ReportScorePacket) return "ReportScore";
    if (_type == 22 || _type == UpdateScorePacket) return "UpdateScore";
    if (_type == 30 || _type == ShowScorePacket) return "ShowScore";
    if (_type == 40 || _type == ShadowSongPacket) return "ShadowSong";
    if (_type == 60 || _type == SendPlayerInfoPacket) return "SendPlayerInfo";
    if (_type == 61 || _type == SendStickerPacket) return "SendSticker";
    if (_type == 101 || _type == SuggestSongPacket) return "SuggestSong";
    return string(_type);
}

function vs_lobby_pkt_quiet(_type)
{
    var n = vs_lobby_pkt_name(_type);
    return (n == "UpdateScore" || n == "SendSticker");
}

// Host copies queue / player info / score to everyone who is Connected.
// REST / matchmake member_joined is too early (guest WS is still down). The
// server notifies again on WS attach with connected:true; SendPlayerInfo from
// the joiner is a third fallback.
function vs_lobby_host_sync(_why)
{
    if (!vs_lobby_is_owner()) return;
    if (!instance_exists(o_st_handle)) return;
    vs_lobby_log("host sync " + string(_why) + " queue/info/score");
    send_packet(SendQueuePacket);
    send_packet(SendPlayerInfoPacket);
    if (o_st_handle.currentMember != undefined)
    {
        send_packet(UpdateScorePacket,
        {
            score_: vs_member_get_score(o_st_handle.currentMember),
            flag: vs_member_get_flag(o_st_handle.currentMember)
        });
    }
    else
    {
        vs_lobby_log("host sync skip score no currentMember");
    }
}

// Matchmake into an existing room now emits member_joined (same as join).
// A packet from an unknown sender still gets a stub so official receive()
// does not crash; GET /members then fills name/avatar/host from the server roster.
function vs_lobby_ensure_sender(_senderId)
{
    if (!instance_exists(o_st_handle)) return false;
    if (_senderId == undefined || string(_senderId) == "") return false;
    if (o_st_handle.getMember(_senderId) != undefined) return false;
    vs_lobby_log("ensure sender stub id=" + string(_senderId));
    array_push(o_st_handle.lobbyMembers, vs_lobby_build_member({
        playerId: _senderId,
        name: "",
        ready: 0,
        host: false,
        order: array_length(o_st_handle.lobbyMembers)
    }));
    vs_lobby_fetch_members("unknown sender");
    if (vs_lobby_is_owner())
    {
        vs_lobby_host_sync("ensure sender");
    }
    return true;
}

function vs_lobby_fetch_members(_why)
{
    if (!instance_exists(o_st_handle) || o_st_handle.lobbyCode == undefined) return;
    var code = string(o_st_handle.lobbyCode);
    if (code == "") return;
    vs_lobby_log("GET /members " + string(_why) + " code=" + code);
    vs_online_get_json("/api/v1/lobbies/" + code + "/members", true, vs_lobby_fetch_members_done);
}

function vs_lobby_fetch_members_done(_ok, _data, _status)
{
    vs_lobby_log("GET /members result " + vs_lobby_http_why(_ok, _data, _status));
    if (!_ok || _data == undefined || !variable_struct_exists(_data, "members")) return;
    if (!is_array(_data.members)) return;
    if (!instance_exists(o_st_handle)) return;
    vs_lobby_apply_roster(_data.members);
    o_st_handle.currentMember = o_st_handle.getMember(vs_online_player_id());
    var hid = vs_lobby_get_host_id();
    if (hid != "")
    {
        vs_lobby_refresh_host_flags(hid);
    }
    vs_lobby_refresh_ui();
}

function vs_lobby_http_why(_ok, _data, _status)
{
    return "ok=" + string(_ok) + " http=" + string(_status) + " " + vs_lobby_fmt(_data);
}

// --- REST entry points -----------------------------------------------------
//
// COMPILER NOTE: anonymous functions in loader-injected scripts cannot capture
// enclosing arguments/`var` locals (they compile to `self.<name>` reads and
// crash). Cross-callback state travels through dedicated global slots here.

function vs_lobby_create(_public, _on_done)
{
    vs_lobby_log("create start public=" + string(_public) + " " + vs_lobby_flags());
    if (!vs_online_is_account())
    {
        vs_lobby_log("create skip guest");
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    if (vs_lobby_has_code())
    {
        vs_lobby_log("create skip already code=" + string(o_st_handle.lobbyCode));
        vs_lobby_refresh_ui();
        if (_on_done != undefined) { _on_done(true, undefined); }
        return;
    }
    if (vs_lobby_is_create_pending())
    {
        vs_lobby_log("create skip pending " + vs_lobby_flags());
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { is_public: true, code: "", on_done: undefined };
    }
    global.vs_lobby_cb.is_public = _public;
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        if (vs_lobby_has_code())
        {
            vs_lobby_log("create POST skip already code=" + string(o_st_handle.lobbyCode));
            var already = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (already != undefined) { already(true, undefined); }
            return;
        }
        if (vs_lobby_is_create_pending())
        {
            vs_lobby_log("create POST skip pending");
            return;
        }
        vs_lobby_set_create_pending(true);
        vs_lobby_log("create POST /lobbies public=" + string(global.vs_lobby_cb.is_public));
        var body = "{\"public\":" + (global.vs_lobby_cb.is_public ? "true" : "false") + "}";
        vs_online_post_raw("/api/v1/lobbies", body, function(_ok, _data, _status)
        {
            vs_lobby_set_create_pending(false);
            vs_lobby_log("create result " + vs_lobby_http_why(_ok, _data, _status));
            var cb = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (_ok)
            {
                var got = (_data != undefined && variable_struct_exists(_data, "code")) ? string(_data.code) : "";
                if (vs_lobby_has_code())
                {
                    var have = string(o_st_handle.lobbyCode);
                    if (got != "" && got != have)
                    {
                        vs_lobby_log("create extra leave " + got + " keep " + have);
                        vs_lobby_rest_leave(got);
                    }
                    else
                    {
                        vs_lobby_enter(_data);
                    }
                }
                else
                {
                    vs_lobby_enter(_data);
                }
            }
            else { vs_lobby_log("create fail no enter"); }
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

// Random matchmaking: join a random open public lobby, or create one.
function vs_lobby_matchmake(_on_done)
{
    vs_lobby_log("matchmake start " + vs_lobby_flags());
    if (!vs_online_is_account())
    {
        vs_lobby_log("matchmake skip guest");
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { is_public: true, code: "", on_done: undefined };
    }
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        vs_lobby_log("matchmake POST /lobbies/matchmake");
        vs_online_post_json("/api/v1/lobbies/matchmake", {}, function(_ok, _data, _status)
        {
            vs_lobby_log("matchmake result " + vs_lobby_http_why(_ok, _data, _status));
            var cb = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (_ok) { vs_lobby_enter(_data); }
            else { vs_lobby_log("matchmake fail no enter"); }
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

function vs_lobby_join(_code, _on_done)
{
    var code = vs_lobby_norm_code(_code);
    vs_lobby_log("join start code=" + code + " raw=" + string(_code) + " " + vs_lobby_flags());
    if (code == undefined || string_length(code) != 6)
    {
        vs_lobby_log("join bad code raw=" + string(_code));
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    if (!vs_online_is_account())
    {
        vs_lobby_log("join skip guest");
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { is_public: true, code: "", on_done: undefined };
    }
    global.vs_lobby_cb.code = code;
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        vs_lobby_log("join POST /lobbies/join code=" + string(global.vs_lobby_cb.code));
        vs_online_post_json("/api/v1/lobbies/join", { code: global.vs_lobby_cb.code }, function(_ok, _data, _status)
        {
            vs_lobby_log("join result " + vs_lobby_http_why(_ok, _data, _status));
            var cb = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (_ok) { vs_lobby_enter(_data); }
            else { vs_lobby_log("join fail no enter"); }
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

function vs_lobby_leave()
{
    var code = "";
    if (instance_exists(o_st_handle) && o_st_handle.lobbyCode != undefined)
    {
        code = string(o_st_handle.lobbyCode);
    }
    vs_lobby_log("leave start code=" + code + " " + vs_lobby_flags());
    if (code != "")
    {
        vs_online_post_json("/api/v1/lobbies/" + code + "/leave", {}, function(_ok, _data, _s)
        {
            vs_lobby_log("leave result " + vs_lobby_http_why(_ok, _data, _s));
        });
    }
    else
    {
        vs_lobby_log("leave skip no code");
    }
    vs_lobby_reset();
}

function vs_lobby_refresh_count()
{
    if (!vs_online_is_account())
    {
        vs_lobby_log("count skip guest");
        return;
    }
    vs_lobby_log("count GET /lobbies");
    vs_online_get_json("/api/v1/lobbies", false, vs_lobby_count_done);
}

function vs_lobby_count_done(_ok, _data, _status)
{
    var n = 0;
    if (_ok && _data != undefined && variable_struct_exists(_data, "lobbies") && is_array(_data.lobbies))
    {
        n = array_length(_data.lobbies);
    }
    vs_lobby_log("count result ok=" + string(_ok) + " http=" + string(_status) + " n=" + string(n));
    if (instance_exists(obj_multiplayer_lobby))
    {
        obj_multiplayer_lobby.lobbyCount = n;
    }
    else
    {
        vs_lobby_log("count skip no lobby ui");
    }
}

// --- state ----------------------------------------------------------------

// Apply the lobby shape from create/join/matchmake, then open the WS channel.
function vs_lobby_enter(_lobbyJson)
{
    if (_lobbyJson == undefined)
    {
        vs_lobby_log("enter skip no data " + vs_lobby_flags());
        return;
    }
    vs_lobby_log("enter " + vs_lobby_fmt(_lobbyJson) + " " + vs_lobby_flags());
    var newCode = variable_struct_exists(_lobbyJson, "code") ? string(_lobbyJson.code) : "";
    if (vs_lobby_has_code())
    {
        var old = string(o_st_handle.lobbyCode);
        if (old != "" && newCode != "" && old != newCode)
        {
            vs_lobby_log("enter replace " + old + " -> " + newCode);
            vs_lobby_rest_leave(old);
            vs_lobby_send_q_clear();
            vs_ws_close();
        }
        else if (old != "" && old == newCode && (vs_ws_is_open() || vs_ws_state().state == 1))
        {
            vs_lobby_log("enter already " + old + " ws=" + string(vs_ws_state().state));
            if (instance_exists(o_st_handle))
            {
                o_st_handle.lobbyId = _lobbyJson.lobbyId;
                o_st_handle.lobbyCode = _lobbyJson.code;
                vs_lobby_apply_roster(_lobbyJson.members);
                var you0 = vs_online_player_id();
                o_st_handle.currentMember = o_st_handle.getMember(you0);
                o_st_handle.vs_hostId = _lobbyJson.hostId;
                vs_lobby_refresh_host_flags(_lobbyJson.hostId);
            }
            vs_lobby_refresh_ui();
            return;
        }
    }
    if (instance_exists(o_st_handle))
    {
        o_st_handle.lobbyId = _lobbyJson.lobbyId;
        o_st_handle.lobbyCode = _lobbyJson.code;
        vs_lobby_apply_roster(_lobbyJson.members);
        var you = vs_online_player_id();
        o_st_handle.currentMember = o_st_handle.getMember(you);
        o_st_handle.vs_hostId = _lobbyJson.hostId;
        vs_lobby_refresh_host_flags(_lobbyJson.hostId);
        vs_lobby_log("enter applied you=" + string(you)
            + " current=" + string(o_st_handle.currentMember != undefined)
            + " owner=" + string(vs_lobby_is_owner()));
    }
    else
    {
        vs_lobby_log("enter no o_st_handle");
    }
    vs_lobby_refresh_ui();
    vs_ws_connect("/api/v1/lobbies/" + string(_lobbyJson.code) + "/ws", vs_online_token());
}

function vs_lobby_reset()
{
    vs_lobby_log("reset " + vs_lobby_flags());
    vs_lobby_set_create_pending(false);
    vs_lobby_send_q_clear();
    vs_ws_close();
    if (instance_exists(o_st_handle))
    {
        o_st_handle.leaveLobby();
        o_st_handle.vs_hostId = undefined;
    }
    else
    {
        vs_lobby_log("reset no o_st_handle");
    }
}

// --- packet send -----------------------------------------------------------

// Called from the patched send_packet while on the custom server.
function vs_lobby_apply_local(_type, _buffer)
{
    // SendQueue.read replaces lobbyMembers from packet ids. A local echo after
    // member_joined can drop the joiner if UUID string/u64 decoding misses.
    if (_type == 6 || _type == SendQueuePacket) return;
    var sz = buffer_get_size(_buffer);
    if (sz <= 0) return;
    if (!vs_lobby_pkt_quiet(_type))
    {
        vs_lobby_log("apply local " + vs_lobby_pkt_name(_type) + " bytes=" + string(sz));
    }
    var copy = buffer_create(sz, buffer_fixed, 1);
    buffer_copy(_buffer, 0, sz, copy, 0);
    buffer_seek(copy, buffer_seek_start, 0);
    receive_packet(copy, vs_online_player_id());
}

function vs_lobby_send_packet(_type, _buffer)
{
    var name = vs_lobby_pkt_name(_type);
    if (vs_ws_is_open())
    {
        if (!vs_lobby_pkt_quiet(_type))
        {
            vs_lobby_log("send " + name + " bytes=" + string(buffer_get_size(_buffer)));
        }
        vs_ws_send_binary(_buffer);
        vs_lobby_apply_local(_type, _buffer);
        return;
    }
    var entering = (vs_ws_state().state == 1) || vs_lobby_has_code();
    if (entering)
    {
        vs_lobby_send_q_init();
        if (array_length(global.vs_lobby_send_q) >= 64)
        {
            vs_lobby_log("drop " + name + " (send queue full) " + vs_lobby_flags());
            return;
        }
        var sz = buffer_get_size(_buffer);
        var copy = buffer_create(max(sz, 1), buffer_fixed, 1);
        if (sz > 0)
        {
            buffer_copy(_buffer, 0, sz, copy, 0);
        }
        array_push(global.vs_lobby_send_q, { type: _type, buf: copy });
        vs_lobby_log("queue " + name + " bytes=" + string(sz)
            + " n=" + string(array_length(global.vs_lobby_send_q))
            + " " + vs_lobby_flags());
        vs_lobby_apply_local(_type, _buffer);
        return;
    }
    vs_lobby_log("drop " + name + " (not in a lobby) " + vs_lobby_flags());
}

// --- WS frame dispatch (called by vs_ws after parsing a frame) -------------

function vs_online_on_ws_frame(_op, _payload)
{
    if (_op == 2) // binary = stamped game packet
    {
        var senderLen = buffer_read(_payload, buffer_u8);
        var remain = buffer_get_size(_payload) - buffer_tell(_payload);
        if (senderLen < 0 || senderLen > remain)
        {
            vs_lobby_log("recv binary drop bad senderLen=" + string(senderLen) + " remain=" + string(remain));
            buffer_delete(_payload);
            return;
        }
        var senderId = "";
        var i = 0;
        repeat (senderLen)
        {
            senderId += chr(buffer_read(_payload, buffer_u8));
            i++;
        }
        if (!vs_lobby_sender_ok(senderId))
        {
            vs_lobby_log("recv binary drop bad sender=" + string_copy(senderId, 1, 80));
            buffer_delete(_payload);
            return;
        }
        var pkt = -1;
        if (buffer_get_size(_payload) > buffer_tell(_payload))
        {
            pkt = buffer_peek(_payload, buffer_tell(_payload), buffer_u8);
        }
        if (!vs_lobby_pkt_quiet(pkt))
        {
            vs_lobby_log("recv binary from=" + senderId
                + " type=" + vs_lobby_pkt_name(pkt)
                + " bytes=" + string(buffer_get_size(_payload)));
        }
        vs_lobby_ensure_sender(senderId);
        // payload position is now exactly at the packet type byte.
        var got = receive_packet(_payload, senderId);
        // packet.read already deletes the buffer on a known type.
        if (got == undefined && !vs_lobby_pkt_quiet(pkt))
        {
            vs_lobby_log("recv unhandled from=" + senderId + " type=" + vs_lobby_pkt_name(pkt));
        }
        if ((pkt == 60 || pkt == SendPlayerInfoPacket)
            && vs_lobby_is_owner()
            && senderId != vs_online_player_id())
        {
            vs_lobby_host_sync("recv SendPlayerInfo from=" + senderId);
            vs_lobby_refresh_ui();
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
        try { json = json_parse(text); }
        catch (_e) { vs_lobby_log("ctrl json fail " + string(_e) + " text=" + string_copy(text, 1, 120)); }
        if (json != undefined)
        {
            vs_lobby_handle_control(json);
        }
        else
        {
            vs_lobby_log("ctrl parse empty text=" + string_copy(text, 1, 120));
        }
    }
    else
    {
        vs_lobby_log("ws frame drop op=" + string(_op) + " bytes=" + string(buffer_get_size(_payload)));
        buffer_delete(_payload);
    }
}

// --- WS control messages ---------------------------------------------------

function vs_lobby_handle_control(_j)
{
    var t = variable_struct_exists(_j, "type") ? _j.type : "";
    vs_lobby_log("ctrl " + string(t) + " " + vs_lobby_fmt(_j));
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
                vs_lobby_log("welcome you=" + string(you)
                    + " current=" + string(o_st_handle.currentMember != undefined)
                    + " owner=" + string(vs_lobby_is_owner())
                    + " members=" + string(array_length(o_st_handle.lobbyMembers)));
                send_packet(SendPlayerInfoPacket); // mirror the Steam "lobby_created/joined" flow
            }
            else
            {
                vs_lobby_log("welcome skip no o_st_handle");
            }
            vs_lobby_refresh_ui();
            break;
        case "member_joined":
            if (instance_exists(o_st_handle) && variable_struct_exists(_j, "member"))
            {
                var mid = variable_struct_exists(_j.member, "playerId") ? string(_j.member.playerId) : "?";
                var mname = variable_struct_exists(_j.member, "name") ? string(_j.member.name) : "";
                vs_lobby_touch_member(_j.member);
                var connected = variable_struct_exists(_j.member, "connected")
                    && vs_lobby_json_true(_j.member.connected);
                vs_lobby_log("member_joined id=" + mid + " name=" + mname
                    + " n=" + string(array_length(o_st_handle.lobbyMembers))
                    + " connected=" + string(connected)
                    + " owner=" + string(vs_lobby_is_owner()));
                // REST join fires while the guest socket is still down. Wait for
                // the WS-attach notify (connected:true) before SendQueue.
                if (connected && mid != vs_online_player_id())
                {
                    vs_lobby_host_sync("member_joined");
                }
                else
                {
                    vs_lobby_log("member_joined skip sync connected=" + string(connected));
                }
                vs_lobby_refresh_ui();
            }
            else
            {
                vs_lobby_log("member_joined skip no handle/member");
            }
            break;
        case "member_left":
            var leftId = variable_struct_exists(_j, "playerId") ? string(_j.playerId) : "";
            if (leftId != "") { vs_lobby_remove_member(leftId); }
            if (variable_struct_exists(_j, "hostId") && instance_exists(o_st_handle))
            {
                o_st_handle.vs_hostId = _j.hostId;
                vs_lobby_refresh_host_flags(_j.hostId);
            }
            vs_lobby_log("member_left id=" + leftId
                + " host=" + (variable_struct_exists(_j, "hostId") ? string(_j.hostId) : "")
                + " " + vs_lobby_flags());
            vs_lobby_refresh_ui();
            break;
        case "host_changed":
            if (instance_exists(o_st_handle))
            {
                o_st_handle.vs_hostId = _j.hostId;
                vs_lobby_refresh_host_flags(_j.hostId);
                vs_lobby_log("host_changed host=" + string(_j.hostId) + " owner=" + string(vs_lobby_is_owner()));
            }
            else
            {
                vs_lobby_log("host_changed skip no o_st_handle host=" + string(_j.hostId));
            }
            break;
        case "kicked":
            vs_lobby_log("kicked reason=" + (variable_struct_exists(_j, "reason") ? string(_j.reason) : "")
                + " " + vs_lobby_flags());
            vs_lobby_reset();
            show_message("You were kicked from the lobby.\n\n你已被踢出房间。");
            if (instance_exists(obj_multiplayer_lobby))
            {
                with (obj_multiplayer_lobby) { updateButtons(); }
            }
            break;
        case "lobby_closed":
            vs_lobby_log("lobby_closed reason=" + (variable_struct_exists(_j, "reason") ? string(_j.reason) : "")
                + " " + vs_lobby_flags());
            vs_lobby_reset();
            show_message("The lobby was closed.\n\n房间已关闭。");
            if (instance_exists(obj_multiplayer_lobby))
            {
                with (obj_multiplayer_lobby) { updateButtons(); }
            }
            break;
        case "error":
            vs_lobby_log("ctrl error code=" + string(_j.code) + " - " + string(_j.message));
            break;
        default:
            vs_lobby_log("ctrl unknown type=" + string(t));
            break;
    }
}
