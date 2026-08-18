// ============================================================================
// vs_songstore.gml — custom-song store data layer (vs-server-go /songs)
//
// Shared download primitives used by the home-page Chart Downloader:
//   - vs_songstore_detail      fetch a song's full metadata (files[] + sha1)
//   - vs_songstore_diff        sha1-diff the server files[] against local
//   - vs_songstore_download_file  download one file (http_get_file)
//
// File HTTP is handled on the official HTTP event (vs_http_on_async also
// calls vs_songstore_on_http). http_get_file is started on the next frame —
// starting it from inside the REST completion callback never fired done.
// ============================================================================

function vs_songstore_local_dir(_chartId)
{
    return "Custom Songs/" + _chartId + "/";
}

function vs_songstore_flatten_name(_name)
{
    if (_name == undefined) return "";
    var n = string_replace_all(string(_name), "\\", "/");
    n = string_replace(n, "charts/", "");
    while (string_pos("/", n) > 0)
    {
        n = string_copy(n, string_pos("/", n) + 1, string_length(n));
    }
    if (n == "" || n == "." || n == ".." || string_pos("..", n) > 0)
    {
        return "";
    }
    return n;
}

function vs_songstore_detail(_songId, _on_done)
{
    if (!variable_global_exists("vs_store_detail_cb"))
    {
        global.vs_store_detail_cb = { on_done: undefined };
    }
    global.vs_store_detail_cb.on_done = _on_done;
    vs_online_get_json("/api/v1/songs/" + _songId, false,
        function(_ok, _data, _status)
        {
            var cb = global.vs_store_detail_cb.on_done;
            global.vs_store_detail_cb.on_done = undefined;
            if (cb != undefined) { cb(_ok, _data); }
        });
}

function vs_songstore_diff(_files, _chartId)
{
    var need = [];
    if (_files == undefined) return need;
    var dir = vs_songstore_local_dir(_chartId);
    for (var i = 0; i < array_length(_files); i++)
    {
        var f = _files[i];
        var flat = vs_songstore_flatten_name(f.name);
        if (flat == "")
        {
            show_debug_message("VS Songstore: skip unsafe file name -> " + string(f.name));
            continue;
        }
        var localPath = dir + flat;
        var localHash = file_exists(localPath) ? sha1_file(localPath) : "";
        if (string_lower(localHash) != string_lower(f.sha1))
        {
            array_push(need, { name: f.name, url: f.url, localPath: localPath });
        }
    }
    return need;
}

function vs_songstore_abs_url(_url)
{
    if (_url == undefined) return "";
    var u = string(_url);
    if (u == "") return "";
    var marker = "/uploads/";
    var p = string_pos(marker, u);
    if (p <= 0)
    {
        marker = "/api/";
        p = string_pos(marker, u);
    }
    if (p > 0)
    {
        u = vs_online_server_url() + string_copy(u, p, string_length(u));
    }
    else if (string_pos("http://", u) != 1 && string_pos("https://", u) != 1)
    {
        if (string_copy(u, 1, 1) != "/") u = "/" + u;
        u = vs_online_server_url() + u;
    }
    return string_replace_all(u, " ", "%20");
}

function vs_songstore_dl_init()
{
    if (!variable_global_exists("vs_dl_q"))
    {
        global.vs_dl_q = [];
        global.vs_dl_busy = false;
        global.vs_dl_scheduled = false;
        global.vs_dl_state = { rid: -1, gen: 0, url: "", localPath: "", tmpPath: "vsonline_dl.bin", on_done: undefined, got: 0, total: 0 };
    }
}

function vs_songstore_download_file(_url, _localPath, _on_done)
{
    vs_songstore_dl_init();
    array_push(global.vs_dl_q, { url: _url, localPath: _localPath, on_done: _on_done });
    vs_songstore_dl_schedule();
}

function vs_songstore_dl_schedule()
{
    vs_songstore_dl_init();
    if (global.vs_dl_scheduled) return;
    global.vs_dl_scheduled = true;
    call_later(1, time_source_units_frames, vs_songstore_dl_on_later);
}

function vs_songstore_dl_on_later()
{
    vs_songstore_dl_init();
    global.vs_dl_scheduled = false;
    vs_songstore_dl_pump();
}

function vs_songstore_dl_clear()
{
    vs_songstore_dl_init();
    global.vs_dl_q = [];
    if (global.vs_dl_busy)
    {
        var tmp = global.vs_dl_state.tmpPath;
        if (tmp != "" && file_exists(tmp)) file_delete(tmp);
        vs_songstore_dl_finish(false);
    }
}

