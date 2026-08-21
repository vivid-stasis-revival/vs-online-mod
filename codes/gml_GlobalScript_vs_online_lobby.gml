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
    var want = string(_chart);
    var i = 0;
    repeat (array_length(global.song_list))
    {
        var s = global.song_list[i];
        if (s != undefined && variable_struct_exists(s, "chart_id") && string(s.chart_id) == want)
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

function vs_online_missing_song(_cid)
{
    var cid = (_cid == undefined) ? "" : string(_cid);
    if (cid == "") cid = vs_lobby_queued_chart_id();
    var nm = vs_chartmeta_get(cid);
    if (nm == "")
    {
        var meta = vs_chartmeta_slot();
        nm = (meta.pending == cid) ? "Looking up..." : "Missing chart";
    }
    var artist = vs_chartmeta_artist(cid);
    return { name: nm, formatted_name: nm, artist: artist, chart_id: cid, is_missing: true };
}

function vs_chartmeta_slot()
{
    if (!variable_global_exists("vs_chartmeta"))
    {
        global.vs_chartmeta = { names: {}, pending: "", q: [] };
    }
    if (!variable_struct_exists(global.vs_chartmeta, "q") || !is_array(global.vs_chartmeta.q))
    {
        global.vs_chartmeta.q = [];
    }
    return global.vs_chartmeta;
}

function vs_chartmeta_queued(_st, _cid)
{
    if (_st.pending == _cid) return true;
    var i = 0;
    repeat (array_length(_st.q))
    {
        if (_st.q[i] == _cid) return true;
        i++;
    }
    return false;
}

function vs_chartmeta_get(_cid)
{
    var cid = string(_cid);
    if (cid == "") return "";
    var sid = vs_online_song_id_from_chart(cid);
    var song = vs_online_song_from_id(sid);
    if (song != undefined)
    {
        if (variable_struct_exists(song, "formatted_name") && string(song.formatted_name) != "")
        {
            return string_replace_all(string(song.formatted_name), "#", " ");
        }
        if (variable_struct_exists(song, "name") && string(song.name) != "") return string(song.name);
    }
    var st = vs_chartmeta_slot();
    if (variable_struct_exists(st.names, cid))
    {
        var e = variable_struct_get(st.names, cid);
        if (e != undefined && variable_struct_exists(e, "name") && string(e.name) != "") return string(e.name);
    }
    return "";
}

function vs_chartmeta_artist(_cid)
{
    var cid = string(_cid);
    if (cid == "") return "";
    var st = vs_chartmeta_slot();
    if (variable_struct_exists(st.names, cid))
    {
        var e = variable_struct_get(st.names, cid);
        if (e != undefined && variable_struct_exists(e, "artist")) return string(e.artist);
    }
    return "";
}

function vs_chartmeta_label(_cid)
{
    var n = vs_chartmeta_get(_cid);
    if (n != "") return n;
    return "this chart";
}

function vs_chartmeta_remember(_it)
{
    if (_it == undefined) return;
    var cid = "";
    if (variable_struct_exists(_it, "chartId")) cid = string(_it.chartId);
    else if (variable_struct_exists(_it, "chart_id")) cid = string(_it.chart_id);
    if (cid == "") return;
    var nm = "";
    if (variable_struct_exists(_it, "formattedName") && string(_it.formattedName) != "")
    {
        nm = string_replace_all(string(_it.formattedName), "#", " ");
    }
    else if (variable_struct_exists(_it, "formatted_name") && string(_it.formatted_name) != "")
    {
        nm = string_replace_all(string(_it.formatted_name), "#", " ");
    }
    else if (variable_struct_exists(_it, "name")) nm = string(_it.name);
    if (nm == "") return;
    var artist = "";
    if (variable_struct_exists(_it, "artist")) artist = string(_it.artist);
    var sid = "";
    if (variable_struct_exists(_it, "id")) sid = string(_it.id);
    var st = vs_chartmeta_slot();
    variable_struct_set(st.names, cid, { name: nm, artist: artist, serverId: sid });
}

function vs_chartmeta_ingest_list(_data, _key)
{
    if (_data == undefined) return;
    vs_chartmeta_remember(_data);
    if (!variable_struct_exists(_data, _key) || !is_array(variable_struct_get(_data, _key))) return;
    var items = variable_struct_get(_data, _key);
    var i = 0;
    repeat (array_length(items))
    {
        vs_chartmeta_remember(items[i]);
        i++;
    }
}

function vs_chartmeta_want(_cid)
{
    var cid = string(_cid);
    if (cid == "") return;
    if (vs_chartmeta_get(cid) != "") return;
    var st = vs_chartmeta_slot();
    if (variable_struct_exists(st.names, cid)) return;
    if (vs_chartmeta_queued(st, cid)) return;
    if (st.pending != "")
    {
        array_push(st.q, cid);
        return;
    }
    st.pending = cid;
    vs_online_get_json("/api/v1/songs?chartId=" + vs_online_url_encode(cid) + "&size=1", false, vs_chartmeta_http);
}

function vs_chartmeta_http(_ok, _data, _status)
{
    var st = vs_chartmeta_slot();
    var cid = st.pending;
    if (_ok) vs_chartmeta_ingest_list(_data, "songs");
    if (cid != "" && vs_chartmeta_get(cid) == "")
    {
        vs_online_get_json("/api/v1/shatters?chart_id=" + vs_online_url_encode(cid) + "&size=1", false, vs_chartmeta_shatter_http);
        return;
    }
    vs_chartmeta_finish(_ok);
}

function vs_chartmeta_shatter_http(_ok, _data, _status)
{
    if (_ok)
    {
        vs_chartmeta_ingest_list(_data, "shatters");
        vs_chartmeta_ingest_list(_data, "songs");
    }
    vs_chartmeta_finish(_ok);
}

function vs_chartmeta_finish(_ok)
{
    var st = vs_chartmeta_slot();
    var cid = st.pending;
    st.pending = "";
    if (cid != "" && vs_chartmeta_get(cid) != "")
    {
        vs_lobby_log("chart name " + cid + " -> " + vs_chartmeta_get(cid));
    }
    else if (_ok && cid != "" && !variable_struct_exists(st.names, cid))
    {
        variable_struct_set(st.names, cid, { name: "", artist: "", serverId: "" });
    }
    vs_lobby_refresh_ui();
    var n = "";
    if (array_length(st.q) > 0)
    {
        n = st.q[0];
        array_delete(st.q, 0, 1);
    }
    if (n != "") vs_chartmeta_want(n);
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

function vs_online_queue_chart_id(_s)
{
    if (_s == undefined) return "";
    if (variable_struct_exists(_s, "chart_id") && string(_s.chart_id) != "")
    {
        return string(_s.chart_id);
    }
    if (variable_struct_exists(_s, "songId")) return vs_online_chart_id_of_song(_s.songId);
    return "";
}

function vs_lobby_queued_chart_id()
{
    if (!vs_lobby_has_queued_song()) return "";
    return vs_online_queue_chart_id(o_st_handle.songQueue[0]);
}

function vs_lobby_resolve_queued_songs()
{
    if (!instance_exists(o_st_handle)) return;
    var i = 0;
    if (is_array(o_st_handle.songQueue))
    {
        repeat (array_length(o_st_handle.songQueue))
        {
            vs_lobby_resolve_song_ref(o_st_handle.songQueue[i]);
            i++;
        }
    }
    vs_lobby_resolve_song_ref(o_st_handle.previousSong);
    vs_lobby_resolve_song_ref(o_st_handle.shadowSong);
    vs_lobby_fix_queue_diff();
}

function vs_lobby_resolve_song_ref(_s)
{
    if (_s == undefined) return;
    var cid = vs_online_queue_chart_id(_s);
    if (cid == "") return;
    _s.chart_id = cid;
    var sid = vs_online_song_id_from_chart(cid);
    if (sid >= 0) _s.songId = sid;
    else vs_chartmeta_want(cid);
}

// After a lobby download, song_list grows but process_song_unlocks may not
// have run yet. Ready/Options then indexes unlocked_songs[song.song_id] and
// crashes (index == length). Pad so confirm Create is always in range.
function vs_lobby_unlock_pad()
{
    if (!variable_global_exists("unlocked_songs") || !is_array(global.unlocked_songs))
    {
        global.unlocked_songs = [];
    }
    var n = 0;
    if (variable_global_exists("song_list") && is_array(global.song_list))
    {
        n = array_length(global.song_list);
    }
    while (array_length(global.unlocked_songs) < n)
    {
        array_push(global.unlocked_songs, [true, true, true, true]);
    }
    var i = 0;
    repeat (n)
    {
        var s = global.song_list[i];
        if (s != undefined && variable_struct_exists(s, "is_custom") && s.is_custom)
        {
            global.unlocked_songs[i] = [true, true, true, true];
        }
        i++;
    }
}

function vs_lobby_unlock_pad_id(_id)
{
    vs_lobby_unlock_pad();
    if (!is_real(_id) || _id < 0) return;
    while (array_length(global.unlocked_songs) <= _id)
    {
        array_push(global.unlocked_songs, [true, true, true, true]);
    }
}

function vs_lobby_song_has_diff(_song, _d)
{
    if (_song == undefined) return false;
    if (!is_real(_d) || _d < 0 || _d > 3) return false;
    // Do not use chart-file probes here. WP Options/Ready used to clamp the
    // queue to the first existing .vsc, which froze every song on OPENING.
    if (_d == 3)
    {
        var he = struct_get_fallback(_song, "has_encore", false);
        return (he == true || he == 1 || he == "1.0");
    }
    return true;
}

function vs_lobby_clamp_diff(_song, _d)
{
    var d = is_real(_d) ? floor(_d) : 0;
    if (vs_lobby_song_has_diff(_song, d)) return d;
    var i = 0;
    repeat (4)
    {
        if (vs_lobby_song_has_diff(_song, i)) return i;
        i++;
    }
    return d;
}

function vs_lobby_fix_queue_diff()
{
    if (!instance_exists(o_st_handle)) return;
    if (!is_array(o_st_handle.songQueue) || array_length(o_st_handle.songQueue) <= 0) return;
    var s = o_st_handle.songQueue[0];
    if (s == undefined) return;
    var song = undefined;
    if (variable_struct_exists(s, "songId")) song = vs_online_song_from_id(s.songId);
    if (song == undefined) return;
    vs_lobby_unlock_pad_id(struct_get_fallback(song, "song_id", s.songId));
    if (!vs_lobby_song_has_diff(song, 3)) song.has_encore = false;
    var d = 0;
    if (variable_struct_exists(s, "difficulty") && is_real(s.difficulty)) d = s.difficulty;
    else if (variable_global_exists("songselect_difficulty") && is_real(global.songselect_difficulty))
    {
        d = global.songselect_difficulty;
    }
    if (!vs_lobby_song_has_diff(song, d)) d = vs_lobby_clamp_diff(song, d);
    s.difficulty = d;
    global.songselect_difficulty = d;
}

function vs_lobby_queue_confirm_song()
{
    vs_lobby_resolve_queued_songs();
    vs_lobby_unlock_pad();
    if (!instance_exists(o_st_handle)) return undefined;
    if (!is_array(o_st_handle.songQueue) || array_length(o_st_handle.songQueue) <= 0) return undefined;
    var s = o_st_handle.songQueue[0];
    if (s == undefined) return undefined;
    var song = undefined;
    if (variable_struct_exists(s, "songId")) song = vs_online_song_from_id(s.songId);
    if (song == undefined) return undefined;
    vs_lobby_unlock_pad_id(struct_get_fallback(song, "song_id", s.songId));
    if (!vs_lobby_song_has_diff(song, 3)) song.has_encore = false;
    var d = 0;
    if (variable_struct_exists(s, "difficulty") && is_real(s.difficulty)) d = s.difficulty;
    else if (variable_global_exists("songselect_difficulty") && is_real(global.songselect_difficulty))
    {
        d = global.songselect_difficulty;
    }
    if (!vs_lobby_song_has_diff(song, d)) d = vs_lobby_clamp_diff(song, d);
    s.difficulty = d;
    global.songselect_difficulty = d;
    return { song: song, difficulty: d };
}

// --- steam_* shims (used via codepatches so the WP UI reads server state) ---

function vs_lobby_lobby_id()
{
    if (vs_online_is_custom())
    {
        if (!instance_exists(o_st_handle)) return 0;
        var lid = vs_http_num(o_st_handle.lobbyId, 0);
        if (lid > 0) return lid;
        // In-room even if lobbyId failed to coerce — landing/Draw must hide.
        if (vs_lobby_has_code()) return 1;
        return 0;
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

function vs_lobby_suggest_clear()
{
    if (!instance_exists(o_st_handle)) return;
    o_st_handle.suggestQueue = [];
}

function vs_lobby_suggest_item_name(_s)
{
    if (_s == undefined) return "";
    var song = undefined;
    if (variable_struct_exists(_s, "songId")) song = vs_online_song_from_id(_s.songId);
    if (song != undefined)
    {
        var d = variable_struct_exists(_s, "difficulty") ? _s.difficulty : 0;
        var nm = song_get_info(song, "name", d);
        if (nm != undefined && string(nm) != "") return string(nm);
        if (variable_struct_exists(song, "name") && string(song.name) != "") return string(song.name);
    }
    var cid = "";
    if (variable_struct_exists(_s, "chart_id")) cid = string(_s.chart_id);
    return vs_chartmeta_label(cid);
}

function vs_lobby_suggest_push(_s, _from)
{
    if (_s == undefined) return;
    var cid = vs_online_queue_chart_id(_s);
    if (cid == "")
    {
        vs_lobby_suggest_clear();
        vs_lobby_log("suggest clear from=" + string(_from));
        return;
    }
    vs_chartmeta_want(cid);
    var sid = vs_online_song_id_from_chart(cid);
    if (!instance_exists(o_st_handle)) return;
    o_st_handle.suggestQueue =
    [{
        member: _from,
        songId: sid,
        difficulty: variable_struct_exists(_s, "difficulty") ? _s.difficulty : 0,
        chart_id: cid
    }];
    vs_lobby_log("suggest recv chart=" + cid + " from=" + string(_from) + " songId=" + string(sid));
}

function vs_lobby_suggest_accept()
{
    if (!vs_lobby_is_owner()) return;
    var q = vs_lobby_suggest_q();
    if (array_length(q) <= 0) return;
    var item = q[0];
    array_delete(q, 0, 1);
    play_se(sfx_songsel_beginsong);
    vs_lobby_log("suggest accept chart=" + vs_online_queue_chart_id(item)
        + " songId=" + string(item.songId));
    send_packet(AddSongPacket, item);
}

function vs_lobby_suggest_ignore()
{
    if (!vs_lobby_is_owner()) return;
    var q = vs_lobby_suggest_q();
    if (array_length(q) <= 0) return;
    play_se(sfx_songsel_select);
    vs_lobby_log("suggest ignore chart=" + vs_online_queue_chart_id(q[0]));
    vs_lobby_suggest_clear();
    send_packet(SuggestSongPacket, { songId: -1, difficulty: -1, chart_id: "" });
}

function vs_lobby_suggest_step()
{
    if (!vs_online_is_custom()) return false;
    if (!vs_lobby_is_owner()) return false;
    var q = vs_lobby_suggest_q();
    if (array_length(q) <= 0) return false;
    if (input_check_pressed(4) || keyboard_check_pressed(vk_enter))
    {
        vs_lobby_suggest_accept();
    }
    else if (input_check_pressed(5) || keyboard_check_pressed(vk_escape))
    {
        vs_lobby_suggest_ignore();
    }
    return true;
}

function vs_lobby_suggest_draw()
{
    if (!vs_online_is_custom()) return;
    if (vs_lobby_lobby_id() <= 0) return;
    var q = vs_lobby_suggest_q();
    if (array_length(q) <= 0) return;
    var s = q[0];
    var member = (s != undefined && variable_struct_exists(s, "member")) ? vs_lobby_find_member(s.member) : undefined;
    var who = (member != undefined && variable_struct_exists(member, "name")) ? string(member.name) : "player";
    var title = "Suggest";
    var nm = vs_lobby_suggest_item_name(s);
    var dlab = vs_lobby_diff_short(variable_struct_exists(s, "difficulty") ? s.difficulty : -1);
    var body = nm;
    if (dlab != "") body = nm + "  " + dlab;
    var sub = who;
    if (s != undefined && variable_struct_exists(s, "songId") && vs_online_song_from_id(s.songId) == undefined)
    {
        sub = who + "  (not local)";
    }
    var hint = vs_lobby_is_owner() ? "CONFIRM / ESCAPE" : "waiting for host";
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pw = min(220, max(120, cw - 8));
    var ph = 56;
    var px = 4;
    var py = ch - ph - 4;
    draw_set_alpha(1);
    draw_set_color(c_black);
    draw_rectangle(px - 2, py - 2, px + pw + 2, py + ph + 2, false);
    draw_set_color(c_white);
    draw_rectangle(px, py, px + pw, py + ph, true);
    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_left);
    draw_set_color(c_aqua);
    draw_text(px + 6, py + 4, vs_dlbr_clip_text(title, pw - 12));
    draw_set_font(global.default_font);
    draw_set_color(c_white);
    draw_text(px + 6, py + 16, vs_dlbr_clip_text(body, pw - 12));
    draw_set_color(c_gray);
    draw_text(px + 6, py + 28, vs_dlbr_clip_text(sub, pw - 12));
    draw_set_color(c_yellow);
    draw_text(px + 6, py + 42, vs_dlbr_clip_text(hint, pw - 12));
    draw_set_color(c_white);
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
    // Prefer score_: vsml/GML can treat the identifier `score` as the
    // built-in instance var, so a struct key named score is not reliable.
    if (variable_struct_exists(_m, "score_")) return variable_struct_get(_m, "score_");
    if (variable_struct_exists(_m, "score")) return variable_struct_get(_m, "score");
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

function vs_lobby_local_play_diff()
{
    vs_lobby_fix_queue_diff();
    if (!instance_exists(o_st_handle)) return -1;
    if (!is_array(o_st_handle.songQueue) || array_length(o_st_handle.songQueue) <= 0) return -1;
    var s = o_st_handle.songQueue[0];
    if (s == undefined) return -1;
    if (variable_struct_exists(s, "difficulty")) return s.difficulty;
    if (variable_global_exists("songselect_difficulty") && global.songselect_difficulty != undefined)
    {
        return global.songselect_difficulty;
    }
    return -1;
}

function vs_lobby_local_autoplay()
{
    return variable_global_exists("op_autoplay") && global.op_autoplay;
}

function vs_lobby_confirm_opt_is_autoplay(_opt)
{
    if (!is_struct(_opt)) return false;
    if (variable_struct_exists(_opt, "name") && _opt.name == "Autoplay") return true;
    if (variable_struct_exists(_opt, "prop") && is_array(_opt.prop) && array_length(_opt.prop) >= 2)
    {
        if (_opt.prop[1] == "op_autoplay") return true;
    }
    return false;
}

// Collapse duplicate Autoplay rows from stacked mods (BugFix + this one).
// Add one in Worldcross if nobody else already did.
function vs_lobby_confirm_ensure_autoplay()
{
    if (!variable_instance_exists(id, "options")) return;
    var opts = variable_instance_get(id, "options");
    if (!is_array(opts)) return;
    var keep = -1;
    var i = 0;
    while (i < array_length(opts))
    {
        if (!vs_lobby_confirm_opt_is_autoplay(opts[i]))
        {
            i++;
        }
        else if (keep < 0)
        {
            keep = i;
            i++;
        }
        else
        {
            var cur = opts[i];
            var had = opts[keep];
            var curKey = is_struct(cur) && variable_struct_exists(cur, "key");
            var hadKey = is_struct(had) && variable_struct_exists(had, "key");
            if (curKey && !hadKey)
            {
                array_delete(opts, keep, 1);
                keep = i - 1;
                i = keep + 1;
            }
            else
            {
                array_delete(opts, i, 1);
            }
        }
    }
    if (keep < 0 && variable_global_exists("multiplayerLobby") && global.multiplayerLobby)
    {
        array_push(opts, { name: "Autoplay", type: 0, choices: ["OFF", "ON"], prop: [global, "op_autoplay"], key: ["system", "config", "autoplay", 0] });
    }
}

function vs_lobby_has_queued_song()
{
    if (!instance_exists(o_st_handle)) return false;
    if (!is_array(o_st_handle.songQueue) || array_length(o_st_handle.songQueue) <= 0) return false;
    return o_st_handle.songQueue[0] != undefined;
}

function vs_lobby_local_missing()
{
    if (!vs_lobby_has_queued_song()) return false;
    var s = o_st_handle.songQueue[0];
    var sid = variable_struct_exists(s, "songId") ? s.songId : -1;
    return vs_online_song_from_id(sid) == undefined;
}

function vs_lobby_local_need_dl()
{
    if (vs_lobby_local_missing()) return true;
    var st = vs_lobby_dl_st();
    var cid = vs_lobby_queued_chart_id();
    return cid != "" && st.need_upd && string(st.chartId) == cid;
}

function vs_lobby_tag_need_dl(_m)
{
    if (!vs_lobby_has_queued_song()) return false;
    if (vs_lobby_member_is_host(_m)) return false;
    if (_m != undefined && variable_struct_exists(_m, "id") && string(_m.id) == string(vs_online_player_id()))
    {
        return vs_lobby_local_need_dl();
    }
    return _m != undefined && variable_struct_exists(_m, "need_dl") && _m.need_dl;
}

function vs_lobby_member_connected(_m)
{
    if (_m == undefined) return false;
    if (!variable_struct_exists(_m, "connected")) return true;
    return vs_lobby_json_true(_m.connected);
}

function vs_lobby_member_needs_chart(_m)
{
    if (_m == undefined) return false;
    if (variable_struct_exists(_m, "npc") && _m.npc) return false;
    if (!vs_lobby_member_connected(_m)) return false;
    if (variable_struct_exists(_m, "id") && string(_m.id) == string(vs_online_player_id()))
    {
        return vs_lobby_local_need_dl();
    }
    return variable_struct_exists(_m, "need_dl") && _m.need_dl;
}

function vs_lobby_need_dl_label()
{
    if (vs_lobby_local_need_dl()) return "You still need this chart";
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return "Someone still needs this chart";
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var m = o_st_handle.lobbyMembers[i];
        if (vs_lobby_member_needs_chart(m))
        {
            var nm = (m != undefined && variable_struct_exists(m, "name")) ? string(m.name) : "";
            if (nm == "") nm = "player";
            return "Waiting for " + nm;
        }
        i++;
    }
    return "Someone still needs this chart";
}

function vs_lobby_everyone_ready()
{
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return false;
    var n = 0;
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var m = o_st_handle.lobbyMembers[i];
        i++;
        if (m == undefined) continue;
        if (variable_struct_exists(m, "npc") && m.npc) continue;
        if (!vs_lobby_member_connected(m)) continue;
        n++;
        if (!m.ready) return false;
    }
    return n > 0;
}

function vs_lobby_member_await_score(_m)
{
    if (_m == undefined) return false;
    if (variable_struct_exists(_m, "npc") && _m.npc) return false;
    if (!vs_lobby_member_connected(_m)) return false;
    return !(_m.reportedScore);
}

function vs_lobby_note_seen(_id)
{
    var m = vs_lobby_find_member(_id);
    if (m == undefined) return;
    m.last_seen = current_time;
}

function vs_lobby_wait_st()
{
    if (!variable_global_exists("vs_lobby_wait"))
    {
        global.vs_lobby_wait = { t0: 0, logged: false };
    }
    return global.vs_lobby_wait;
}

function vs_lobby_wait_begin()
{
    var st = vs_lobby_wait_st();
    st.t0 = current_time;
    st.logged = false;
    var n = 0;
    if (instance_exists(o_st_handle) && is_array(o_st_handle.lobbyMembers))
    {
        n = array_length(o_st_handle.lobbyMembers);
    }
    vs_lobby_log("waiting_room begin members=" + string(n) + " pending=" + vs_lobby_wait_pending_label());
}

function vs_lobby_wait_pending_label()
{
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return "";
    var bits = "";
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var m = o_st_handle.lobbyMembers[i];
        i++;
        if (!vs_lobby_member_await_score(m)) continue;
        var nm = (m != undefined && variable_struct_exists(m, "name")) ? string(m.name) : "";
        if (nm == "") nm = "player";
        if (bits != "") bits += ", ";
        bits += nm;
    }
    return bits;
}

function vs_lobby_wait_member_stale(_m)
{
    if (_m == undefined) return false;
    var st = vs_lobby_wait_st();
    var t0 = st.t0;
    var seen = (variable_struct_exists(_m, "last_seen") && is_real(_m.last_seen)) ? _m.last_seen : 0;
    var last = t0;
    if (seen > last) last = seen;
    return (current_time - last) >= 45000;
}

function vs_lobby_wait_skip_pending(_why)
{
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return 0;
    var n = 0;
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var m = o_st_handle.lobbyMembers[i];
        i++;
        if (!vs_lobby_member_await_score(m)) continue;
        m.reportedScore = true;
        n++;
    }
    if (n > 0) vs_lobby_log("waiting_room skip n=" + string(n) + " why=" + string(_why));
    return n;
}

