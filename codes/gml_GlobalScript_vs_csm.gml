// ============================================================================
// vs_csm.gml — Custom Songs support (vendored / adapted from Custom Songs Mod)
//
// Always on, even when Custom Server is off. Standalone CSM is a hard conflict
// (see conflict_check.gml). We do NOT register as custom_song_mod.
//
// Two roots are scanned:
//   - game_save_id + Custom Songs/   (downloader / sandbox writes)
//   - program_directory + Custom Songs/  (manual Steam drops)
// audio_create_stream / sprite_add / .vsc reads use chart_load_dir (the folder
// that was actually found). chart_path stays relative so stats sidecars write
// into the save area.
// ============================================================================

function vs_csm_norm_dir(_p)
{
    var s = string_replace_all(string(_p), "\\", "/");
    if (s != "" && string_char_at(s, string_length(s)) != "/") s += "/";
    return s;
}

function vs_csm_same_dir(_a, _b)
{
    var a = string_lower(vs_csm_norm_dir(_a));
    var b = string_lower(vs_csm_norm_dir(_b));
    return a != "/" && a == b;
}

function vs_csm_save_area()
{
    var s = "";
    try { s = game_save_id; } catch (_e) { s = ""; }
    if (s == undefined || s == "") s = working_directory;
    return vs_csm_norm_dir(s);
}

function vs_csm_save_songs_root()
{
    return vs_csm_save_area() + "Custom Songs/";
}

function vs_csm_steam_songs_root()
{
    var s = "";
    try { s = program_directory; } catch (_e) { s = ""; }
    if (s == undefined || s == "") return "";
    return vs_csm_norm_dir(s) + "Custom Songs/";
}

// Save-area first so a downloaded copy wins over a Steam folder with the same name.
function vs_csm_song_roots()
{
    var roots = [];
    var save = vs_csm_save_songs_root();
    var steam = vs_csm_steam_songs_root();
    if (save != "" && directory_exists(save)) array_push(roots, save);
    if (steam != "" && directory_exists(steam) && !vs_csm_same_dir(steam, save))
        array_push(roots, steam);
    return roots;
}

function vs_csm_list_subdirs(_root)
{
    var out = [];
    if (_root == undefined || _root == "") return out;
    if (!directory_exists(_root)) return out;
    var n = file_find_first(_root + "*", 16);
    while (n != "")
    {
        if (n != "." && n != "..")
            array_push(out, { name: n, dir: _root + n + "/" });
        n = file_find_next();
    }
    file_find_close();
    return out;
}

function vs_csm_find_song(_chartId)
{
    if (_chartId == undefined || _chartId == "") return undefined;
    if (variable_global_exists("song_list"))
    {
        var n = array_length(global.song_list);
        for (var i = 0; i < n; i++)
        {
            var s = global.song_list[i];
            if (s != undefined && variable_struct_exists(s, "chart_id") && s.chart_id == _chartId)
                return s;
        }
    }
    if (variable_global_exists("shatter_list"))
    {
        var n2 = array_length(global.shatter_list);
        for (var j = 0; j < n2; j++)
        {
            var sh = global.shatter_list[j];
            if (sh != undefined && variable_struct_exists(sh, "chart_id") && sh.chart_id == _chartId)
                return sh;
        }
    }
    return undefined;
}

function vs_csm_load_dir_from_id(_chartId)
{
    var song = vs_csm_find_song(_chartId);
    if (song != undefined)
        return struct_get_fallback(song, "chart_load_dir", struct_get_fallback(song, "chart_path", ""));
    return vs_csm_search_load_dir(_chartId);
}

function vs_csm_stat_dir(_chartId)
{
    var song = vs_csm_find_song(_chartId);
    if (song != undefined)
        return struct_get_fallback(song, "chart_path", "Custom Songs/" + _chartId + "/");
    return "Custom Songs/" + _chartId + "/";
}

