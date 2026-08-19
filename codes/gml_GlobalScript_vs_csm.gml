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
    var s = vs_songstore_save_dir();
    if (s != undefined && s != "") return vs_csm_norm_dir(s);
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

function vs_csm_root_listed(_roots, _dir)
{
    for (var i = 0; i < array_length(_roots); i++)
    {
        if (vs_csm_same_dir(_roots[i], _dir)) return true;
    }
    return false;
}

// Relative first (same view as Downloaded / file_exists), then explicit
// AppData, then Steam. audio/sprite still resolve through vs_csm_pick_load_dir.
function vs_csm_song_roots()
{
    var roots = [];
    array_push(roots, "Custom Songs/");
    var save = vs_csm_save_songs_root();
    if (save != "" && directory_exists(save) && !vs_csm_root_listed(roots, save))
        array_push(roots, save);
    var steam = vs_csm_steam_songs_root();
    if (steam != "" && directory_exists(steam) && !vs_csm_root_listed(roots, steam))
        array_push(roots, steam);
    return roots;
}

function vs_csm_rel_tail(_rel)
{
    var s = vs_csm_norm_dir(_rel);
    if (string_starts_with(string_lower(s), "custom songs/"))
        return string_copy(s, 14, string_length(s));
    return s;
}

function vs_csm_dir_has_info(_dir)
{
    if (_dir == undefined || _dir == "") return false;
    return file_exists(_dir + "info.json") || file_exists(_dir + "shatterinfo.json");
}

function vs_csm_dir_has_charts(_dir)
{
    if (_dir == undefined || _dir == "") return false;
    var names = ["OPENING", "MIDDLE", "FINALE", "ENCORE", "PRELUDE"];
    for (var i = 0; i < array_length(names); i++)
    {
        if (file_exists(_dir + names[i] + ".vsc") || file_exists(_dir + names[i] + ".vsb")
            || file_exists(_dir + string_lower(names[i]) + ".vsc") || file_exists(_dir + string_lower(names[i]) + ".vsb"))
            return true;
    }
    return false;
}

function vs_csm_pick_load_dir(_rel)
{
    var tail = vs_csm_rel_tail(_rel);
    var cands = [];
    var save = vs_csm_save_songs_root();
    if (save != "") array_push(cands, save + tail);
    var steam = vs_csm_steam_songs_root();
    if (steam != "") array_push(cands, steam + tail);
    array_push(cands, vs_csm_norm_dir(_rel));
    var fallback = "";
    for (var i = 0; i < array_length(cands); i++)
    {
        var d = cands[i];
        if (!vs_csm_dir_has_info(d)) continue;
        if (fallback == "") fallback = d;
        // AppData stubs (info.json, no .vsc) used to win over a complete
        // Steam copy of the same chart_id, which hid ENCORE on encore-only songs.
        if (vs_csm_dir_has_charts(d)) return d;
    }
    if (fallback != "") return fallback;
    return vs_csm_norm_dir(_rel);
}

function vs_csm_list_subdirs(_root)
{
    var out = [];
    if (_root == undefined || _root == "") return out;
    if (!directory_exists(_root)) return out;
    var n = file_find_first(_root + "*", 16);
    if (n == "")
    {
        file_find_close();
        n = file_find_first(_root + "*", 0);
    }
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
    // Custom audio_create_stream sounds cannot go through precise_audio_*.
    // CSM's initSetting flips this to GameMaker; official default is Custom (0).
    if (variable_global_exists("op_use_gamemaker_audio") && global.op_use_gamemaker_audio == 1)
        return false;
    vs_csm_play_log("force gm audio was=" + string(variable_global_exists("op_use_gamemaker_audio") ? global.op_use_gamemaker_audio : "?"));
    global.op_use_gamemaker_audio = 1;
    ini_open("system");
    ini_write_real("config", "use_gamemaker_audio", 1);
    ini_close();
    try { precise_audio_uninit_device(); } catch (_e) { }
    return true;
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
    if (!file_exists(p)) return undefined;
    var a = audio_create_stream(p);
    if (!vs_csm_asset_ok_audio(a))
    {
        vs_csm_play_log("stream fail " + string(p) + " -> " + string(a));
        return undefined;
    }
    return a;
}