function vs_lobby_wait_guest_leave(_why)
{
    vs_lobby_log("waiting_room guest leave " + string(_why));
    room_goto(scene_multiplayer_lobby);
}

function vs_lobby_wait_step()
{
    if (!vs_online_is_custom()) return;
    if (!instance_exists(obj_multiplayer_waiting_room)) return;
    var st = vs_lobby_wait_st();
    if (st.t0 <= 0) vs_lobby_wait_begin();
    var pending = vs_lobby_wait_pending_label();
    if (pending == "") return;
    if (!st.logged)
    {
        st.logged = true;
        vs_lobby_log("waiting_room pending " + pending);
    }
    if (vs_lobby_is_owner())
    {
        var i = 0;
        var skipped = 0;
        if (instance_exists(o_st_handle) && is_array(o_st_handle.lobbyMembers))
        {
            repeat (array_length(o_st_handle.lobbyMembers))
            {
                var m = o_st_handle.lobbyMembers[i];
                i++;
                if (!vs_lobby_member_await_score(m)) continue;
                if (!vs_lobby_wait_member_stale(m)) continue;
                m.reportedScore = true;
                skipped++;
            }
        }
        if (skipped > 0) vs_lobby_log("waiting_room timeout skip n=" + string(skipped) + " left=" + vs_lobby_wait_pending_label());
    }
    var cancel = keyboard_check_pressed(vk_escape);
    if (variable_global_exists("menu_cancel") && keyboard_check_pressed(global.menu_cancel)) cancel = true;
    if (input_check_pressed(5)) cancel = true;
    if (cancel)
    {
        play_se(sfx_songsel_select);
        if (vs_lobby_is_owner()) vs_lobby_wait_skip_pending("escape");
        else vs_lobby_wait_guest_leave("escape");
        return;
    }
}

