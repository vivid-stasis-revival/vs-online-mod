// ============================================================================
// vs_localcharts.gml — Local Charts manager (home-page entry)
//
// Lists and manages local custom songs in "Custom Songs/" (CSM format):
//   - scans top-level song folders (info.json) and pack folders
//     (songpack_info.json) into a flat, grouped list
//   - checks for server updates by chartId (sha1 diff, reuses the songstore
//     REST layer)
//   - jumps into the song select at a chart's position
//
// This complements the Custom Songs Mod (CSM): CSM turns these folders into
// playable entries in global.song_list + global.song_packs; here we give the
// player a dedicated home-page manager for them.
//
// COMPILER NOTE: Underanalyzer / vsml:
//   - anons do not capture enclosing args/`var` (they become self.<name>)
//   - object-event anons also compile mod GlobalScripts as instance vars
// Cross-callback state travels through global slots or method(self, named_fn).
// ============================================================================

function vs_localcharts_dir()
{
    return vs_songstore_root();
}

// "Custom Songs/xyz/" -> "xyz"
function vs_localcharts_folder_name(_dir)
{
    var d = _dir;
    var pre = vs_localcharts_dir();
    if (string_starts_with(d, pre))
        d = string_copy(d, string_length(pre) + 1, string_length(d));
    if (string_ends_with(d, "/"))
        d = string_copy(d, 1, string_length(d) - 1);
    if (string_ends_with(d, "\\"))
        d = string_copy(d, 1, string_length(d) - 1);
    return d;
}

function vs_localcharts_read_pack(_dir)
{
    var name = vs_localcharts_folder_name(_dir);
    if (file_exists(_dir + "songpack_info.json"))
    {
        var raw = "";
        var f = file_text_open_read(_dir + "songpack_info.json");
        while (!file_text_eof(f))
        {
            raw += file_text_readln(f);
        }
        file_text_close(f);
        try
        {
            var j = json_parse(raw);
            if (j != undefined && variable_struct_exists(j, "name"))
                name = j.name;
        }
        catch (_e) { }
    }
    return { name: name, dir: _dir };
}

// Read one local chart's info.json into a manager row.
// Returns undefined when the folder has no playable chart.
function vs_localcharts_read_info(_dir, _pack)
{
    if (!file_exists(_dir + "info.json")) return undefined;

    var raw = "";
    var f = file_text_open_read(_dir + "info.json");
    while (!file_text_eof(f))
    {
        raw += file_text_readln(f);
    }
    file_text_close(f);

    var j = undefined;
    try { j = json_parse(raw); } catch (_e) { }
    if (j == undefined) return undefined;

    var s =
    {
        pack: _pack,
        chart_id: variable_struct_exists(j, "chart_id") ? j.chart_id : "",
        name: variable_struct_exists(j, "name") ? j.name : "",
        artist: variable_struct_exists(j, "artist") ? j.artist : "",
        chart_path: _dir,
        diffs: [],
        has_encore: false,
        song_id: -1,
        in_select: false,
        tracked: false,
        kind: 0
    };
    if (s.chart_id == "") s.chart_id = vs_localcharts_folder_name(_dir);

    var diffNames = ["OPENING", "MIDDLE", "FINALE", "ENCORE"];
    for (var i = 0; i < 4; i++)
    {
        if (file_exists(_dir + diffNames[i] + ".vsc") || file_exists(_dir + diffNames[i] + ".vsb"))
        {
            array_push(s.diffs, diffNames[i]);
            if (i == 3) s.has_encore = true;
        }
    }
    if (array_length(s.diffs) == 0) return undefined; // folder exists but no chart

    var he = struct_get_fallback(j, "has_encore", false);
    s.has_encore = (he == true || he == 1 || he == "1.0");

    s.song_id = vs_localcharts_song_id_in_list(s.chart_id);
    s.in_select = (s.song_id >= 0);
    s.tracked = vs_dlmgr_tracked(s.chart_id); // was it downloaded by us?
    return s;
}

function vs_localcharts_read_shatter(_dir, _pack)
{
    if (!file_exists(_dir + "shatterinfo.json")) return undefined;

    var raw = "";
    var f = file_text_open_read(_dir + "shatterinfo.json");
    while (!file_text_eof(f))
    {
        raw += file_text_readln(f);
    }
    file_text_close(f);

    var j = undefined;
    try { j = json_parse(raw); } catch (_e) { }
    if (j == undefined) return undefined;

    var diff = variable_struct_exists(j, "difficulty_name") ? string(j.difficulty_name) : "";
    var s =
    {
        pack: _pack,
        chart_id: variable_struct_exists(j, "chart_id") ? j.chart_id : "",
        name: variable_struct_exists(j, "name") ? j.name : "",
        artist: variable_struct_exists(j, "artist") ? j.artist : "",
        chart_path: _dir,
        diffs: (diff != "") ? [diff] : [],
        has_encore: false,
        song_id: -1,
        in_select: false,
        tracked: false,
        kind: 2
    };
    if (s.chart_id == "") s.chart_id = vs_localcharts_folder_name(_dir);
    s.song_id = vs_localcharts_shatter_id_in_list(s.chart_id);
    s.in_select = (s.song_id >= 0);
    s.tracked = vs_dlmgr_tracked(s.chart_id);
    return s;
}

