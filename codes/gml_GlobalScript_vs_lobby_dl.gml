// Lobby missing-chart download: reuse the Chart Downloader progress popup,
// gate Ready / Options until the queued chart is in song_list, and restamp
// SendPlayerInfo so the red D clears for the rest of the room.

function vs_lobby_dl_st()
{
    if (!variable_global_exists("vs_lobby_dl"))
    {
        global.vs_lobby_dl = { open: false, ask: false, looking: false, checking: false, need_upd: false, chartId: "", serverId: "", seq: 0, err: "", qseq: [] };
    }
    if (!variable_struct_exists(global.vs_lobby_dl, "qseq") || !is_array(global.vs_lobby_dl.qseq))
    {
        global.vs_lobby_dl.qseq = [];
    }
    return global.vs_lobby_dl;
}

// HTTP callbacks cannot capture enclosing `var` (vsml compiles those as
// self.seq and crashes on oCoroutineManager). Pair each request with its
// seq through this FIFO — HTTP is already one-in-flight.
function vs_lobby_dl_push_seq()
{
    var st = vs_lobby_dl_st();
    array_push(st.qseq, st.seq);
}

function vs_lobby_dl_pop_seq()
{
    var st = vs_lobby_dl_st();
    if (array_length(st.qseq) <= 0) return -1;
    var seq = st.qseq[0];
    array_delete(st.qseq, 0, 1);
    return seq;
}

function vs_lobby_dl_check_lookup_http(_ok, _data, _status)
{
    vs_lobby_dl_on_check_lookup(vs_lobby_dl_pop_seq(), _ok, _data);
}

function vs_lobby_dl_check_detail_http(_ok, _data, _status)
{
    vs_lobby_dl_on_check_detail(vs_lobby_dl_pop_seq(), _ok, _data);
}

function vs_lobby_dl_lookup_http(_ok, _data, _status)
{
    vs_lobby_dl_on_lookup(vs_lobby_dl_pop_seq(), _ok, _data);
}

function vs_lobby_dl_open()
{
    return vs_lobby_dl_st().open;
}

function vs_lobby_dl_seed_popup(_title, _file)
{
    if (!variable_global_exists("vs_dlmgr_dl"))
    {
        global.vs_dlmgr_dl = { on_done: undefined, need: [], idx: 0, chartId: "", serverId: "", name: "", failed: false, cancel: false, fileGot: 0, fileTotal: 0, fileName: "", err: "" };
    }
    if (vs_dlmgr_is_busy()) return;
    var st = global.vs_dlmgr_dl;
    st.name = _title;
    st.need = [];
    st.idx = 0;
    st.fileName = string(_file);
    st.cancel = false;
    st.err = "";
}

function vs_lobby_dl_close()
{
    var st = vs_lobby_dl_st();
    st.open = false;
    st.ask = false;
    st.looking = false;
    st.err = "";
}

function vs_lobby_dl_fail(_msg)
{
    var st = vs_lobby_dl_st();
    st.looking = false;
    st.ask = false;
    st.err = string(_msg);
    st.open = true;
    vs_lobby_dl_seed_popup("Download failed", st.err);
    vs_lobby_log("dl fail chart=" + string(st.chartId) + " " + st.err);
}

function vs_lobby_dl_cancel()
{
    var st = vs_lobby_dl_st();
    st.seq += 1;
    st.looking = false;
    st.checking = false;
    st.ask = false;
    if (vs_dlmgr_is_busy() && string(global.vs_dlmgr_dl.chartId) == string(st.chartId))
    {
        vs_dlmgr_cancel();
        vs_lobby_log("dl cancel chart=" + string(st.chartId));
    }
    vs_lobby_dl_close();
}

function vs_lobby_dl_on_queue()
{
    var st = vs_lobby_dl_st();
    var cid = vs_lobby_queued_chart_id();
    if (st.open && (cid == "" || string(st.chartId) != string(cid)))
    {
        vs_lobby_dl_cancel();
    }
    vs_lobby_dl_arm_check();
}

function vs_lobby_dl_unready()
{
    if (!instance_exists(obj_multiplayer_lobby)) return;
    with (obj_multiplayer_lobby)
    {
        if (!isReady) return;
        isReady = false;
        send_packet(SendReadyPacket, false);
        if (variable_instance_exists(self, "countdownTimer") && countdownTimer != undefined)
        {
            cancelCountdown();
        }
    }
}