function vs_csm_search_load_dir(_chartId)
{
    if (_chartId == undefined || _chartId == "") return "";
    var roots = vs_csm_song_roots();
    for (var r = 0; r < array_length(roots); r++)
    {
        var top = roots[r] + _chartId + "/";
        if (file_exists(top + "info.json") || file_exists(top + "shatterinfo.json"))
            return top;
        var kids = vs_csm_list_subdirs(roots[r]);
        for (var i = 0; i < array_length(kids); i++)
        {
            if (file_exists(kids[i].dir + "songpack_info.json"))
            {
                var nested = kids[i].dir + _chartId + "/";
                if (file_exists(nested + "info.json") || file_exists(nested + "shatterinfo.json"))
                    return nested;
            }
        }
    }
    return "";
}

function vs_csm_force_gm_audio()
{
    ini_open("system");
    var soundEng = ini_read_real("config", "use_gamemaker_audio", 1);
    if (soundEng == 0)
    {
        global.op_use_gamemaker_audio = 1;
        ini_write_real("config", "use_gamemaker_audio", 1);
    }
    ini_close();
}

function vs_csm_read_json_file(_path)
{
    if (!file_exists(_path)) return undefined;
    var f = file_text_open_read(_path);
    if (f == -1) return undefined;
    var raw = "";
    while (!file_text_eof(f))
        raw += file_text_readln(f);
    file_text_close(f);
    var j = undefined;
    try { j = json_parse(raw); } catch (_e) { j = undefined; }
    return j;
}

function vs_csm_add_stream(_dir, _name)
{
    var p = _dir + _name;
    if (file_exists(p)) return audio_create_stream(p);
    return undefined;
}

function vs_csm_add_jacket(_dir, _src)
{
    if (_src != undefined && _src != "" && file_exists(_dir + _src))
        return sprite_add(_dir + _src, 1, false, false, 0, 0);
    var jacketNames = ["jacket.gif", "jacket.jpeg", "jacket.jpg", "jacket.png"];
    for (var i = 0; i < array_length(jacketNames); i++)
    {
        if (file_exists(_dir + jacketNames[i]))
            return sprite_add(_dir + jacketNames[i], 1, false, false, 0, 0);
    }
    return undefined;
}

function vs_csm_ensure_unlock(_song)
{
    if (!variable_struct_exists(_song, "unlock") || !is_struct(_song.unlock))
    {
        _song.unlock =
        {
            song_id: _song.song_id,
            type: 0,
            enc_type: 0,
            per_difficulty: false,
            hidden: false,
            hint: "",
            enc_hint: ""
        };
        return;
    }
    _song.unlock.song_id = _song.song_id;
}

function readCustomSongPackInfo(dir)
{
    var packInfo = vs_csm_read_json_file(dir + "songpack_info.json");
    if (packInfo == undefined) packInfo = {};
    if (!variable_struct_exists(packInfo, "songs") || !is_array(packInfo.songs))
        packInfo.songs = [];
    return packInfo;
}

function readShatterInfo(dir, rel)
{
    var songInfo = vs_csm_read_json_file(dir + "shatterinfo.json");
    if (songInfo == undefined) return undefined;
    songInfo.chart_path = rel;
    songInfo.chart_load_dir = dir;
    songInfo.is_custom = true;
    songInfo.song_id = array_length(global.shatter_list);

    var audName = variable_struct_exists(songInfo, "audio_id") ? songInfo.audio_id : "music.ogg";
    var aud = vs_csm_add_stream(dir, audName);
    if (aud != undefined) songInfo.audio_id = aud;

    if (!variable_struct_exists(songInfo, "preview_id"))
    {
        var prev = vs_csm_add_stream(dir, "preview.ogg");
        songInfo.preview_id = (prev != undefined) ? prev : songInfo.audio_id;
    }
    else
    {
        var prev2 = vs_csm_add_stream(dir, songInfo.preview_id);
        if (prev2 != undefined) songInfo.preview_id = prev2;
    }

    var jacket = vs_csm_add_jacket(dir, variable_struct_exists(songInfo, "jacket") ? songInfo.jacket : "");
    songInfo.jacket = (jacket != undefined) ? jacket : song_generic;

    if (!variable_struct_exists(songInfo, "ticket_earns"))
        songInfo.ticket_earns = [0, 0, 0];

    if (!variable_struct_exists(songInfo, "unlock") || !is_method(songInfo.unlock))
    {
        songInfo.unlock = function()
        {
            return true;
        };
    }
    return songInfo;
}