function vs_lobby_wait_draw()
{
    draw_set_font(global.default_font);
    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text(10, 10, "Waiting for results...");
    if (!vs_online_is_custom()) return;
    var pending = vs_lobby_wait_pending_label();
    if (pending == "") return;
    draw_text(10, 22, "Waiting for " + pending);
    var hint = vs_lobby_is_owner() ? "ESCAPE skip" : "ESCAPE lobby";
    var left = 45;
    var st = vs_lobby_wait_st();
    if (instance_exists(o_st_handle) && is_array(o_st_handle.lobbyMembers))
    {
        var i = 0;
        repeat (array_length(o_st_handle.lobbyMembers))
        {
            var m = o_st_handle.lobbyMembers[i];
            i++;
            if (!vs_lobby_member_await_score(m)) continue;
            var seen = (variable_struct_exists(m, "last_seen") && is_real(m.last_seen)) ? m.last_seen : 0;
            var last = st.t0;
            if (seen > last) last = seen;
            var sec = 45 - floor((current_time - last) / 1000);
            if (sec < left) left = sec;
        }
    }
    if (left < 0) left = 0;
    draw_set_color(c_yellow);
    draw_text(10, 34, hint + "  auto " + string(left) + "s");
    draw_set_color(c_white);
}

function vs_lobby_anyone_need_dl()
{
    if (!vs_online_is_custom()) return false;
    if (vs_lobby_local_need_dl()) return true;
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return false;
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        if (vs_lobby_member_needs_chart(o_st_handle.lobbyMembers[i])) return true;
        i++;
    }
    return false;
}