function vs_csm_add_jacket(_dir, _src)
{
    if (_src != undefined && _src != "" && file_exists(_dir + _src))
    {
        var spr0 = sprite_add(_dir + _src, 1, false, false, 0, 0);
        if (vs_csm_asset_ok_sprite(spr0)) return spr0;
        vs_csm_play_log("jacket fail " + _dir + string(_src) + " -> " + string(spr0));
    }
    var jacketNames = ["jacket.gif", "jacket.jpeg", "jacket.jpg", "jacket.png"];
    for (var i = 0; i < array_length(jacketNames); i++)
    {
        if (file_exists(_dir + jacketNames[i]))
        {
            var spr1 = sprite_add(_dir + jacketNames[i], 1, false, false, 0, 0);
            if (vs_csm_asset_ok_sprite(spr1)) return spr1;
            vs_csm_play_log("jacket fail " + _dir + jacketNames[i] + " -> " + string(spr1));
        }
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

function vs_csm_has_encore_file(_dir)
{
    if (_dir == undefined || _dir == "") return false;
    return vs_csm_chart_file_exists(_dir, "ENCORE");
}

function vs_csm_chart_file_exists(_dir, _name)
{
    if (_dir == undefined || _dir == "" || _name == undefined) return false;
    var n = string(_name);
    return file_exists(_dir + n + ".vsc") || file_exists(_dir + n + ".vsb")
        || file_exists(_dir + string_lower(n) + ".vsc") || file_exists(_dir + string_lower(n) + ".vsb");
}

function vs_csm_json_has_encore(_v)
{
    if (_v == true || _v == 1) return true;
    var s = string_lower(string(_v));
    return (s == "1.0" || s == "1" || s == "true" || s == "yes");
}

function vs_csm_meta_has_encore(_song)
{
    if (_song == undefined) return false;
    if (variable_struct_exists(_song, "has_encore") && vs_csm_json_has_encore(_song.has_encore))
        return true;
    var c4 = vs_csm_safe_real(struct_get_fallback(_song, "difficulty_constant_4", 0), 0);
    if (c4 > 0) return true;
    var d4 = string(struct_get_fallback(_song, "difficulty_display_4", "0"));
    return (d4 != "" && d4 != "0" && d4 != "0.0" && d4 != "N/A");
}

// Official select stores has_encore as the string "1.0" (from the vsd) and
// compares with == / != "1.0". JSON bool true is truthy for `&&` checks but
// fails those comparisons, so refresh_song_objects remaps ENCORE -> FINALE
// and the old select never lets you cursor onto difficulty 3.
//
// Only a real ENCORE.vsc/vsb counts. info.json often has constant_4 / has_encore
// leftover from templates; treating that as Encore makes Encore-only select
// drop Finale 16/15+ and empty the list (NO SIGNAL).
function vs_csm_apply_has_encore(_song, _dir)
{
    _song.has_encore = vs_csm_has_encore_file(_dir) ? "1.0" : false;
    if (!variable_struct_exists(_song, "show_encore")) _song.show_encore = true;
}

function vs_csm_first_chart_diff(_dir)
{
    var names = ["OPENING", "MIDDLE", "FINALE", "ENCORE"];
    for (var i = 0; i < 4; i++)
    {
        if (vs_csm_chart_file_exists(_dir, names[i]))
            return i;
    }
    return 0;
}

// Official MAX LEVEL "17" is index 22. Custom 17+ (const 17.5) maps to 23
// and anything above that is 18, 18+, … Saved max is often still 22, which
// emptied Encore-only lists (no Finale rows to fall back on) into NO SIGNAL.
function vs_csm_level_in_range(_chk, _lo, _hi)
{
    if (_chk == -1) return true;
    if (_chk >= _lo && _chk <= _hi) return true;
    if (_chk >= 23 && _hi >= 22) return true;
    return false;
}

function vs_csm_recover_empty_songsel()
{
    var changed = false;
    if (level_range_end < 23)
    {
        level_range_end = 23;
        global.last_freeplay_max_level = 23;
        changed = true;
    }
    if (level_range_start > 22)
    {
        level_range_start = 22;
        global.last_freeplay_min_level = 22;
        changed = true;
    }
    if (changed) refresh_song_objects(0);
}

// Song-select badges are sprite frames: 1..18 and 9+..16+. 17+ is frame 27,
// which the official sheet does not have. Draw the display string instead.
function vs_csm_draw_diff_badge(_sprite, _diff_value, _x, _y)
{
    var dv = string(_diff_value);
    var idx = 0;
    if (string_length(dv) > 0 && string_char_at(dv, string_length(dv)) == "+")
    {
        idx = (19 + vs_csm_safe_real(string_copy(dv, 1, string_length(dv) - 1), 0)) - 9;
    }
    else
    {
        idx = vs_csm_safe_real(dv, 0);
    }
    if (sprite_exists(_sprite) && idx >= 0 && idx < sprite_get_number(_sprite))
    {
        draw_sprite(_sprite, idx, _x, _y);
        return;
    }
    var ha = draw_get_halign();
    var va = draw_get_valign();
    var w = sprite_exists(_sprite) ? sprite_get_width(_sprite) : 18;
    var h = sprite_exists(_sprite) ? sprite_get_height(_sprite) : 18;
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text(_x + (w / 2), _y + (h / 2), dv);
    draw_set_halign(ha);
    draw_set_valign(va);
}

function vs_csm_play_log(_msg)
{
    var line = "VS PLAY: " + string(_msg);
    show_debug_message(line);
    vs_songstore_log("PLAY " + string(_msg));
}

function vs_csm_safe_real(_v, _fallback)
{
    if (_v == undefined) return _fallback;
    if (is_real(_v))
    {
        if (_v != _v) return _fallback;
        return _v;
    }
    var s = string(_v);
    var out = "";
    var n = string_length(s);
    for (var i = 1; i <= n; i++)
    {
        var ch = string_char_at(s, i);
        if (ch == "-" && out == "")
        {
            out = "-";
            continue;
        }
        if (ch == "." && string_pos(".", out) == 0)
        {
            out += ".";
            continue;
        }
        if (ord(ch) >= 48 && ord(ch) <= 57)
        {
            out += ch;
            continue;
        }
        if (out != "" && out != "-") break;
        if (out == "-") out = "";
    }
    if (out == "" || out == "-" || out == ".") return _fallback;
    var r = _fallback;
    try { r = real(out); } catch (_e) { r = _fallback; }
    return r;
}

function vs_csm_bpm_real(_v)
{
    var r = vs_csm_safe_real(_v, 120);
    if (r <= 0) return 120;
    return r;
}

function vs_csm_empty_chart()
{
    return { notes: [], mods: undefined };
}

function vs_csm_note_extra_get(_extra, _key, _fallback)
{
    if (!is_struct(_extra)) return _fallback;
    var v = variable_struct_get(_extra, _key);
    if (v == undefined) v = variable_struct_get(_extra, string(_key));
    if (v == undefined) return _fallback;
    return vs_csm_safe_real(v, _fallback);
}

function vs_csm_note_extra_set(_end)
{
    var e = {};
    variable_struct_set(e, 1, _end);
    variable_struct_set(e, "1", _end);
    return e;
}

function vs_csm_pick_diff_file(_dir, _want)
{
    if (_dir == undefined) _dir = "";
    _dir = vs_csm_norm_dir(_dir);
    var want = string(_want);
    if (file_exists(_dir + want + ".vsc")) return { path: _dir + want + ".vsc", diff: want };
    var names = ["OPENING", "MIDDLE", "FINALE", "ENCORE", "PRELUDE"];
    for (var i = 0; i < 5; i++)
    {
        if (file_exists(_dir + names[i] + ".vsc"))
            return { path: _dir + names[i] + ".vsc", diff: names[i] };
    }
    return undefined;
}

function vs_csm_asset_ok_audio(_a)
{
    return (_a != undefined && _a != -1 && audio_exists(_a));
}

function vs_csm_asset_ok_sprite(_s)
{
    return (_s != undefined && _s != -1 && sprite_exists(_s));
}

function vs_csm_start_song_guard(_song, _diffIdx)
{
    if (_song == undefined) return;
    var loadDir = struct_get_fallback(_song, "chart_load_dir", struct_get_fallback(_song, "chart_path", ""));
    var names = ["OPENING", "MIDDLE", "FINALE", "ENCORE", "PRELUDE"];
    var want = (is_real(_diffIdx) && _diffIdx >= 0 && _diffIdx < 5) ? names[_diffIdx] : string(_diffIdx);
    var aud = song_get_info(_song, "audio_id", _diffIdx);
    var jk = song_get_info(_song, "jacket", _diffIdx);
    vs_csm_play_log("start chart=" + string(struct_get_fallback(_song, "chart_id", "?"))
        + " idx=" + string(_diffIdx)
        + " want=" + want
        + " dir=" + string(loadDir)
        + " vsc=" + string(file_exists(loadDir + want + ".vsc"))
        + " audio=" + string(aud) + " ok=" + string(vs_csm_asset_ok_audio(aud))
        + " jacket=" + string(jk) + " ok=" + string(vs_csm_asset_ok_sprite(jk))
        + " bpm=" + string(struct_get_fallback(_song, "bpm_display", ""))
        + " encore=" + string(struct_get_fallback(_song, "has_encore", false)));
    if (variable_struct_exists(_song, "is_custom"))
        vs_csm_force_gm_audio();
    if (!vs_csm_asset_ok_audio(global.loadaudio))
    {
        vs_csm_play_log("loadaudio invalid, fallback generic");
        global.loadaudio = music_chart_desparola;
    }
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
                var shRel = "Custom Songs/" + e.name + "/";
                var songInfo = undefined;
                try { songInfo = readShatterInfo(vs_csm_pick_load_dir(shRel), shRel); } catch (_sh1) { songInfo = undefined; }
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
                var sh = undefined;
                try { sh = readShatterInfo(vs_csm_pick_load_dir(rel), rel); } catch (_sh2) { sh = undefined; }
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
    var folderId = vs_localcharts_folder_name(rel);
    var cid0 = string(struct_get_fallback(songInfo, "chart_id", ""));
    if (cid0 == "" || cid0 == "generic") songInfo.chart_id = folderId;
    songInfo.song_id = array_length(global.song_list);
    vs_csm_ensure_unlock(songInfo);
    vs_csm_apply_has_encore(songInfo, dir);

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
                var songRel = "Custom Songs/" + e.name + "/";
                var songInfo = undefined;
                try { songInfo = readCustomSongInfo(vs_csm_pick_load_dir(songRel), songRel); } catch (_rd) { songInfo = undefined; }
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
            var packed = undefined;
            try { packed = readCustomSongInfo(vs_csm_pick_load_dir(rel), rel); } catch (_rd2) { packed = undefined; }
            if (packed == undefined) continue;
            var cid2 = string_lower(string(packed.chart_id));
            if (cid2 != "" && variable_struct_exists(seenCharts, cid2)) continue;
            variable_struct_set(seenCharts, ck, true);
            if (cid2 != "") variable_struct_set(seenCharts, cid2, true);
            array_push(packInfo.songs, array_length(global.song_list));
            array_push(customSongList, array_length(global.song_list));
            array_push(global.song_list, packed);
        }
        var pid = vs_packmgr_id_from_folder(packJobs[p].name);
        if (pid != "")
        {
            packInfo.vs_pack_id = pid;
            vs_packmgr_csm_fill(packInfo, pid);
        }
        array_push(global.custom_song_packs, packInfo);
    }

    // Subscribed online packs stay as loose Custom Songs/<chart_id>/ folders.
    // Build a real song-select pack from vsonline.packs.json; members also
    // stay in All Custom Songs, same as a CSM folder pack.
    vs_packmgr_csm_append();

    array_push(global.custom_song_packs,
    {
        name: "All Custom Songs",
        songs: customSongList,
        color1: 16777215,
        color2: 16777215,
        description: "Custom Songs."
    });
}

function vs_csm_song_index(_chartId)
{
    var want = string_lower(string(_chartId));
    if (want == "" || !variable_global_exists("song_list")) return -1;
    var n = array_length(global.song_list);
    for (var i = 0; i < n; i++)
    {
        var s = global.song_list[i];
        if (s == undefined) continue;
        var cid = string_lower(string(struct_get_fallback(s, "chart_id", "")));
        if (cid == want) return i;
        var folder = string_lower(vs_localcharts_folder_name(struct_get_fallback(s, "chart_path", "")));
        if (folder != "" && folder == want) return i;
    }
    return -1;
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