function vs_lobby_dl_arm_check()
{
    if (!vs_online_is_custom()) return;
    var st = vs_lobby_dl_st();
    if (st.open) return;
    st.need_upd = false;
    st.checking = false;
    st.serverId = "";
    var cid = vs_lobby_queued_chart_id();
    if (cid == "" || vs_lobby_local_missing()) return;
    if (!vs_dlmgr_tracked(cid) || !vs_songstore_has_chart(cid)) return;
    st.seq += 1;
    st.chartId = cid;
    st.checking = true;
    vs_lobby_log("dl check chart=" + cid);
    vs_lobby_dl_push_seq();
    vs_online_get_json("/api/v1/songs?chartId=" + vs_online_url_encode(cid) + "&size=1", false, vs_lobby_dl_check_lookup_http);
}

function vs_lobby_dl_on_check_lookup(_seq, _ok, _data)
{
    var st = vs_lobby_dl_st();
    if (_seq != st.seq) return;
    var sid = vs_lobby_dl_catalog_id(_ok, _data, st.chartId);
    if (sid == "")
    {
        st.checking = false;
        vs_lobby_log("dl check skip not on server chart=" + st.chartId);
        return;
    }
    st.serverId = sid;
    vs_lobby_dl_push_seq();
    vs_online_get_json("/api/v1/songs/" + sid, false, vs_lobby_dl_check_detail_http);
}

function vs_lobby_dl_on_check_detail(_seq, _ok, _data)
{
    var st = vs_lobby_dl_st();
    if (_seq != st.seq) return;
    st.checking = false;
    var n = 0;
    if (_ok && _data != undefined && variable_struct_exists(_data, "files"))
    {
        n = array_length(vs_songstore_diff(_data.files, st.chartId));
    }
    st.need_upd = n > 0;
    vs_lobby_log("dl check chart=" + st.chartId + (st.need_upd ? (" UPDATE files=" + string(n)) : " current"));
    send_packet(SendPlayerInfoPacket);
    if (st.need_upd) vs_lobby_dl_unready();
    if (!st.open) return;
    if (st.ask)
    {
        if (!st.need_upd) vs_lobby_dl_close();
        return;
    }
    if (st.need_upd) vs_lobby_dl_begin(st.chartId);
    else vs_lobby_dl_close();
}

function vs_lobby_dl_catalog_id(_ok, _data, _cid)
{
    if (!_ok || _data == undefined) return "";
    if (!variable_struct_exists(_data, "songs") || !is_array(_data.songs)) return "";
    var items = _data.songs;
    var i = 0;
    repeat (array_length(items))
    {
        var it = items[i];
        if (it != undefined && variable_struct_exists(it, "chartId") && string(it.chartId) == string(_cid))
        {
            return variable_struct_exists(it, "id") ? string(it.id) : "";
        }
        i++;
    }
    if (array_length(items) > 0 && items[0] != undefined && variable_struct_exists(items[0], "id"))
    {
        return string(items[0].id);
    }
    return "";
}

function vs_lobby_dl_show_ask(_cid)
{
    var st = vs_lobby_dl_st();
    st.open = true;
    st.ask = true;
    st.err = "";
    st.chartId = string(_cid);
}

function vs_lobby_dl_accept()
{
    var st = vs_lobby_dl_st();
    st.ask = false;
    var cid = vs_lobby_queued_chart_id();
    if (cid == "") cid = st.chartId;
    if (st.checking && string(st.chartId) == string(cid))
    {
        st.open = true;
        vs_lobby_dl_seed_popup("Checking", cid);
        return;
    }
    vs_lobby_dl_begin(cid);
}

function vs_lobby_dl_prompt()
{
    return vs_lobby_dl_prompt_ex(true);
}

function vs_lobby_dl_go()
{
    vs_lobby_dl_prompt_ex(false);
}

function vs_lobby_dl_prompt_ex(_ask)
{
    if (!vs_online_is_custom()) return false;
    var cid = vs_lobby_queued_chart_id();
    var st = vs_lobby_dl_st();
    if (st.open && !st.ask && (cid == "" || string(st.chartId) == string(cid)))
    {
        return true;
    }
    if (st.checking && string(st.chartId) == string(cid))
    {
        if (_ask) vs_lobby_dl_show_ask(cid);
        else vs_lobby_dl_accept();
        return true;
    }
    if (!vs_lobby_local_need_dl()) return false;
    if (st.open && st.ask && (cid == "" || string(st.chartId) == string(cid)))
    {
        if (!_ask) vs_lobby_dl_accept();
        return true;
    }
    if (_ask) vs_lobby_dl_show_ask(cid);
    else vs_lobby_dl_begin(cid);
    return true;
}