function CustomShatterReader()
{
    var seen = {};
    var roots = vs_csm_song_roots();
    for (var r = 0; r < array_length(roots); r++)
    {
        var entries = vs_csm_list_subdirs(roots[r]);
        var packs = [];
        for (var i = 0; i < array_length(entries); i++)
        {
            var e = entries[i];
            var key = string_lower(e.name);
            if (file_exists(e.dir + "shatterinfo.json"))
            {
                if (variable_struct_exists(seen, key)) continue;
                var songInfo = readShatterInfo(e.dir, "Custom Songs/" + e.name + "/");
                if (songInfo == undefined) continue;
                var cid = string_lower(string(songInfo.chart_id));
                if (variable_struct_exists(seen, cid)) continue;
                variable_struct_set(seen, key, true);
                variable_struct_set(seen, cid, true);
                array_push(global.shatter_list, songInfo);
                array_push(global.shatter_order, songInfo.song_id);
            }
            else if (file_exists(e.dir + "songpack_info.json"))
            {
                array_push(packs, e);
            }
        }
        for (var p = 0; p < array_length(packs); p++)
        {
            var children = vs_csm_list_subdirs(packs[p].dir);
            for (var j = 0; j < array_length(children); j++)
            {
                var c = children[j];
                if (!file_exists(c.dir + "shatterinfo.json")) continue;
                var ck = string_lower(packs[p].name + "/" + c.name);
                if (variable_struct_exists(seen, ck)) continue;
                var rel = "Custom Songs/" + packs[p].name + "/" + c.name + "/";
                var sh = readShatterInfo(c.dir, rel);
                if (sh == undefined) continue;
                var cid2 = string_lower(string(sh.chart_id));
                if (variable_struct_exists(seen, cid2)) continue;
                variable_struct_set(seen, ck, true);
                variable_struct_set(seen, cid2, true);
                array_push(global.shatter_list, sh);
                array_push(global.shatter_order, sh.song_id);
            }
        }
    }
}

function readCustomSongInfo(dir, rel)
{
    var songInfoSrc = vs_csm_read_json_file(dir + "info.json");
    if (songInfoSrc == undefined || !is_struct(songInfoSrc)) return undefined;

    var songInfo = getGenericSong(-1);
    structcpy(songInfoSrc, songInfo);

    songInfo.chart_path = rel;
    songInfo.chart_load_dir = dir;
    songInfo.is_custom = true;
    songInfo.song_id = array_length(global.song_list);
    vs_csm_ensure_unlock(songInfo);

    var audName = variable_struct_exists(songInfoSrc, "audio_id") ? songInfoSrc.audio_id : "music.ogg";
    var aud = vs_csm_add_stream(dir, audName);
    if (aud != undefined) songInfo.audio_id = aud;

    if (!variable_struct_exists(songInfoSrc, "sort_artists"))
    {
        var _art = variable_struct_exists(songInfoSrc, "artist") ? songInfoSrc.artist : "";
        songInfo.sort_artists = [_art];
    }

    if (!variable_struct_exists(songInfoSrc, "preview_id"))
    {
        var prev = vs_csm_add_stream(dir, "preview.ogg");
        songInfo.preview_id = (prev != undefined) ? prev : songInfo.audio_id;
    }
    else
    {
        var prev2 = vs_csm_add_stream(dir, songInfoSrc.preview_id);
        if (prev2 != undefined) songInfo.preview_id = prev2;
    }

    var jacket = vs_csm_add_jacket(dir, variable_struct_exists(songInfoSrc, "jacket") ? songInfoSrc.jacket : "");
    songInfo.jacket = (jacket != undefined) ? jacket : song_generic;

    if (variable_struct_exists(songInfo, "enc_data") && is_struct(songInfo.enc_data))
    {
        var encData = songInfo.enc_data;
        encData.song_id = array_length(global.song_list);
        if (variable_struct_exists(encData, "audio_id"))
        {
            var enca = vs_csm_add_stream(dir, encData.audio_id);
            encData.audio_id = (enca != undefined) ? enca : songInfo.audio_id;
        }
        else
        {
            encData.audio_id = songInfo.audio_id;
        }
        if (variable_struct_exists(encData, "preview_id"))
        {
            var encp = vs_csm_add_stream(dir, encData.preview_id);
            encData.preview_id = (encp != undefined) ? encp : encData.audio_id;
        }
        else
        {
            encData.preview_id = encData.audio_id;
        }
        if (variable_struct_exists(encData, "jacket"))
        {
            var encj = vs_csm_add_jacket(dir, encData.jacket);
            encData.jacket = (encj != undefined) ? encj : songInfo.jacket;
        }
        else
        {
            encData.jacket = songInfo.jacket;
        }
        encData.jacket_designer = variable_struct_exists(encData, "jacket_designer") ? encData.jacket_designer : songInfo.jacket_artist;
        songInfo.enc_data = encData;
    }
    return songInfo;
}

