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
// Custom songs are loaded by vs_csm.gml (CustomSongReader) into
// global.song_list + global.song_packs. This file is the home-page manager.
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
    var d = string_replace_all(string(_dir), "\\", "/");
    while (string_ends_with(d, "/"))
        d = string_copy(d, 1, string_length(d) - 1);
    var slash = string_last_pos("/", d);
    if (slash > 0)
        d = string_copy(d, slash + 1, string_length(d));
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
    if (file_exists(_dir + "shatterinfo.json")) return undefined;
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
            if (i == 3) s.has_encore = "1.0";
        }
    }
    if (array_length(s.diffs) == 0) return undefined; // folder exists but no chart

    var he = struct_get_fallback(j, "has_encore", false);
    if (he == true || he == 1 || he == "1.0" || string_lower(string(he)) == "true") s.has_encore = "1.0";
    var c4 = struct_get_fallback(j, "difficulty_constant_4", 0);
    if (is_real(c4) && c4 > 0) s.has_encore = "1.0";

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

// Scan both Custom Songs roots (save area + Steam) into a flat list
// sorted by pack, then name. Same chart_id keeps the save-area copy.
function vs_localcharts_scan()
{
    var out = [];
    vs_songstore_clear_save_songs();
    var roots = vs_csm_song_roots();
    if (array_length(roots) == 0) return out;

    var seen = {};
    var packs = [];
    var pmap = vs_packmgr_chart_pack_map();
    for (var r = 0; r < array_length(roots); r++)
    {
        var entries = vs_csm_list_subdirs(roots[r]);
        for (var i = 0; i < array_length(entries); i++)
        {
            var e = entries[i];
            var key = string_lower(e.name);
            if (file_exists(e.dir + "shatterinfo.json"))
            {
                if (variable_struct_exists(seen, key)) continue;
                var sh = vs_localcharts_read_shatter(e.dir, "Shatter");
                if (sh != undefined)
                {
                    variable_struct_set(seen, key, true);
                    if (sh.chart_id != "") variable_struct_set(seen, string_lower(sh.chart_id), true);
                    var pk1 = string_lower(string(sh.chart_id));
                    if (sh.pack == "Shatter" && pk1 != "" && variable_struct_exists(pmap, pk1))
                        sh.pack = variable_struct_get(pmap, pk1);
                    array_push(out, sh);
                }
            }
            else if (file_exists(e.dir + "info.json"))
            {
                if (variable_struct_exists(seen, key)) continue;
                var s = vs_localcharts_read_info(e.dir, "Unpacked");
                if (s != undefined)
                {
                    variable_struct_set(seen, key, true);
                    if (s.chart_id != "") variable_struct_set(seen, string_lower(s.chart_id), true);
                    var pk0 = string_lower(string(s.chart_id));
                    if (s.pack == "Unpacked" && pk0 != "" && variable_struct_exists(pmap, pk0))
                        s.pack = variable_struct_get(pmap, pk0);
                    array_push(out, s);
                }
            }
            else if (file_exists(e.dir + "songpack_info.json"))
            {
                if (variable_struct_exists(seen, "pack:" + key)) continue;
                variable_struct_set(seen, "pack:" + key, true);
                array_push(packs, e.dir);
            }
        }
    }

    for (var i = 0; i < array_length(packs); i++)
    {
        var pk = vs_localcharts_read_pack(packs[i]);
        var children = vs_csm_list_subdirs(packs[i]);
        for (var j = 0; j < array_length(children); j++)
        {
            var pp = children[j].dir;
            var ck = string_lower(vs_localcharts_folder_name(packs[i]) + "/" + children[j].name);
            if (file_exists(pp + "shatterinfo.json"))
            {
                if (variable_struct_exists(seen, ck)) continue;
                var sh2 = vs_localcharts_read_shatter(pp, pk.name);
                if (sh2 != undefined)
                {
                    variable_struct_set(seen, ck, true);
                    if (sh2.chart_id != "") variable_struct_set(seen, string_lower(sh2.chart_id), true);
                    array_push(out, sh2);
                }
            }
            else if (file_exists(pp + "info.json"))
            {
                if (variable_struct_exists(seen, ck)) continue;
                var s2 = vs_localcharts_read_info(pp, pk.name);
                if (s2 != undefined)
                {
                    variable_struct_set(seen, ck, true);
                    if (s2.chart_id != "") variable_struct_set(seen, string_lower(s2.chart_id), true);
                    array_push(out, s2);
                }
            }
        }
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
        if (s != undefined && vs_localcharts_chart_matches(s, _chart_id))
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

function vs_localcharts_chart_matches(_song, _chart_id)
{
    if (_song == undefined || _chart_id == undefined || _chart_id == "") return false;
    var want = string_lower(string(_chart_id));
    var cid = string_lower(string(struct_get_fallback(_song, "chart_id", "")));
    if (cid != "" && cid == want) return true;
    var folder = string_lower(vs_localcharts_folder_name(struct_get_fallback(_song, "chart_path", "")));
    return folder != "" && folder == want;
}

// Find { pack_index, pos, song_id } of a chart across the current song packs.
// Returns undefined when the chart is not reachable in the select.
function vs_localcharts_pack_pos(_chart_id)
{
    if (!variable_global_exists("song_packs") || !variable_global_exists("song_list")) return undefined;
    var want = string(_chart_id);
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
                if (vs_localcharts_chart_matches(global.song_list[sid], want))
                    return { pack_index: p, pos: s, song_id: sid };
            }
        }
    }
    return undefined;
}