function vs_lobby_diff_short(_d)
{
    if (_d == 0) return "OPN";
    if (_d == 1) return "MID";
    if (_d == 2) return "FIN";
    if (_d == 3) return "ENC";
    if (_d == 4) return "PRE";
    return "";
}

function vs_lobby_diff_color(_d)
{
    if (_d == 0) return make_color_rgb(0, 224, 255);
    if (_d == 1) return make_color_rgb(255, 220, 0);
    if (_d == 2) return make_color_rgb(255, 80, 80);
    if (_d == 3) return make_color_rgb(255, 80, 200);
    if (_d == 4) return make_color_rgb(255, 210, 26);
    return c_white;
}

function vs_lobby_tag_diff(_m)
{
    if (_m != undefined && variable_struct_exists(_m, "play_diff") && real(_m.play_diff) >= 0)
    {
        return _m.play_diff;
    }
    if (_m != undefined && variable_struct_exists(_m, "id") && string(_m.id) == string(vs_online_player_id()))
    {
        return vs_lobby_local_play_diff();
    }
    return -1;
}

function vs_lobby_tag_ap(_m)
{
    if (_m != undefined && variable_struct_exists(_m, "autoplay") && _m.autoplay) return true;
    if (_m != undefined && variable_struct_exists(_m, "id") && string(_m.id) == string(vs_online_player_id()))
    {
        return vs_lobby_local_autoplay();
    }
    return false;
}

