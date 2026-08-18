// ============================================================================
// vs_dlmgr.gml — Chart Downloader (Web Charts download manager)
//
// Downloads / updates custom charts from the live vs-server-go catalog into
// "Custom Songs/" (CSM format), plus the matching Local tab.
//
//   - browse songs / backstage / shatters (paginated, size=100) with search (?q=)
//   - annotate each row with local state (downloaded / needs update via
//     sha1 diff against the local folder)
//   - single download/update, "check page", and "update page" batch actions
//   - filters: All / Not downloaded / Downloaded / Updates available
//
// This talks to the SAME REST layer as vs_songstore and downloads into the
// SAME folders, so charts picked up here immediately show up for the Custom
// Songs Mod (and vice-versa). The old in-select "Web Charts" pack/browser was
// removed in favour of this manager.
//
// COMPILER NOTE: anonymous functions in loader-injected scripts can't capture
// enclosing arguments / `var` locals (they compile to `self.<name>` reads and
// crash); cross-callback state travels through the dedicated global slots
// below. The browser object drives everything else through its own instances.
// ============================================================================

// GET /api/v1/songs or /shatters?q=&page=&size=100.
// _kind: 0 songs, 1 songs?backstage=1, 2 shatters.
// _on_done(ok, data|undefined).
function vs_dlmgr_list(_query, _page, _kind, _on_done)
{
    if (!variable_global_exists("vs_dlmgr_cb"))
    {
        global.vs_dlmgr_cb = { query: "", page: 1, kind: 0, on_done: undefined };
    }
    global.vs_dlmgr_cb.query = _query;
    global.vs_dlmgr_cb.page = _page;
    global.vs_dlmgr_cb.kind = _kind;
    global.vs_dlmgr_cb.on_done = _on_done;
    vs_online_with_conn(function()
    {
        var kind = global.vs_dlmgr_cb.kind;
        var path = (kind == 2) ? "/api/v1/shatters" : "/api/v1/songs";
        var url = path + "?page=" + string(max(global.vs_dlmgr_cb.page, 1)) + "&size=100";
        var q = global.vs_dlmgr_cb.query;
        if (q != undefined && q != "")
        {
            url += "&q=" + vs_online_url_encode(q);
        }
        if (kind == 1)
        {
            url += "&backstage=1";
        }
        vs_online_get_json(url, false, function(_ok, _data, _status)
        {
            var cb = global.vs_dlmgr_cb.on_done;
            global.vs_dlmgr_cb.on_done = undefined;
            if (cb != undefined) { cb(_ok, _data); }
        });
    });
}

// Is this chart downloaded locally? (folder existence — cheap, no network)
function vs_dlmgr_downloaded(_chartId)
{
    return vs_songstore_has_chart(_chartId);
}

// Full sha1 check of one chart: fetch server detail, diff against the local
// folder. _on_done(ok, need|undefined) where `need` is the array of files
// that are missing or changed (empty array => up to date).
function vs_dlmgr_check(_songId, _chartId, _kind, _on_done)
{
    if (!variable_global_exists("vs_dlmgr_check_cb"))
    {
        global.vs_dlmgr_check_cb = { on_done: undefined };
    }
    global.vs_dlmgr_check_cb.on_done = _on_done;
    global.vs_dlmgr_check_cb.chartId = _chartId;
    vs_songstore_fetch(_kind, _songId, function(_ok, _detail)
    {
        var slot = global.vs_dlmgr_check_cb;
        var cb = slot.on_done;
        var chartId = slot.chartId;
        slot.on_done = undefined;
        if (cb == undefined) return;
        if (!_ok || _detail == undefined)
        {
            cb(false, undefined);
            return;
        }
        cb(true, vs_songstore_diff(_detail.files, chartId));
    });
}

// Human text for a display row's sync state.
function vs_dlmgr_row_status(_r)
{
    if (!_r.downloaded) return _r.chartId + "  -  not downloaded";
    if (!_r.tracked)
    {
        if (_r.checked && _r.need == -3) return _r.chartId + "  -  local chart, differs from server - protected (not overwritten)";
        return _r.chartId + "  -  local (no download record) - not overwritten";
    }
    if (_r.checked && _r.need > 0) return _r.chartId + "  -  UPDATE (" + string(_r.need) + " file" + (_r.need > 1 ? "s" : "") + ")";
    if (_r.checked) return _r.chartId + "  -  up to date";
    return _r.chartId + "  -  downloaded, checking...";
}

