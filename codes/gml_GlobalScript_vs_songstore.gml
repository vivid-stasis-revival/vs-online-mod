// ============================================================================
// vs_songstore.gml — custom-song store data layer (vs-server-go /songs)
//
// Shared download primitives used by the home-page Chart Downloader:
//   - vs_songstore_detail      fetch a song's full metadata (files[] + sha1)
//   - vs_songstore_diff        sha1-diff the server files[] against local
//   - vs_songstore_download_file  download one file (http_get_file)
//
// Downloads land in "Custom Songs/<chartId>/" (the folder must match chart_id,
// per the Custom Songs Mod format). The old in-song-select "Web Charts" virtual
// pack + browser were removed — the Chart Downloader (vs_dlmgr/vs_downloader_browser)
// is now the single web-chart UI.
// ============================================================================

function vs_songstore_local_dir(_chartId)
{
    return "Custom Songs/" + _chartId + "/";
}

// The Custom Songs Mod keeps every file (info.json, music, jacket, and the
// .vsc/.vsm charts) directly inside the song folder named by chart_id — the
// game's own Example folder has ENCORE.vsc at the root, no "charts/" subfolder.
// The server, however, stores chart files under a "charts/" subfolder and its
// /songs/:id files[] names them "charts/OPENING.vsc" etc. Flatten that prefix
// on download so what we write matches what CSM actually reads.
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

// GET /songs/:id -> full detail (charts[] + files[] with per-file sha1).
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

// Diff the server files[] against local files; returns [{name,url,localPath}]
// that are missing or whose sha1 changed. `need` is empty => up to date.
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

// Download one file with http_get_file, awaiting the http async event.
function vs_songstore_download_file(_url, _localPath, _on_done)
{
    if (!variable_global_exists("vs_dl_q"))
    {
        global.vs_dl_q = [];
        global.vs_dl_busy = false;
        global.vs_dl_state = { rid: -1, url: "", localPath: "", on_done: undefined };
    }
    array_push(global.vs_dl_q, { url: _url, localPath: _localPath, on_done: _on_done });
    vs_songstore_dl_pump();
}

function vs_songstore_dl_pump()
{
    if (global.vs_dl_busy) return;
    if (array_length(global.vs_dl_q) == 0) return;
    global.vs_dl_busy = true;
    var job = global.vs_dl_q[0];
    array_delete(global.vs_dl_q, 0, 1);
    global.vs_dl_state.url = job.url;
    global.vs_dl_state.localPath = job.localPath;
    global.vs_dl_state.on_done = job.on_done;
    __CoroutineBegin(function()
    {
        var st = global.vs_dl_state;
        st.rid = http_get_file(st.url, st.localPath);
        __CoroutineAwaitAsync("http", function()
        {
            var st = global.vs_dl_state;
            if (ds_map_find_value(async_load, "id") != st.rid)
            {
                return false;
            }
            var cb = st.on_done;
            var path = st.localPath;
            st.on_done = undefined;
            global.vs_dl_busy = false;
            if (cb != undefined) { cb(file_exists(path), path); }
            vs_songstore_dl_pump();
            return true;
        });
    });
    __CoroutineEnd();
}