function vs_lobby_ui_font()
{
    if (variable_global_exists("default_font")) return global.default_font;
    return fnt_monacovs;
}

function vs_lobby_draw_namecard_tags(_m, _rx, _ry, _halign)
{
    if (_m == undefined) return;
    var d = vs_lobby_tag_diff(_m);
    var lab = vs_lobby_diff_short(d);
    var ap = vs_lobby_tag_ap(_m);
    if (lab == "" && !ap) return;
    var bits = lab;
    if (ap) bits = (bits == "") ? "AP" : (bits + " AP");
    if (_halign == undefined) _halign = fa_right;
    draw_set_font(vs_lobby_ui_font());
    draw_set_halign(_halign);
    draw_set_color(ap && lab == "" ? c_yellow : vs_lobby_diff_color(d));
    draw_text_o(_rx, _ry, bits);
    draw_set_halign(fa_left);
    draw_set_color(c_white);
}

function vs_lobby_draw_local_tags(_rx, _ry, _halign)
{
    vs_lobby_draw_namecard_tags(
        { play_diff: vs_lobby_local_play_diff(), autoplay: vs_lobby_local_autoplay() },
        _rx, _ry, _halign);
}

function vs_lobby_member_is_host(_m)
{
    if (_m == undefined) return false;
    var hid = vs_lobby_owner_id();
    if (hid != "" && variable_struct_exists(_m, "id") && string(_m.id) == string(hid)) return true;
    return variable_struct_exists(_m, "host") && _m.host;
}

function vs_lobby_draw_host_mark(_m, _x, _y)
{
    if (!vs_lobby_member_is_host(_m)) return;
    draw_set_font(vs_lobby_ui_font());
    draw_set_halign(fa_left);
    draw_set_color(c_yellow);
    draw_text_o(_x, _y, "M");
    draw_set_color(c_white);
}

function vs_lobby_draw_dl_mark(_m, _x, _y)
{
    if (!vs_lobby_tag_need_dl(_m)) return;
    draw_set_font(vs_lobby_ui_font());
    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(255, 40, 40));
    draw_text_o(_x, _y, "D");
    draw_set_color(c_white);
}

function vs_lobby_draw_avatar_marks(_m, _x, _y)
{
    vs_lobby_draw_host_mark(_m, _x, _y);
    vs_lobby_draw_dl_mark(_m, _x, _y);
}

function vs_lobby_keep_play_tags(_dst, _src)
{
    if (_dst == undefined || _src == undefined) return;
    if (variable_struct_exists(_src, "play_diff")) _dst.play_diff = _src.play_diff;
    if (variable_struct_exists(_src, "autoplay")) _dst.autoplay = _src.autoplay;
    if (variable_struct_exists(_src, "need_dl")) _dst.need_dl = _src.need_dl;
}

function vs_lobby_score_live()
{
    return instance_exists(o_score_updater);
}

// o_score_updater copies lobbyMembers once. A later roster rebuild would
// leave the overlay on stale structs while UpdateScore writes the new ones.
function vs_lobby_scoreboard_tick()
{
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return;
    members = [];
    array_copy(members, 0, o_st_handle.lobbyMembers, 0, array_length(o_st_handle.lobbyMembers));
    var me = vs_lobby_find_member(vs_online_player_id());
    if (me == undefined) me = o_st_handle.currentMember;
    if (me == undefined) return;
    currentMember = me;
    if (variable_global_exists("currentscore"))
    {
        vs_member_set_score(me, global.currentscore);
    }
}

function vs_lobby_ops_lobby()
{
    if (!instance_exists(obj_multiplayer_lobby)) return noone;
    return obj_multiplayer_lobby.id;
}

function vs_lobby_ops_active()
{
    var lobby = vs_lobby_ops_lobby();
    if (lobby == noone) return false;
    return variable_instance_exists(lobby, "opsMode") && string(lobby.opsMode) != "";
}

function vs_lobby_ops_targets()
{
    var out = [];
    if (!instance_exists(o_st_handle) || !is_array(o_st_handle.lobbyMembers)) return out;
    var me = string(vs_online_player_id());
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var m = o_st_handle.lobbyMembers[i];
        if (m != undefined && variable_struct_exists(m, "id") && string(m.id) != "" && string(m.id) != me)
        {
            array_push(out, m);
        }
        i++;
    }
    return out;
}

function vs_lobby_ops_kick_slot()
{
    var lobby = vs_lobby_ops_lobby();
    if (lobby == noone || !variable_instance_exists(lobby, "menu_actions_host")) return -1;
    var acts = lobby.menu_actions_host;
    var i = 0;
    repeat (array_length(acts))
    {
        if (acts[i] != undefined && variable_struct_exists(acts[i], "callback") && acts[i].callback == "kick") return i;
        i++;
    }
    return -1;
}

function vs_lobby_ops_relabel()
{
    var lobby = vs_lobby_ops_lobby();
    var slot = vs_lobby_ops_kick_slot();
    if (lobby == noone || slot < 0) return;
    var lab = "Kick";
    if (vs_lobby_ops_active())
    {
        var t = vs_lobby_ops_targets();
        var i = lobby.opsCursor;
        if (i >= 0 && i < array_length(t) && t[i] != undefined)
        {
            lab = "Kick " + truncate_string(string(t[i].name), 48);
        }
    }
    lobby.menu_actions_host[slot].txt = lab;
}

function vs_lobby_ops_end()
{
    var lobby = vs_lobby_ops_lobby();
    if (lobby == noone) return;
    if (variable_instance_exists(lobby, "opsMode")) lobby.opsMode = "";
    if (variable_instance_exists(lobby, "opsCursor")) lobby.opsCursor = 0;
    vs_lobby_ops_relabel();
}

