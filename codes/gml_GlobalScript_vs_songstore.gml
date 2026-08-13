// ============================================================================
// vs_songstore.gml — custom-song store client (vs-server-go /songs)
//
// Data layer for the "Web Charts" virtual pack: search + paginate the server
// catalog, diff per-file sha1 against the local Custom Songs/ folder, download
// only changed files, then trigger CSM's CustomSongReader() to rescan.
//
// Downloads land in "Custom Songs/<chartId>/" (the folder must match chart_id,
// per the Custom Songs Mod format).
// ============================================================================

function vs_songstore_local_dir(_chartId)
{
    return "Custom Songs/" + _chartId + "/";
}

// --- catalog ---------------------------------------------------------------

// GET /songs?q=&page=&size= -> {songs, total}. _on_done(ok, data|undefined).
function vs_songstore_list(_query, _page, _on_done)
{
    var q = "";
    if (_query != undefined && _query != "")
    {
        q = "&q=" + _query;
    }
    vs_online_get_json("/api/v1/songs?page=" + string(max(_page, 1)) + "&size=50" + q, false,
        function(ok, data, status)
        {
            _on_done(ok, data);
        });
}

// GET /songs/:id -> full detail (charts[] + files[] with per-file sha1).
function vs_songstore_detail(_songId, _on_done)
{
    vs_online_get_json("/api/v1/songs/" + _songId, false,
        function(ok, data, status)
        {
            _on_done(ok, data);
        });
}

// --- local state (scan Custom Songs/, no manifest file) --------------------

// Downloaded-ness by folder existence (cheap, no network).
function vs_songstore_downloaded(_chartId)
{
    return directory_exists(vs_songstore_local_dir(_chartId));
}

// Diff the server files[] against local files; returns [{name,url,localPath}]
// that are missing or whose sha1 changed.
function vs_songstore_diff(_files, _chartId)
{
    var need = [];
    if (_files == undefined) return need;
    var dir = vs_songstore_local_dir(_chartId);
    for (var i = 0; i < array_length(_files); i++)
    {
        var f = _files[i];
        var localPath = dir + f.name;
        var localHash = file_exists(localPath) ? sha1_file(localPath) : "";
        if (string_lower(localHash) != string_lower(f.sha1))
        {
            array_push(need, { name: f.name, url: f.url, localPath: localPath });
        }
    }
    return need;
}

// --- download --------------------------------------------------------------

// Download one file with http_get_file, awaiting the http async event.
function vs_songstore_download_file(_url, _localPath, _on_done)
{
    __CoroutineBegin(function()
    {
        var rid = http_get_file(_url, _localPath);
        __CoroutineAwaitAsync("http", function()
        {
            if (async_load[? "id"] != rid)
            {
                return false;
            }
            _on_done(file_exists(_localPath), _localPath);
            return true;
        });
    });
    __CoroutineEnd();
}

// Download a whole song: fetch detail, diff, then pull changed files in order,
// and finally rescan via CustomSongReader() (guarded for CSM not being present).
function vs_songstore_download(_songId, _chartId, _on_done)
{
    vs_songstore_detail(_songId, function(ok, song)
    {
        if (!ok || song == undefined)
        {
            if (_on_done != undefined) { _on_done(false); }
            return;
        }
        var dir = vs_songstore_local_dir(_chartId);
        if (!directory_exists(dir)) { directory_create(dir); }
        var need = vs_songstore_diff(song.files, _chartId);
        if (array_length(need) == 0)
        {
            vs_songstore_after_download(_on_done);
            return;
        }
        vs_songstore_download_chain(need, 0, _on_done);
    });
}

function vs_songstore_download_chain(_need, _idx, _on_done)
{
    if (_idx >= array_length(_need))
    {
        vs_songstore_after_download(_on_done);
        return;
    }
    var f = _need[_idx];
    vs_songstore_download_file(f.url, f.localPath, function(ok, path)
    {
        show_debug_message("VS Store: " + (ok ? "downloaded " : "FAILED ") + path);
        vs_songstore_download_chain(_need, _idx + 1, _on_done);
    });
}

function vs_songstore_after_download(_on_done)
{
    // Refresh the custom-song list if the Custom Songs Mod is loaded.
    try { CustomSongReader(); } catch (_e) { }
    if (_on_done != undefined) { _on_done(true); }
}

// --- Web Charts virtual pack ----------------------------------------------

// Inject the "Web Charts" pack into global.song_packs (idempotent). Called at
// the end of create_song_packs() so it survives every rebuild.
function vs_online_add_web_pack()
{
    if (!vs_online_is_custom()) return;
    var i = 0;
    repeat (array_length(global.song_packs))
    {
        if (variable_struct_exists(global.song_packs[i], "is_vs_web")) return;
        i++;
    }
    array_push(global.song_packs,
    {
        name: "Web Charts",
        songs: [],
        is_vs_web: true,
        color1: 65535,
        color2: 16711935,
        description: "Browse and download custom charts from the server."
    });
}

// Index of the first non-web pack (fallback target when leaving the browser).
function vs_songstore_allsongs_index()
{
    var i = 0;
    repeat (array_length(global.song_packs))
    {
        if (!variable_struct_exists(global.song_packs[i], "is_vs_web")) return i;
        i++;
    }
    return 0;
}