function CustomSongReader()
{
    global.custom_song_packs = [];
    var customSongList = [];
    var seenCharts = {};
    var seenPacks = {};
    var packJobs = [];
    var roots = vs_csm_song_roots();

    for (var r = 0; r < array_length(roots); r++)
    {
        var entries = vs_csm_list_subdirs(roots[r]);
        for (var i = 0; i < array_length(entries); i++)
        {
            var e = entries[i];
            var key = string_lower(e.name);
            if (file_exists(e.dir + "info.json"))
            {
                if (variable_struct_exists(seenCharts, key)) continue;
                var songInfo = readCustomSongInfo(e.dir, "Custom Songs/" + e.name + "/");
                if (songInfo == undefined) continue;
                var cid = string_lower(string(songInfo.chart_id));
                if (cid != "" && variable_struct_exists(seenCharts, cid)) continue;
                variable_struct_set(seenCharts, key, true);
                if (cid != "") variable_struct_set(seenCharts, cid, true);
                array_push(customSongList, array_length(global.song_list));
                array_push(global.song_list, songInfo);
            }
            else if (file_exists(e.dir + "songpack_info.json"))
            {
                if (variable_struct_exists(seenPacks, key)) continue;
                variable_struct_set(seenPacks, key, true);
                array_push(packJobs, e);
            }
        }
    }

    for (var p = 0; p < array_length(packJobs); p++)
    {
        var dir = packJobs[p].dir;
        var packInfo = readCustomSongPackInfo(dir);
        var children = vs_csm_list_subdirs(dir);
        for (var j = 0; j < array_length(children); j++)
        {
            var c = children[j];
            if (!file_exists(c.dir + "info.json")) continue;
            var ck = string_lower(packJobs[p].name + "/" + c.name);
            if (variable_struct_exists(seenCharts, ck)) continue;
            var rel = "Custom Songs/" + packJobs[p].name + "/" + c.name + "/";
            var packed = readCustomSongInfo(c.dir, rel);
            if (packed == undefined) continue;
            var cid2 = string_lower(string(packed.chart_id));
            if (cid2 != "" && variable_struct_exists(seenCharts, cid2)) continue;
            variable_struct_set(seenCharts, ck, true);
            if (cid2 != "") variable_struct_set(seenCharts, cid2, true);
            array_push(packInfo.songs, array_length(global.song_list));
            array_push(customSongList, array_length(global.song_list));
            array_push(global.song_list, packed);
        }
        array_push(global.custom_song_packs, packInfo);
    }

    array_push(global.custom_song_packs,
    {
        name: "All Custom Songs",
        songs: customSongList,
        color1: 16777215,
        color2: 16777215,
        description: "Custom Songs."
    });
}