function vs_lobby_ops_begin(_mode)
{
    if (!vs_online_is_custom() || !vs_lobby_is_owner()) return;
    var lobby = vs_lobby_ops_lobby();
    if (lobby == noone) return;
    var t = vs_lobby_ops_targets();
    if (array_length(t) <= 0)
    {
        play_se(sfx_songsel_select);
        vs_lobby_log("ops " + string(_mode) + " no targets");
        return;
    }
    lobby.opsMode = string(_mode);
    lobby.opsCursor = 0;
    var slot = vs_lobby_ops_kick_slot();
    if (slot >= 0) lobby.cursor_pos = slot;
    vs_lobby_ops_relabel();
    play_se(sfx_songsel_diff);
    vs_lobby_log("ops begin " + string(_mode) + " n=" + string(array_length(t)));
}

function vs_lobby_ops_selected()
{
    if (!vs_lobby_ops_active()) return undefined;
    var lobby = vs_lobby_ops_lobby();
    var t = vs_lobby_ops_targets();
    var i = lobby.opsCursor;
    if (i < 0 || i >= array_length(t)) return undefined;
    return t[i];
}

function vs_lobby_draw_ops_card(_m, _x, _y)
{
    var sel = vs_lobby_ops_selected();
    if (sel == undefined || _m == undefined) return;
    if (!variable_struct_exists(_m, "id") || string(_m.id) != string(sel.id)) return;
    draw_set_color(c_yellow);
    draw_set_alpha(0.28 + 0.12 * sin(current_time / 140));
    draw_rectangle(_x, _y, _x + 145, _y + 32, false);
    draw_set_alpha(1);
    draw_rectangle(_x, _y, _x + 145, _y + 32, true);
    draw_set_color(c_white);
}

function vs_lobby_ops_scroll_to(_m)
{
    var lobby = vs_lobby_ops_lobby();
    if (lobby == noone || _m == undefined || !instance_exists(o_st_handle)) return;
    var members = o_st_handle.lobbyMembers;
    var i = 0;
    var idx = -1;
    repeat (array_length(members))
    {
        if (members[i] != undefined && string(members[i].id) == string(_m.id))
        {
            idx = i;
            break;
        }
        i++;
    }
    if (idx < 0) return;
    var y0 = idx * 35;
    var max_off = clamp((array_length(members) - 3) * 35, 0, 999);
    if (y0 < lobby.member_y_offset) lobby.member_y_offset = y0;
    if (y0 > lobby.member_y_offset + 70) lobby.member_y_offset = y0 - 70;
    lobby.member_y_offset = clamp(lobby.member_y_offset, 0, max_off);
}

function vs_lobby_kick_done(_ok, _data, _status)
{
    vs_lobby_log("kick " + vs_lobby_http_why(_ok, _data, _status));
    if (!_ok)
    {
        show_message("Could not kick that player.\n\n无法踢出该玩家。");
    }
}

function vs_lobby_kick(_playerId)
{
    if (!vs_online_is_custom() || !vs_lobby_is_owner()) return;
    if (!vs_lobby_has_code()) return;
    var pid = string(_playerId);
    if (pid == "" || pid == string(vs_online_player_id())) return;
    var code = string(o_st_handle.lobbyCode);
    vs_lobby_log("REST kick id=" + pid);
    vs_http_request_path(
        "/api/v1/lobbies/" + code + "/members/" + vs_online_url_encode(pid),
        true,
        "DELETE",
        { Accept: "application/json" },
        "",
        vs_lobby_kick_done,
        true,
        "",
        "");
}

function vs_lobby_ops_confirm()
{
    var lobby = vs_lobby_ops_lobby();
    if (lobby == noone) return;
    var sel = vs_lobby_ops_selected();
    if (sel == undefined)
    {
        play_se(sfx_songsel_select);
        vs_lobby_ops_end();
        return;
    }
    if (lobby.opsMode == "kick")
    {
        play_se(sfx_songsel_beginsong);
        vs_lobby_kick(sel.id);
    }
    vs_lobby_ops_end();
}