function vs_songstore_dl_pump()
{
    vs_songstore_dl_init();
    if (global.vs_dl_busy) return;
    if (array_length(global.vs_dl_q) == 0) return;
    if (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel)
    {
        global.vs_dl_q = [];
        return;
    }
    global.vs_dl_busy = true;
    var job = global.vs_dl_q[0];
    array_delete(global.vs_dl_q, 0, 1);
    if (!variable_global_exists("vs_dl_gen"))
    {
        global.vs_dl_gen = 0;
        global.vs_dl_to = [];
    }
    global.vs_dl_gen += 1;
    var url = vs_songstore_abs_url(job.url);
    var tmp = "vsonline_dl_" + string(global.vs_dl_gen) + ".bin";
    if (file_exists(tmp)) file_delete(tmp);
    global.vs_dl_state.url = url;
    global.vs_dl_state.localPath = job.localPath;
    global.vs_dl_state.tmpPath = tmp;
    global.vs_dl_state.on_done = job.on_done;
    global.vs_dl_state.got = 0;
    global.vs_dl_state.total = 0;
    global.vs_dl_state.gen = global.vs_dl_gen;
    global.vs_dl_state.rid = http_get_file(url, tmp);
    if (global.vs_dl_state.rid == undefined || global.vs_dl_state.rid < 0)
    {
        show_debug_message("VS DL: http_get_file failed " + url);
        vs_songstore_dl_finish(false);
        return;
    }
    array_push(global.vs_dl_to, global.vs_dl_state.gen);
    call_later(60 * 300, time_source_units_frames, vs_songstore_dl_on_timeout);
    show_debug_message("VS DL: start " + string(job.localPath) + " url=" + url + " rid=" + string(global.vs_dl_state.rid));
}

function vs_songstore_dl_on_timeout()
{
    vs_songstore_dl_init();
    if (!variable_global_exists("vs_dl_to") || array_length(global.vs_dl_to) == 0) return;
    var g = global.vs_dl_to[0];
    array_delete(global.vs_dl_to, 0, 1);
    if (!global.vs_dl_busy) return;
    var st = global.vs_dl_state;
    if (st.gen != g) return;
    show_debug_message("VS DL: timeout " + string(st.localPath) + " url=" + string(st.url));
    var tmp = st.tmpPath;
    if (tmp != "" && file_exists(tmp)) file_delete(tmp);
    vs_songstore_dl_finish(false);
}

function vs_songstore_dl_commit(_ok)
{
    var st = global.vs_dl_state;
    var tmp = st.tmpPath;
    var dest = st.localPath;
    if (_ok)
    {
        if (tmp != "" && file_exists(tmp))
        {
            if (file_exists(dest)) file_delete(dest);
            file_copy(tmp, dest);
            file_delete(tmp);
        }
        _ok = file_exists(dest);
    }
    else if (tmp != "" && file_exists(tmp))
    {
        file_delete(tmp);
    }
    return _ok;
}

function vs_songstore_dl_finish(_ok)
{
    vs_songstore_dl_init();
    var st = global.vs_dl_state;
    var cb = st.on_done;
    var path = st.localPath;
    _ok = vs_songstore_dl_commit(_ok);
    st.on_done = undefined;
    st.rid = -1;
    st.gen = 0;
    global.vs_dl_busy = false;
    if (cb != undefined) { cb(_ok, path); }
    vs_songstore_dl_schedule();
}

function vs_songstore_on_http()
{
    if (!variable_global_exists("vs_dl_busy") || !global.vs_dl_busy) return;
    var st = global.vs_dl_state;
    if (st == undefined || st.rid < 0) return;
    if (async_load == -1) return;
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || string(rid) != string(st.rid)) return;
    var gmStatus = ds_map_find_value(async_load, "status");
    var got = ds_map_find_value(async_load, "sizeDownloaded");
    var tot = ds_map_find_value(async_load, "contentLength");
    if (got != undefined) st.got = real(got);
    if (tot != undefined) st.total = real(tot);
    if (variable_global_exists("vs_dlmgr_dl"))
    {
        global.vs_dlmgr_dl.fileGot = st.got;
        global.vs_dlmgr_dl.fileTotal = st.total;
    }
    var doneProg = (st.total > 0 && st.got >= st.total);
    if (gmStatus == 1 && !doneProg)
    {
        return;
    }
    var httpStatus = ds_map_find_value(async_load, "http_status");
    var httpOk = (httpStatus == undefined || (httpStatus >= 200 && httpStatus < 300));
    var ok = ((gmStatus >= 0) || doneProg) && httpOk;
    if (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel)
    {
        ok = false;
    }
    show_debug_message("VS DL: done " + string(st.localPath) + " ok=" + string(ok) + " http=" + string(httpStatus) + " st=" + string(gmStatus));
    vs_songstore_dl_finish(ok);
}