function vs_lobby_dl_block_options()
{
    return vs_lobby_dl_prompt();
}

function vs_lobby_dl_begin(_cid)
{
    var st = vs_lobby_dl_st();
    st.seq += 1;
    st.chartId = string(_cid);
    st.err = "";
    st.open = true;
    st.ask = false;
    st.looking = false;
    if (st.chartId == "")
    {
        vs_lobby_dl_fail("no chart id");
        return;
    }
    if (vs_lobby_dl_try_local(st.chartId))
    {
        vs_lobby_dl_close();
        vs_lobby_dl_arm_check();
        return;
    }
    if (vs_songstore_has_chart(st.chartId) && !vs_dlmgr_tracked(st.chartId))
    {
        vs_lobby_dl_fail("local chart");
        return;
    }
    if (vs_dlmgr_is_busy())
    {
        if (string(global.vs_dlmgr_dl.chartId) == st.chartId)
        {
            return;
        }
        vs_lobby_dl_fail("another download");
        return;
    }
    st.looking = true;
    vs_lobby_dl_seed_popup("Looking up", st.chartId);
    vs_lobby_log("dl lookup chart=" + st.chartId);
    vs_lobby_dl_push_seq();
    vs_online_get_json("/api/v1/songs?chartId=" + vs_online_url_encode(st.chartId) + "&size=1", false, vs_lobby_dl_lookup_http);
}

function vs_lobby_dl_try_local(_cid)
{
    if (vs_lobby_dl_st().need_upd) return false;
    if (!vs_songstore_has_chart(_cid)) return false;
    vs_localcharts_refresh();
    vs_lobby_resolve_queued_songs();
    send_packet(SendPlayerInfoPacket);
    return !vs_lobby_local_missing();
}

function vs_lobby_dl_on_lookup(_seq, _ok, _data)
{
    var st = vs_lobby_dl_st();
    if (_seq != st.seq || !st.open) return;
    st.looking = false;
    var sid = vs_lobby_dl_catalog_id(_ok, _data, st.chartId);
    if (sid == "")
    {
        vs_lobby_dl_fail("not on server");
        return;
    }
    if (vs_dlmgr_is_busy())
    {
        if (string(global.vs_dlmgr_dl.chartId) == st.chartId) return;
        vs_lobby_dl_fail("another download");
        return;
    }
    vs_lobby_log("dl start chart=" + st.chartId + " song=" + sid);
    vs_dlmgr_download(sid, st.chartId, 0, vs_lobby_dl_on_done);
}

function vs_lobby_dl_on_done(_ok)
{
    var st = vs_lobby_dl_st();
    if (!st.open) return;
    if (!_ok)
    {
        if (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel)
        {
            vs_lobby_dl_close();
            return;
        }
        var why = "download failed";
        if (variable_global_exists("vs_dlmgr_dl") && variable_struct_exists(global.vs_dlmgr_dl, "err") && global.vs_dlmgr_dl.err != "")
        {
            why = string(global.vs_dlmgr_dl.err);
        }
        vs_lobby_dl_fail(why);
        return;
    }
    vs_localcharts_refresh();
    vs_lobby_resolve_queued_songs();
    st.need_upd = false;
    send_packet(SendPlayerInfoPacket);
    vs_lobby_log("dl ok chart=" + st.chartId + " songId=" + string(vs_online_song_id_from_chart(st.chartId)));
    vs_lobby_dl_close();
    play_se(sfx_songsel_beginsong);
}

function vs_lobby_dl_step()
{
    if (!vs_lobby_dl_open()) return false;
    var st = vs_lobby_dl_st();
    var cancel = keyboard_check_pressed(vk_escape);
    if (variable_global_exists("menu_cancel") && keyboard_check_pressed(global.menu_cancel)) cancel = true;
    if (input_check_pressed(5)) cancel = true;
    if (st.ask)
    {
        var ok = input_check_pressed(4) || keyboard_check_pressed(vk_enter);
        if (ok)
        {
            play_se(sfx_songsel_select);
            vs_lobby_dl_accept();
        }
        else if (cancel)
        {
            play_se(sfx_songsel_select);
            vs_lobby_dl_close();
        }
        return true;
    }
    if (cancel)
    {
        play_se(sfx_songsel_select);
        vs_lobby_dl_cancel();
    }
    return true;
}