// --- download provenance / history ------------------------------------------
//
// How to tell a server-downloaded chart from a locally-made one that merely
// shares the same id:
//   tracked  == the song folder carries a marker (Custom Songs/<id>/.vs_download.json)
//               -> WE downloaded/updated it.
//   folder, untracked == a pre-existing local chart -> protected, never
//               overwritten by a web download.
// A persistent download log also lives at <game dir>/vsonline.downloads.json.

function vs_dlmgr_meta_path(_chartId)
{
    var play = vs_songstore_chart_dir(_chartId);
    if (play != "") return play + ".vs_download.json";
    var dirs = vs_songstore_dir_candidates(_chartId);
    var i = 0;
    repeat (array_length(dirs))
    {
        var p = dirs[i] + ".vs_download.json";
        if (file_exists(p)) return p;
        i++;
    }
    return vs_songstore_local_dir(_chartId) + ".vs_download.json";
}

function vs_dlmgr_tracked(_chartId)
{
    if (_chartId == undefined || _chartId == "") return false;
    return file_exists(vs_dlmgr_meta_path(_chartId));
}

// Write / refresh the per-chart download marker (called after a successful
// download or update). Preserves the first-downloaded timestamp.
function vs_dlmgr_write_meta(_chartId, _serverId, _name)
{
    if (_chartId == undefined || _chartId == "") return;
    var p = vs_dlmgr_meta_path(_chartId);
    var oldDownloadedAt = 0;
    var isNew = true;
    if (file_exists(p))
    {
        var f = file_text_open_read(p);
        var raw = "";
        while (!file_text_eof(f)) { raw += file_text_readln(f); }
        file_text_close(f);
        try
        {
            var j = json_parse(raw);
            if (j != undefined && variable_struct_exists(j, "downloadedAt"))
            {
                oldDownloadedAt = j.downloadedAt;
                isNew = false;
            }
        }
        catch (_e) { }
    }
    var m =
    {
        chartId: _chartId,
        serverId: _serverId,
        name: _name,
        downloadedAt: isNew ? date_current_datetime() : oldDownloadedAt,
        updatedAt: date_current_datetime()
    };
    var fw = file_text_open_write(p);
    file_text_write_string(fw, json_stringify(m));
    file_text_close(fw);
    vs_dlmgr_log(_chartId, _serverId, _name, isNew);
}

// Persistent download history (one entry per chart, most recent wins).
function vs_dlmgr_log(_chartId, _serverId, _name, _isNew)
{
    var path = working_directory + "vsonline.downloads.json";
    var list = [];
    if (file_exists(path))
    {
        var f = file_text_open_read(path);
        var raw = "";
        while (!file_text_eof(f)) { raw += file_text_readln(f); }
        file_text_close(f);
        try
        {
            var j = json_parse(raw);
            if (j != undefined && is_array(j)) { list = j; }
        }
        catch (_e) { }
    }
    var entry =
    {
        chartId: _chartId,
        serverId: _serverId,
        name: _name,
        action: _isNew ? "downloaded" : "updated",
        time: date_current_datetime()
    };
    array_insert(list, 0, entry);
    // keep newest entry per chartId, cap the list
    var seen = ds_map_create();
    var out = [];
    for (var i = 0; i < array_length(list); i++)
    {
        var e = list[i];
        if (e != undefined && !ds_map_exists(seen, e.chartId))
        {
            ds_map_add(seen, e.chartId, true);
            array_push(out, e);
        }
    }
    ds_map_destroy(seen);
    while (array_length(out) > 200) { array_delete(out, array_length(out) - 1, 1); }
    var fw = file_text_open_write(path);
    file_text_write_string(fw, json_stringify(out));
    file_text_close(fw);
}