function vs_lobby_ops_step()
{
    if (!vs_lobby_ops_active()) return false;
    var lobby = vs_lobby_ops_lobby();
    var t = vs_lobby_ops_targets();
    if (array_length(t) <= 0)
    {
        vs_lobby_ops_end();
        return true;
    }
    if (lobby.opsCursor < 0) lobby.opsCursor = 0;
    if (lobby.opsCursor >= array_length(t)) lobby.opsCursor = array_length(t) - 1;
    var d = (input_check_pressed(12) - input_check_pressed(11))
        + (input_check_pressed(14) - input_check_pressed(13));
    if (d != 0)
    {
        play_se(sfx_songsel_cursor);
        lobby.opsCursor = (array_length(t) + lobby.opsCursor + d) % array_length(t);
    }
    vs_lobby_ops_relabel();
    vs_lobby_ops_scroll_to(t[lobby.opsCursor]);
    if (input_check_pressed(4))
    {
        vs_lobby_ops_confirm();
    }
    else if (input_check_pressed(5))
    {
        play_se(sfx_songsel_select);
        vs_lobby_ops_end();
    }
    return true;
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
        global.vs_avatar_placing = false;
        global.vs_avatar_placeTries = 0;
    }
    if (!variable_global_exists("vs_avatar_placing"))
    {
        global.vs_avatar_placing = false;
        global.vs_avatar_placeTries = 0;
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
    global.vs_avatar_placing = false;
    global.vs_avatar_placeTries = 0;
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

function vs_online_avatar_wait_file()
{
    if (global.vs_avatar_placing) return;
    global.vs_avatar_placing = true;
    global.vs_avatar_placeTries = 0;
    call_later(1, time_source_units_frames, vs_online_avatar_on_place);
}

function vs_online_avatar_on_place()
{
    vs_online_avatar_cache();
    if (!global.vs_avatar_busy || !global.vs_avatar_placing) return;
    if (vs_http_file_here(global.vs_avatar_dest))
    {
        show_debug_message("VS Online: avatar file ready pid=" + string(global.vs_avatar_cur));
        vs_online_avatar_finish(true);
        return;
    }
    global.vs_avatar_placeTries += 1;
    if (global.vs_avatar_placeTries >= 45)
    {
        show_debug_message("VS Online: avatar file missing pid=" + string(global.vs_avatar_cur));
        vs_online_avatar_finish(false);
        return;
    }
    call_later(1, time_source_units_frames, vs_online_avatar_on_place);
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
    var dest = global.vs_avatar_dest;
    var here = vs_http_file_here(dest);
    var httpStatus = vs_http_num(ds_map_find_value(async_load, "http_status"), -1);
    var settle = vs_http_file_settle(gmStatus, httpStatus, here, doneProg);
    if (settle == 0)
    {
        if (doneProg || gmStatus == 0) vs_online_avatar_wait_file();
        return;
    }
    var ok = (settle > 0);
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
    global.vs_avatar_placing = false;
    global.vs_avatar_placeTries = 0;
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
        play_diff: -1,
        autoplay: false,
        need_dl: 0,
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
        var pid = "";
        if (src != undefined && variable_struct_exists(src, "playerId")) pid = string(src.playerId);
        var m = undefined;
        if (pid != "" && variable_struct_exists(prevById, pid))
        {
            // Keep the same struct so live score overlays keep updating.
            m = variable_struct_get(prevById, pid);
            vs_lobby_touch_member(src);
            m.order = i;
        }
        else
        {
            m = vs_lobby_build_member(src);
            m.order = i;
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
        if (o_st_handle.lobbyMembers[i].id != undefined && string(o_st_handle.lobbyMembers[i].id) == string(_id))
        {
            array_delete(o_st_handle.lobbyMembers, i, 1);
            vs_lobby_spi_unmark(_id);
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
    return (n == "UpdateScore");
}

// Host copies queue / player info / score to everyone who is Connected.
// REST / matchmake member_joined is too early (guest WS is still down). The
// server notifies again on WS attach with connected:true; SendPlayerInfo from
// the joiner is a third fallback.
function vs_lobby_spi_st()
{
    if (!variable_global_exists("vs_lobby_spi_ok") || !is_struct(global.vs_lobby_spi_ok))
    {
        global.vs_lobby_spi_ok = {};
    }
    return global.vs_lobby_spi_ok;
}

function vs_lobby_spi_need_sync(_id)
{
    var st = vs_lobby_spi_st();
    var k = string(_id);
    if (k == "") return false;
    return !(variable_struct_exists(st, k) && variable_struct_get(st, k));
}

function vs_lobby_spi_mark(_id)
{
    var k = string(_id);
    if (k == "") return;
    variable_struct_set(vs_lobby_spi_st(), k, true);
}

function vs_lobby_spi_unmark(_id)
{
    var k = string(_id);
    if (k == "")
    {
        global.vs_lobby_spi_ok = {};
        return;
    }
    variable_struct_set(vs_lobby_spi_st(), k, false);
}

function vs_lobby_host_sync(_why, _from)
{
    if (!vs_online_is_custom()) return;
    if (!vs_lobby_is_owner()) return;
    if (!instance_exists(o_st_handle)) return;
    // SendQueue also writes per-member scores. During play that overwrites
    // live UpdateScore values with whatever the host last stored (often 0).
    if (vs_lobby_score_live())
    {
        vs_lobby_log("host sync skip in play " + string(_why));
        return;
    }
    if (_from == undefined) _from = "";
    var fromId = string(_from);
    if (fromId != "")
    {
        if (!vs_lobby_spi_need_sync(fromId))
        {
            vs_lobby_log("host sync skip " + string(_why) + " already from=" + fromId);
            return;
        }
        vs_lobby_spi_mark(fromId);
    }
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

function vs_lobby_find_member(_id)
{
    if (!instance_exists(o_st_handle)) return undefined;
    var want = string(_id);
    if (want == "") return undefined;
    var i = 0;
    repeat (array_length(o_st_handle.lobbyMembers))
    {
        var m = o_st_handle.lobbyMembers[i];
        if (m != undefined && string(m.id) == want) return m;
        i++;
    }
    return undefined;
}

function vs_lobby_fetch_clear()
{
    global.vs_lobby_mem_http = false;
    global.vs_lobby_mem_again = false;
}

// Matchmake into an existing room now emits member_joined (same as join).
// A packet from an unknown sender still gets a stub so official receive()
// does not crash; GET /members then fills name/avatar/host from the server roster.
function vs_lobby_ensure_sender(_senderId)
{
    if (!instance_exists(o_st_handle)) return false;
    if (_senderId == undefined || string(_senderId) == "") return false;
    if (vs_lobby_find_member(_senderId) != undefined) return false;
    vs_lobby_log("ensure sender stub id=" + string(_senderId));
    array_push(o_st_handle.lobbyMembers, vs_lobby_build_member({
        playerId: _senderId,
        name: "",
        ready: 0,
        host: false,
        order: array_length(o_st_handle.lobbyMembers)
    }));
    vs_lobby_fetch_members("unknown sender");
    vs_lobby_host_sync("ensure sender", _senderId);
    return true;
}

function vs_lobby_fetch_members(_why)
{
    if (!instance_exists(o_st_handle) || o_st_handle.lobbyCode == undefined) return;
    var code = string(o_st_handle.lobbyCode);
    if (code == "") return;
    if (variable_global_exists("vs_lobby_mem_http") && global.vs_lobby_mem_http == true)
    {
        global.vs_lobby_mem_again = true;
        vs_lobby_log("GET /members defer " + string(_why));
        return;
    }
    global.vs_lobby_mem_http = true;
    global.vs_lobby_mem_again = false;
    vs_lobby_log("GET /members " + string(_why) + " code=" + code);
    vs_online_get_json("/api/v1/lobbies/" + code + "/members", true, vs_lobby_fetch_members_done);
}

function vs_lobby_fetch_members_done(_ok, _data, _status)
{
    vs_lobby_log("GET /members result " + vs_lobby_http_why(_ok, _data, _status));
    global.vs_lobby_mem_http = false;
    var again = variable_global_exists("vs_lobby_mem_again") && global.vs_lobby_mem_again == true;
    global.vs_lobby_mem_again = false;
    if (_ok && _data != undefined && variable_struct_exists(_data, "members") && is_array(_data.members) && instance_exists(o_st_handle) && vs_lobby_has_code())
    {
        vs_lobby_apply_roster(_data.members);
        o_st_handle.currentMember = vs_lobby_find_member(vs_online_player_id());
        var hid = vs_lobby_get_host_id();
        if (hid != "")
        {
            vs_lobby_refresh_host_flags(hid);
        }
        vs_lobby_refresh_ui();
    }
    if (again && vs_lobby_has_code()) vs_lobby_fetch_members("deferred");
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
            var skipped = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (skipped != undefined) { skipped(false, undefined); }
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
    if (vs_lobby_has_code() || vs_ws_state().state == 1)
    {
        vs_lobby_log("matchmake skip already " + vs_lobby_flags());
        if (_on_done != undefined) { _on_done(true, undefined); }
        return;
    }
    if (!variable_global_exists("vs_lobby_cb"))
    {
        global.vs_lobby_cb = { is_public: true, code: "", on_done: undefined, match_busy: false };
    }
    if (variable_struct_exists(global.vs_lobby_cb, "match_busy") && global.vs_lobby_cb.match_busy == true)
    {
        vs_lobby_log("matchmake skip busy");
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        if (vs_lobby_has_code() || vs_ws_state().state == 1)
        {
            vs_lobby_log("matchmake skip already after conn " + vs_lobby_flags());
            var cb0 = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (cb0 != undefined) { cb0(true, undefined); }
            return;
        }
        if (variable_struct_exists(global.vs_lobby_cb, "match_busy") && global.vs_lobby_cb.match_busy == true)
        {
            vs_lobby_log("matchmake skip busy after conn");
            var cbBusy = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (cbBusy != undefined) { cbBusy(false, undefined); }
            return;
        }
        global.vs_lobby_cb.match_busy = true;
        vs_lobby_log("matchmake POST /lobbies/matchmake");
        vs_online_post_json("/api/v1/lobbies/matchmake", {}, function(_ok, _data, _status)
        {
            global.vs_lobby_cb.match_busy = false;
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
    var joinCode = vs_lobby_norm_code(_code);
    vs_lobby_log("join start code=" + joinCode + " raw=" + string(_code) + " " + vs_lobby_flags());
    if (joinCode == undefined || string_length(joinCode) != 6)
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
    if (variable_struct_exists(global.vs_lobby_cb, "join_busy") && global.vs_lobby_cb.join_busy == true)
    {
        vs_lobby_log("join skip busy");
        if (_on_done != undefined) { _on_done(false, undefined); }
        return;
    }
    global.vs_lobby_cb.code = joinCode;
    global.vs_lobby_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        if (variable_struct_exists(global.vs_lobby_cb, "join_busy") && global.vs_lobby_cb.join_busy == true)
        {
            vs_lobby_log("join skip busy after conn");
            var cbBusy = global.vs_lobby_cb.on_done;
            global.vs_lobby_cb.on_done = undefined;
            if (cbBusy != undefined) { cbBusy(false, undefined); }
            return;
        }
        global.vs_lobby_cb.join_busy = true;
        vs_lobby_log("join POST /lobbies/join code=" + string(global.vs_lobby_cb.code));
        // Do not write `{ code: ... }` here: vs_lobby_join's old `var code`
        // made vsml rewrite that key to self.code inside this anon.
        var body = {};
        variable_struct_set(body, "code", global.vs_lobby_cb.code);
        vs_online_post_json("/api/v1/lobbies/join", body, function(_ok, _data, _status)
        {
            global.vs_lobby_cb.join_busy = false;
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

function vs_lobby_count_st()
{
    // Keep flag names off the function namespace. `global.vs_lobby_count_busy`
    // was the script itself (always truthy), so GET /lobbies never ran.
    if (!variable_global_exists("vs_lobby_cnt") || !is_struct(global.vs_lobby_cnt))
    {
        global.vs_lobby_cnt = { inflight: false, wait: false, t0: 0, next_at: 0, timer: undefined };
    }
    if (!variable_struct_exists(global.vs_lobby_cnt, "inflight")) global.vs_lobby_cnt.inflight = false;
    if (!variable_struct_exists(global.vs_lobby_cnt, "wait")) global.vs_lobby_cnt.wait = false;
    if (!variable_struct_exists(global.vs_lobby_cnt, "t0")) global.vs_lobby_cnt.t0 = 0;
    if (!variable_struct_exists(global.vs_lobby_cnt, "next_at")) global.vs_lobby_cnt.next_at = 0;
    if (!variable_struct_exists(global.vs_lobby_cnt, "timer")) global.vs_lobby_cnt.timer = undefined;
    return global.vs_lobby_cnt;
}

function vs_lobby_count_schedule()
{
    var st = vs_lobby_count_st();
    if (!instance_exists(obj_multiplayer_lobby)) return;
    if (!vs_online_is_custom()) return;
    // Reset so manual Refresh / list_done always get a fresh 5s window.
    if (st.timer != undefined)
    {
        call_cancel(st.timer);
        st.timer = undefined;
    }
    st.wait = true;
    st.next_at = current_time + 5000;
    st.timer = call_later(60 * 5, time_source_units_frames, vs_lobby_count_on_timer);
}

function vs_lobby_count_on_timer()
{
    var st = vs_lobby_count_st();
    st.wait = false;
    st.timer = undefined;
    vs_lobby_refresh_count();
}

function vs_lobby_refresh_count()
{
    if (!instance_exists(obj_multiplayer_lobby) || !vs_online_is_custom()) return;
    var st = vs_lobby_count_st();
    // Landing is vs_lobby_lobby_id()<=0. A leftover invite code must not
    // block the public list; a stuck HTTP flag also must not last forever.
    var inRoom = vs_lobby_lobby_id() > 0;
    var blocked = st.inflight && (current_time - st.t0) < 15000;
    if (inRoom || blocked)
    {
        vs_lobby_count_schedule();
        return;
    }
    // New matchmaking landing owns the public list fetch.
    if (vs_lobby_browser_active())
    {
        vs_lobby_browser_refresh(false);
        return;
    }
    st.inflight = true;
    st.t0 = current_time;
    vs_online_get_json("/api/v1/lobbies", false, vs_lobby_count_done);
}

function vs_lobby_count_done(_ok, _data, _status)
{
    vs_lobby_count_st().inflight = false;
    var n = 0;
    var got = false;
    if (_ok && _data != undefined && variable_struct_exists(_data, "lobbies") && is_array(_data.lobbies))
    {
        n = array_length(_data.lobbies);
        got = true;
    }
    if (got && instance_exists(obj_multiplayer_lobby))
    {
        obj_multiplayer_lobby.lobbyCount = n;
    }
    vs_lobby_count_schedule();
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
            // A second matchmake can create a new empty room while we are
            // still connecting to the first. Keep the first join.
            if (vs_ws_is_open() || vs_ws_state().state == 1)
            {
                vs_lobby_log("enter ignore extra " + newCode + " keep " + old);
                vs_lobby_rest_leave(newCode);
                vs_lobby_refresh_ui();
                return;
            }
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

function vs_lobby_ws_ensure()
{
    if (!vs_online_is_custom() || !vs_lobby_has_code()) return;
    var ws = vs_ws_state();
    if (ws.state == 3 || ws.state == 1) return;
    var code = string(o_st_handle.lobbyCode);
    vs_lobby_log("ws ensure reconnect code=" + code);
    vs_ws_connect("/api/v1/lobbies/" + code + "/ws", vs_online_token());
}

function vs_lobby_ws_retry()
{
    var ws = vs_ws_state();
    ws.retryWait = false;
    vs_lobby_ws_ensure();
}

function vs_lobby_ws_on_drop(_why)
{
    vs_lobby_log("ws drop " + string(_why) + " " + vs_lobby_flags());
    vs_lobby_send_q_clear();
    vs_ws_reset();
    if (!vs_lobby_has_code()) return;
    var ws = vs_ws_state();
    if (variable_struct_exists(ws, "retryWait") && ws.retryWait) return;
    ws.retryWait = true;
    call_later(120, time_source_units_frames, vs_lobby_ws_retry);
}

function vs_lobby_reset()
{
    vs_lobby_log("reset " + vs_lobby_flags());
    vs_lobby_set_create_pending(false);
    if (variable_global_exists("vs_lobby_cb") && is_struct(global.vs_lobby_cb))
    {
        global.vs_lobby_cb.match_busy = false;
        global.vs_lobby_cb.join_busy = false;
    }
    vs_lobby_ops_end();
    vs_lobby_dl_cancel();
    vs_lobby_send_q_clear();
    vs_lobby_fetch_clear();
    vs_lobby_spi_unmark("");
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
    if (instance_exists(obj_multiplayer_lobby) && vs_lobby_browser_active())
        vs_lobby_browser_refresh(true);
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
        if (vs_lobby_pkt_quiet(_type))
        {
            return;
        }
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
        vs_lobby_note_seen(senderId);
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
            vs_lobby_host_sync("recv SendPlayerInfo from=" + senderId, senderId);
            vs_lobby_refresh_ui();
        }
    }
    else if (_op == 1) // text = JSON control message
    {
        var firstCtrl = 0;
        if (buffer_get_size(_payload) > 0)
        {
            firstCtrl = buffer_peek(_payload, 0, buffer_u8);
        }
        if (firstCtrl != 123 && firstCtrl != 91)
        {
            vs_online_on_ws_frame(2, _payload);
            return;
        }
        var text = vs_utf8_from_buffer(_payload);
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
                    // Reconnect must sync again; SPI one-shot would skip otherwise.
                    vs_lobby_spi_unmark(mid);
                    vs_lobby_host_sync("member_joined", mid);
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
                if (!vs_lobby_is_owner()) vs_lobby_ops_end();
                vs_lobby_refresh_ui();
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