function vs_localcharts_pack_pos_by_id(_pack_id)
{
    var pid = string(_pack_id);
    if (pid == "" || !variable_global_exists("song_packs")) return undefined;
    for (var p = 0; p < array_length(global.song_packs); p++)
    {
        var pk = global.song_packs[p];
        if (pk == undefined) continue;
        if (variable_struct_exists(pk, "vs_pack_id") && string(pk.vs_pack_id) == pid)
        {
            if (!variable_struct_exists(pk, "songs") || !is_array(pk.songs) || array_length(pk.songs) <= 0)
                return undefined;
            var sid = pk.songs[0];
            if (!is_real(sid) || sid < 0 || sid >= array_length(global.song_list)) return undefined;
            return { pack_index: p, pos: 0, song_id: sid };
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
    // load_song_information rebuilds song_list then CustomSongReader appends once.
    vs_songstore_clear_save_songs();
    try { load_song_information(); }
    catch (_e) { show_debug_message("VS LocalCharts: song reload failed -> " + string(_e)); }
    try { create_song_packs(); }
    catch (_e2) { show_debug_message("VS LocalCharts: pack rebuild failed -> " + string(_e2)); }
    try { load_highscores(); }
    catch (_e3) { show_debug_message("VS LocalCharts: highscore reload failed -> " + string(_e3)); }
    try { process_song_unlocks(); }
    catch (_e4) { show_debug_message("VS LocalCharts: unlock rebuild failed -> " + string(_e4)); }
    vs_lobby_unlock_pad();
}

// Jump into the song select with a chart focused (used from both the download
// manager's Local tab and any local-chart entry). Returns false when the chart
// is not reachable in the select.
function vs_localcharts_enter_select(_loc)
{
    if (_loc == undefined) return false;

    // Old song select restores last_freeplay_pack / last_freeplay_index.
    global.force_song_select = _loc.song_id;
    global.last_freeplay_pack = _loc.pack_index;
    global.last_freeplay_index = _loc.pos;
    global.last_freeplay_song = _loc.song_id;
    var jumpDiff = 0;
    var jumpSong = global.song_list[_loc.song_id];
    if (jumpSong != undefined)
    {
        var jumpDir = struct_get_fallback(jumpSong, "chart_load_dir", struct_get_fallback(jumpSong, "chart_path", ""));
        jumpDiff = vs_csm_first_chart_diff(jumpDir);
    }
    global.songselect_difficulty = jumpDiff;

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
    room_goto(scene_songselect_old);
    return true;
}

function vs_localcharts_rebuild_packs()
{
    if (variable_global_exists("custom_song_packs"))
    {
        try { create_song_packs(); } catch (_e) { }
    }
}

// Jump into the song select with a chart focused (used from both the download
// manager's Local tab and any local-chart entry). Returns false when the chart
// is not reachable in the select.
function vs_localcharts_jump(_chart_id)
{
    if (_chart_id == undefined || _chart_id == "") return false;
    vs_localcharts_rebuild_packs();
    return vs_localcharts_enter_select(vs_localcharts_pack_pos(_chart_id));
}

function vs_localcharts_jump_pack(_pack_id)
{
    if (_pack_id == undefined || _pack_id == "") return false;
    vs_localcharts_rebuild_packs();
    return vs_localcharts_enter_select(vs_localcharts_pack_pos_by_id(_pack_id));
}

function vs_localcharts_jump_shatter(_chart_id)
{
    if (_chart_id == undefined || _chart_id == "") return false;

    try { create_shatter_list(); } catch (_e) { }

    var sid = vs_localcharts_shatter_id_in_list(_chart_id);
    if (sid < 0) return false;

    // Shatter select ignores force_song_select (that is for Rhythm Play packs)
    // and instead restores last_boundaryshatter_song. Set both.
    global.force_song_select = sid;
    global.last_boundaryshatter_song = sid;

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
                var item = { chartId: c.chart_id, difficulty: vs_online_diff_api(diffs[d]), sha1: sha };
                var vsm = vs_online_chart_vsm_sha1(c.chart_id, diffs[d]);
                if (vsm != "") item.vsmSha1 = vsm;
                array_push(charts, item);
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
    var body = {};
    variable_struct_set(body, "charts", charts);
    vs_online_post_json("/api/v1/charts/check-updates", body, vs_localcharts_auto_done);
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