// Scan "Custom Songs/" (top-level songs + pack subfolders) into a flat list
// sorted by pack, then name.
function vs_localcharts_scan()
{
    var out = [];
    vs_songstore_clear_save_songs();
    if (!directory_exists(vs_localcharts_dir())) return out;

    var packs = [];
    var d = file_find_first(vs_localcharts_dir() + "*", 16);
    while (d != "")
    {
        var p = vs_localcharts_dir() + d + "/";
        if (file_exists(p + "info.json"))
        {
            var s = vs_localcharts_read_info(p, "Unpacked");
            if (s != undefined) array_push(out, s);
        }
        else if (file_exists(p + "shatterinfo.json"))
        {
            var sh = vs_localcharts_read_shatter(p, "Shatter");
            if (sh != undefined) array_push(out, sh);
        }
        else if (file_exists(p + "songpack_info.json"))
        {
            array_push(packs, p);
        }
        d = file_find_next();
    }
    file_find_close();

    for (var i = 0; i < array_length(packs); i++)
    {
        var pk = vs_localcharts_read_pack(packs[i]);
        var dd = file_find_first(packs[i] + "*", 16);
        while (dd != "")
        {
            var pp = packs[i] + dd + "/";
            if (file_exists(pp + "info.json"))
            {
                var s2 = vs_localcharts_read_info(pp, pk.name);
                if (s2 != undefined) array_push(out, s2);
            }
            else if (file_exists(pp + "shatterinfo.json"))
            {
                var sh2 = vs_localcharts_read_shatter(pp, pk.name);
                if (sh2 != undefined) array_push(out, sh2);
            }
            dd = file_find_next();
        }
        file_find_close();
    }

    array_sort(out, function(_a, _b)
    {
        var ap = string_lower(_a.pack);
        var bp = string_lower(_b.pack);
        if (ap != bp) return (ap > bp) ? 1 : -1;
        return (string_lower(_a.name) > string_lower(_b.name)) ? 1 : -1;
    });
    return out;
}

// Index of a song with chart_id inside global.song_list (-1 when absent).
function vs_localcharts_song_id_in_list(_chart_id)
{
    if (!variable_global_exists("song_list")) return -1;
    var n = array_length(global.song_list);
    for (var i = 0; i < n; i++)
    {
        var s = global.song_list[i];
        if (s != undefined && variable_struct_exists(s, "chart_id") && s.chart_id == _chart_id)
            return i;
    }
    return -1;
}

function vs_localcharts_shatter_id_in_list(_chart_id)
{
    if (!variable_global_exists("shatter_list")) return -1;
    var n = array_length(global.shatter_list);
    for (var i = 0; i < n; i++)
    {
        var s = global.shatter_list[i];
        if (s != undefined && variable_struct_exists(s, "chart_id") && s.chart_id == _chart_id)
            return i;
    }
    return -1;
}

// Find { pack_index, pos, song_id } of a chart across the current song packs.
// Returns undefined when the chart is not reachable in the select.
function vs_localcharts_pack_pos(_chart_id)
{
    if (!variable_global_exists("song_packs") || !variable_global_exists("song_list")) return undefined;
    for (var p = 0; p < array_length(global.song_packs); p++)
    {
        var pk = global.song_packs[p];
        if (pk == undefined || !variable_struct_exists(pk, "songs") || pk.songs == undefined) continue;
        var m = array_length(pk.songs);
        for (var s = 0; s < m; s++)
        {
            var sid = pk.songs[s];
            if (is_real(sid) && sid >= 0 && sid < array_length(global.song_list))
            {
                var e = global.song_list[sid];
                if (e != undefined && variable_struct_exists(e, "chart_id") && e.chart_id == _chart_id)
                    return { pack_index: p, pos: s, song_id: sid };
            }
        }
    }
    return undefined;
}

// Reload the local song data into the game:
//   - always re-scan (manager list refreshes on its own)
//   - when the Custom Songs Mod is loaded, rebuild global.song_list + packs
//     so freshly downloaded / removed charts take effect in the select.
function vs_localcharts_refresh()
{
    if (variable_global_exists("custom_song_packs"))
    {
        try { load_song_information(); }
        catch (_e) { show_debug_message("VS LocalCharts: song reload failed -> " + string(_e)); }
        try { create_song_packs(); }
        catch (_e2) { show_debug_message("VS LocalCharts: pack rebuild failed -> " + string(_e2)); }
    }
}