// Download / update one chart WITHOUT touching CSM's in-memory state:
//   detail -> diff -> create folder -> serial-download changed files.
// CSM is left untouched; the caller refreshes it cleanly afterwards
// (vs_localcharts_refresh -> load_song_information rebuilds song_list once).
// This deliberately does NOT call CustomSongReader(), which appends every
// custom song again into global.song_list (would duplicate entries).
function vs_dlmgr_download(_songId, _chartId, _kind, _on_done)
{
    if (!variable_global_exists("vs_dlmgr_dl"))
    {
        global.vs_dlmgr_dl = { on_done: undefined, need: [], idx: 0, chartId: "", serverId: "", name: "", failed: false, cancel: false, fileGot: 0, fileTotal: 0, fileName: "", err: "" };
    }
    global.vs_dlmgr_dl.on_done = _on_done;
    global.vs_dlmgr_dl.chartId = _chartId;
    global.vs_dlmgr_dl.serverId = _songId;
    global.vs_dlmgr_dl.failed = false;
    global.vs_dlmgr_dl.cancel = false;
    global.vs_dlmgr_dl.fileGot = 0;
    global.vs_dlmgr_dl.fileTotal = 0;
    global.vs_dlmgr_dl.fileName = "";
    global.vs_dlmgr_dl.err = "";
    vs_songstore_fetch(_kind, _songId, function(_ok, _detail)
    {
        var st = global.vs_dlmgr_dl;
        if (st.cancel)
        {
            vs_dlmgr_dl_finish(false);
            return;
        }
        if (!_ok || _detail == undefined)
        {
            vs_songstore_set_err("could not fetch song info");
            var cb = st.on_done;
            st.on_done = undefined;
            if (cb != undefined) { cb(false); }
            return;
        }
        st.name = variable_struct_exists(_detail, "name") ? _detail.name : st.chartId;
        st.need = vs_songstore_diff(_detail.files, st.chartId);
        st.idx = 0;
        if (array_length(st.need) == 0)
        {
            if (vs_songstore_has_chart(st.chartId))
            {
                vs_dlmgr_write_meta(st.chartId, st.serverId, st.name);
                var cb = st.on_done;
                st.on_done = undefined;
                if (cb != undefined) { cb(true); }
                return;
            }
            vs_songstore_set_err("no chart files on server");
            var cb = st.on_done;
            st.on_done = undefined;
            if (cb != undefined) { cb(false); }
            return;
        }
        vs_dlmgr_dl_step();
    });
}

// Serial-download driver for vs_dlmgr_download (state in global.vs_dlmgr_dl).
// On completion writes the per-chart download marker + the history log.
function vs_dlmgr_cancel()
{
    if (!variable_global_exists("vs_dlmgr_dl")) return;
    global.vs_dlmgr_dl.cancel = true;
    global.vs_dlmgr_dl.failed = true;
    vs_songstore_dl_clear();
}

function vs_dlmgr_dl_finish(_ok)
{
    var st = global.vs_dlmgr_dl;
    if (_ok && !st.cancel)
    {
        if (!vs_songstore_has_chart(st.chartId))
        {
            vs_songstore_set_err("files missing after download");
            _ok = false;
            vs_songstore_cleanup_stub(st.chartId);
        }
        else vs_dlmgr_write_meta(st.chartId, st.serverId, st.name);
    }
    else
    {
        vs_songstore_cleanup_stub(st.chartId);
    }
    var cb = st.on_done;
    st.on_done = undefined;
    if (cb != undefined) { cb(_ok && !st.cancel); }
}

function vs_dlmgr_dl_pkg_done(_ok, _path)
{
    var st = global.vs_dlmgr_dl;
    if (st.cancel)
    {
        vs_dlmgr_dl_finish(false);
        return;
    }
    if (!_ok)
    {
        st.failed = true;
        if (st.err == "") vs_songstore_set_err("package download failed");
    }
    vs_dlmgr_dl_finish(_ok);
}

function vs_dlmgr_dl_file_done(_ok, _path)
{
    var st2 = global.vs_dlmgr_dl;
    if (st2.cancel)
    {
        if (_path != undefined && file_exists(_path)) file_delete(_path);
        vs_dlmgr_dl_finish(false);
        return;
    }
    if (!_ok)
    {
        st2.failed = true;
        show_debug_message("VS DLMGR: download failed -> " + string(_path));
    }
    st2.idx++;
    vs_dlmgr_dl_step();
}

function vs_dlmgr_dl_step()
{
    var st = global.vs_dlmgr_dl;
    if (st.cancel)
    {
        vs_dlmgr_dl_finish(false);
        return;
    }
    if (st.idx >= array_length(st.need))
    {
        vs_dlmgr_dl_finish(!st.failed);
        return;
    }
    var f = st.need[st.idx];
    st.fileName = vs_songstore_flatten_name(f.name);
    st.fileGot = 0;
    st.fileTotal = 0;
    vs_songstore_download_file(f.url, f.localPath, vs_dlmgr_dl_file_done);
}

function vs_dlmgr_prog_frac()
{
    if (!variable_global_exists("vs_dlmgr_dl")) return 0;
    var st = global.vs_dlmgr_dl;
    var n = array_length(st.need);
    if (n <= 0) return 0;
    var part = 0;
    if (st.fileTotal > 0)
    {
        part = st.fileGot / st.fileTotal;
        if (part < 0) part = 0;
        if (part > 1) part = 1;
    }
    var p = (st.idx + part) / n;
    if (p < 0) p = 0;
    if (p > 1) p = 1;
    return p;
}

// Filter names for the F key cycle.
function vs_dlmgr_filter_name(_f)
{
    switch (_f)
    {
        case 0: return "All";
        case 1: return "Not downloaded";
        case 2: return "Downloaded";
        case 3: return "Updates available";
    }
    return "?";
}
