// Lobby missing-chart download: reuse the Chart Downloader progress popup,
// gate Ready / Options until the queued chart is in song_list, and restamp
// SendPlayerInfo so the red D clears for the rest of the room.

function vs_lobby_dl_st()
{
    if (!variable_global_exists("vs_lobby_dl"))
    {
        global.vs_lobby_dl = { open: false, looking: false, chartId: "", seq: 0, err: "" };
    }
    return global.vs_lobby_dl;
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
    st.looking = false;
    st.err = "";
}

function vs_lobby_dl_fail(_msg)
{
    var st = vs_lobby_dl_st();
    st.looking = false;
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
    if (!st.open) return;
    var cid = vs_lobby_queued_chart_id();
    if (cid == "" || string(st.chartId) != string(cid))
    {
        vs_lobby_dl_cancel();
    }
}

function vs_lobby_dl_prompt()
{
    if (!vs_online_is_custom()) return false;
    if (!vs_lobby_local_need_dl()) return false;
    var cid = vs_lobby_queued_chart_id();
    var st = vs_lobby_dl_st();
    if (st.open && (cid == "" || string(st.chartId) == string(cid)))
    {
        return true;
    }
    vs_lobby_dl_begin(cid);
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
    st.looking = false;
    if (st.chartId == "")
    {
        vs_lobby_dl_fail("no chart id");
        return;
    }
    if (vs_lobby_dl_try_local(st.chartId))
    {
        vs_lobby_dl_close();
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
    var seq = st.seq;
    st.looking = true;
    vs_lobby_dl_seed_popup("Looking up", st.chartId);
    vs_lobby_log("dl lookup chart=" + st.chartId);
    vs_online_get_json("/api/v1/songs?chartId=" + vs_online_url_encode(st.chartId) + "&size=1", false,
        function(_ok, _data, _status)
        {
            vs_lobby_dl_on_lookup(seq, _ok, _data);
        });
}

function vs_lobby_dl_try_local(_cid)
{
    if (!vs_songstore_has_chart(_cid)) return false;
    vs_localcharts_refresh();
    vs_lobby_resolve_queued_songs();
    send_packet(SendPlayerInfoPacket);
    return !vs_lobby_local_need_dl();
}

function vs_lobby_dl_on_lookup(_seq, _ok, _data)
{
    var st = vs_lobby_dl_st();
    if (_seq != st.seq || !st.open) return;
    st.looking = false;
    var sid = "";
    if (_ok && _data != undefined && variable_struct_exists(_data, "songs") && is_array(_data.songs))
    {
        var items = _data.songs;
        var i = 0;
        repeat (array_length(items))
        {
            var it = items[i];
            if (it != undefined && variable_struct_exists(it, "chartId") && string(it.chartId) == st.chartId)
            {
                sid = variable_struct_exists(it, "id") ? string(it.id) : "";
                break;
            }
            i++;
        }
        if (sid == "" && array_length(items) > 0 && items[0] != undefined && variable_struct_exists(items[0], "id"))
        {
            sid = string(items[0].id);
        }
    }
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
    vs_dlmgr_download(sid, st.chartId, 0, function(_ok2)
    {
        vs_lobby_dl_on_done(_ok2);
    });
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
    send_packet(SendPlayerInfoPacket);
    vs_lobby_log("dl ok chart=" + st.chartId + " songId=" + string(vs_online_song_id_from_chart(st.chartId)));
    vs_lobby_dl_close();
    play_se(sfx_songsel_beginsong);
}

function vs_lobby_dl_step()
{
    if (!vs_lobby_dl_open()) return false;
    var cancel = keyboard_check_pressed(vk_escape);
    if (variable_global_exists("menu_cancel") && keyboard_check_pressed(global.menu_cancel)) cancel = true;
    if (input_check_pressed(5)) cancel = true;
    if (cancel)
    {
        play_se(sfx_songsel_select);
        vs_lobby_dl_cancel();
    }
    return true;
}

function vs_lobby_dl_draw()
{
    if (!vs_lobby_dl_open()) return;
    vs_dlbr_draw_dl_popup();
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
    if (want)
    {
        if (have >= 0) return;
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
        array_insert(_acts, slot, { txt: "Download", callback: "downloadchart" });
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