// Jump into the song select with a chart focused (used from both the download
// manager's Local tab and any local-chart entry). Returns false when the chart
// is not reachable in the select.
function vs_localcharts_jump(_chart_id)
{
    if (_chart_id == undefined || _chart_id == "") return false;

    // Rebuild packs first so CSM custom packs are present in the same layout
    // the select will rebuild (same create_song_packs -> same indexes).
    if (variable_global_exists("custom_song_packs"))
    {
        try { create_song_packs(); } catch (_e) { }
    }

    var loc = vs_localcharts_pack_pos(_chart_id);
    if (loc == undefined) return false;

    // o_songselect_main already honors force_song_select (finds pack + cursor).
    global.force_song_select = loc.song_id;
    global.last_freeplay_pack = loc.pack_index;
    global.songselect_difficulty = 0;

    if (instance_exists(vs_downloader_browser))
    {
        instance_destroy(vs_downloader_browser);
    }

    audio_stop_all();
    if (instance_exists(o_newmenu_main))
    {
        with (o_newmenu_main)
        {
            transitionToScene(scene_songselect_old, true, 0);
        }
        return true;
    }
    // No menu to hand the transition to — fall back to an instant room change.
    room_goto(scene_songselect_old);
    return true;
}

function vs_localcharts_jump_shatter(_chart_id)
{
    if (_chart_id == undefined || _chart_id == "") return false;

    try { create_shatter_list(); } catch (_e) { }

    var sid = vs_localcharts_shatter_id_in_list(_chart_id);
    if (sid < 0) return false;

    global.force_song_select = sid;

    if (instance_exists(vs_downloader_browser))
    {
        instance_destroy(vs_downloader_browser);
    }

    audio_stop_all();
    if (instance_exists(o_newmenu_main))
    {
        with (o_newmenu_main)
        {
            transitionToScene(scene_songselect_old_shatter, true, 0);
        }
        return true;
    }
    room_goto(scene_songselect_old_shatter);
    return true;
}

// --- boot auto update check ------------------------------------------------
//
// After launching with a custom server + signed-in account, silently diff
// every local chart against the server (one request at a time) and report how
// many need updates. Non-blocking, runs once per session; guests skip it (they
// can't use online features anyway). State lives in global.vs_auto.
function vs_localcharts_auto_check()
{
    if (variable_global_exists("vs_auto_started") && variable_global_get("vs_auto_started"))
    {
        return;
    }
    global.vs_auto_started = true;
    if (!variable_global_exists("vs_auto"))
    {
        global.vs_auto = { list: [], idx: 0, updates: [], done: false, cur: undefined };
    }
    var st = global.vs_auto;
    // Only charts recorded as our downloads (tracked) are checked against the
    // server — a local chart that merely shares the id is not treated as
    // downloadable/updatable content.
    var scanned = vs_localcharts_scan();
    var tr = [];
    for (var i = 0; i < array_length(scanned); i++)
    {
        if (vs_dlmgr_tracked(scanned[i].chart_id))
        {
            array_push(tr, scanned[i]);
        }
    }
    st.list = tr;
    st.idx = 0;
    st.updates = [];
    st.done = false;
    var charts = [];
    for (var j = 0; j < array_length(tr); j++)
    {
        var c = tr[j];
        var diffs = c.diffs;
        var d = 0;
        repeat (array_length(diffs))
        {
            var sha = vs_online_chart_sha1(c.chart_id, diffs[d]);
            if (sha != "")
            {
                array_push(charts, { chartId: c.chart_id, difficulty: vs_online_diff_api(diffs[d]), sha1: sha });
            }
            d++;
        }
    }
    show_debug_message("VS Online: auto update check for " + string(array_length(tr)) + " tracked chart(s), " + string(array_length(charts)) + " file(s)...");
    if (array_length(charts) == 0)
    {
        st.done = true;
        global.vs_updates_available = [];
        return;
    }
    vs_online_post_json("/api/v1/charts/check-updates", { charts: charts }, vs_localcharts_auto_done);
}

function vs_localcharts_auto_done(_ok, _data, _status)
{
    var st = global.vs_auto;
    st.done = true;
    var updates = [];
    if (_ok && _data != undefined && variable_struct_exists(_data, "results") && is_array(_data.results))
    {
        var seen = {};
        var i = 0;
        repeat (array_length(_data.results))
        {
            var r = _data.results[i];
            if (r != undefined && variable_struct_exists(r, "needsUpdate") && r.needsUpdate)
            {
                var cid = r.chartId;
                if (!variable_struct_exists(seen, cid))
                {
                    variable_struct_set(seen, cid, true);
                    var nm = cid;
                    var k = 0;
                    repeat (array_length(st.list))
                    {
                        if (st.list[k].chart_id == cid) { nm = st.list[k].name; break; }
                        k++;
                    }
                    array_push(updates, { chart_id: cid, name: nm, need: 1 });
                }
            }
            i++;
        }
    }
    st.updates = updates;
    global.vs_updates_available = updates;
    show_debug_message("VS Online: auto update check done - " + string(array_length(updates)) + " chart(s) need server updates.");
}