function vs_csm_row_score(_row)
{
    if (_row == undefined) return 0;
    var v = variable_struct_get(_row, "score");
    if (v == undefined || !is_real(v)) return 0;
    return v;
}

function vs_csm_scores_merge_start()
{
    if (!vs_online_is_custom() || !vs_online_is_account()) return;
    if (!variable_global_exists("highscores") || !variable_global_exists("song_list")) return;

    var jobs = [];
    var diffs = ["OPENING", "MIDDLE", "FINALE", "ENCORE", "PRELUDE"];
    for (var i = 0; i < array_length(global.song_list); i++)
    {
        var song = global.song_list[i];
        if (song == undefined || !variable_struct_exists(song, "is_custom")) continue;
        for (var d = 0; d < 5; d++)
        {
            var row = undefined;
            if (i < array_length(global.highscores.normal) && d < array_length(global.highscores.normal[i]))
                row = global.highscores.normal[i][d];
            var sha = vs_online_chart_sha1(song.chart_id, diffs[d]);
            var loc = vs_csm_row_score(row);
            if ((sha == undefined || sha == "") && (loc == undefined || loc <= 0)) continue;
            array_push(jobs,
            {
                kind: 0,
                index: i,
                diff_i: d,
                chart_id: song.chart_id,
                diff: diffs[d],
                sha1: sha,
                local_score: loc
            });
        }
    }
    if (variable_global_exists("shatter_list"))
    {
        for (var s = 0; s < array_length(global.shatter_list); s++)
        {
            var sh = global.shatter_list[s];
            if (sh == undefined || !variable_struct_exists(sh, "is_custom")) continue;
            var srow = (s < array_length(global.highscores.shatter)) ? global.highscores.shatter[s] : undefined;
            var sha2 = vs_online_chart_sha1(sh.chart_id, sh.difficulty_name);
            var loc2 = vs_csm_row_score(srow);
            if ((sha2 == undefined || sha2 == "") && (loc2 == undefined || loc2 <= 0)) continue;
            array_push(jobs,
            {
                kind: 1,
                index: s,
                diff_i: 0,
                chart_id: sh.chart_id,
                diff: sh.difficulty_name,
                sha1: sha2,
                local_score: loc2
            });
        }
    }
    global.vs_csm_merge = { jobs: jobs, idx: 0 };
    vs_csm_scores_merge_next();
}

function vs_csm_scores_merge_next()
{
    if (!variable_global_exists("vs_csm_merge")) return;
    var st = global.vs_csm_merge;
    if (st.idx >= array_length(st.jobs)) return;
    var job = st.jobs[st.idx];
    vs_online_get_my_chart_score(job.chart_id, job.diff, job.sha1, vs_csm_scores_merge_done);
}

function vs_csm_scores_merge_apply(_job, _server)
{
    var local_ = _job.local_score;
    if (local_ == undefined) local_ = 0;
    if (_server > local_)
    {
        var row = undefined;
        if (_job.kind == 0)
        {
            if (_job.index < array_length(global.highscores.normal)
                && _job.diff_i < array_length(global.highscores.normal[_job.index]))
            {
                row = global.highscores.normal[_job.index][_job.diff_i];
                variable_struct_set(row, "score", _server);
            }
        }
        else if (_job.index < array_length(global.highscores.shatter))
        {
            row = global.highscores.shatter[_job.index];
            variable_struct_set(row, "score", _server);
        }
    }
}

function vs_csm_scores_merge_done(_ok, _data, _status)
{
    if (!variable_global_exists("vs_csm_merge")) return;
    var st = global.vs_csm_merge;
    if (st.idx >= array_length(st.jobs)) return;
    var job = st.jobs[st.idx];
    var server_ = 0;
    if (_ok && _data != undefined && variable_struct_exists(_data, "found") && _data.found)
        server_ = variable_struct_get(_data, "score");
    if (server_ == undefined) server_ = 0;
    vs_csm_scores_merge_apply(job, server_);
    st.idx += 1;
    vs_csm_scores_merge_next();
}