function vs_lobby_dl_ask_name()
{
    if (vs_lobby_has_queued_song())
    {
        var q = o_st_handle.songQueue[0];
        var song = (q != undefined && variable_struct_exists(q, "songId")) ? vs_online_song_from_id(q.songId) : undefined;
        if (song != undefined)
        {
            var d = variable_struct_exists(q, "difficulty") ? q.difficulty : 0;
            var nm = song_get_info(song, "name", d);
            if (nm != undefined && string(nm) != "") return string(nm);
            if (variable_struct_exists(song, "name")) return string(song.name);
        }
    }
    var cid = vs_lobby_queued_chart_id();
    if (cid != "") return cid;
    return "this chart";
}

function vs_lobby_dl_draw_ask()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pw = min(220, max(80, cw - 8));
    var ph = min(78, max(48, ch - 8));
    var px = (cw - pw) / 2;
    var py = (ch - ph) / 2;
    draw_set_alpha(0.55);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);
    draw_set_color(c_black);
    draw_rectangle(px - 2, py - 2, px + pw + 2, py + ph + 2, false);
    draw_set_color(c_white);
    draw_rectangle(px, py, px + pw, py + ph, true);
    var title = vs_lobby_local_missing() ? "Download this chart?" : "Update this chart?";
    var name = vs_lobby_dl_ask_name();
    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_center);
    draw_set_color(c_aqua);
    draw_text(px + pw / 2, py + 8, vs_dlbr_clip_text(title, pw - 12));
    draw_set_font(global.default_font);
    draw_set_color(c_white);
    draw_text(px + pw / 2, py + 28, vs_dlbr_clip_text(name, pw - 12));
    draw_set_color(c_yellow);
    draw_text(px + pw / 2, py + 52, vs_dlbr_clip_text("CONFIRM / ESCAPE", pw - 12));
    draw_set_halign(fa_left);
    draw_set_color(c_white);
}

function vs_lobby_dl_draw()
{
    if (!vs_lobby_dl_open()) return;
    if (vs_lobby_dl_st().ask) vs_lobby_dl_draw_ask();
    else vs_dlbr_draw_dl_popup();
}

function vs_lobby_dl_menu_find(_acts, _cb)
{
    if (_acts == undefined || !is_array(_acts)) return -1;
    var i = 0;
    repeat (array_length(_acts))
    {
        if (_acts[i] != undefined && _acts[i].callback == _cb) return i;
        i++;
    }
    return -1;
}

function vs_lobby_dl_menu_apply(_acts)
{
    if (_acts == undefined || !is_array(_acts)) return;
    var want = vs_online_is_custom() && (vs_lobby_local_need_dl() || vs_lobby_dl_open());
    var have = vs_lobby_dl_menu_find(_acts, "downloadchart");
    var lab = vs_lobby_local_missing() ? "Download" : "Update";
    if (want)
    {
        if (have >= 0)
        {
            _acts[have].txt = lab;
            return;
        }
        var slot = 1;
        if (vs_lobby_dl_menu_find(_acts, "readytoggle") >= 0)
        {
            slot = vs_lobby_dl_menu_find(_acts, "readytoggle") + 1;
        }
        else
        {
            var start = vs_lobby_dl_menu_find(_acts, "startgame");
            slot = (start >= 0) ? start : array_length(_acts);
        }
        array_insert(_acts, slot, { txt: lab, callback: "downloadchart" });
    }
    else if (have >= 0)
    {
        array_delete(_acts, have, 1);
        if (instance_exists(obj_multiplayer_lobby) && obj_multiplayer_lobby.cursor_pos >= array_length(_acts))
        {
            obj_multiplayer_lobby.cursor_pos = max(0, array_length(_acts) - 1);
        }
    }
}

function vs_lobby_dl_menu_sync()
{
    if (!instance_exists(obj_multiplayer_lobby)) return;
    with (obj_multiplayer_lobby)
    {
        vs_lobby_dl_menu_apply(menu_actions_player);
        vs_lobby_dl_menu_apply(menu_actions_host);
    }
}
