// ============================================================================
// vs_songstore.gml — custom-song store data layer (vs-server-go /songs)
//
// Shared download primitives used by the home-page Chart Downloader:
//   - vs_songstore_detail      fetch a song's full metadata (files[] + sha1)
//   - vs_songstore_diff        sha1-diff the server files[] against local
//   - vs_songstore_download_file  download one file (http_get_file)
//
// Charts go in working_directory + Custom Songs/<id>/. GML cannot write
// program_directory while the sandbox is on; relative / working_directory
// writes land in the save area. info.json is written last.
// ============================================================================

function vs_songstore_root()
{
    return "Custom Songs/";
}

function vs_songstore_install_path(_rel)
{
    var r = string_replace_all(string(_rel), "\\", "/");
    var p = working_directory;
    if (p == undefined || p == "") return r;
    p = string_replace_all(string(p), "\\", "/");
    if (p != "" && string_char_at(p, string_length(p)) != "/") p += "/";
    return p + r;
}

function vs_songstore_win_path(_p)
{
    return string_replace_all(string(_p), "/", "\\");
}

function vs_songstore_same_dir(_a, _b)
{
    var a = string_lower(string_replace_all(string(_a), "\\", "/"));
    var b = string_lower(string_replace_all(string(_b), "\\", "/"));
    if (a != "" && string_char_at(a, string_length(a)) != "/") a += "/";
    if (b != "" && string_char_at(b, string_length(b)) != "/") b += "/";
    return a != "/" && a == b;
}

function vs_songstore_save_dir()
{
    var la = environment_get_variable("LOCALAPPDATA");
    if (la == undefined || la == "") return "";
    la = string_replace_all(string(la), "\\", "/");
    if (la != "" && string_char_at(la, string_length(la)) != "/") la += "/";
    return la + "VIVIDSTASIS/";
}

function vs_songstore_tmp_abs(_tmp)
{
    if (_tmp == undefined || _tmp == "") return "";
    var name = filename_name(string(_tmp));
    var cands = [];
    if (string_pos(":", string(_tmp)) > 0) array_push(cands, string(_tmp));
    var save = vs_songstore_save_dir();
    if (save != "") array_push(cands, save + name);
    array_push(cands, working_directory + name);
    array_push(cands, vs_songstore_install_path(name));
    var i = 0;
    repeat (array_length(cands))
    {
        if (cands[i] != "" && file_exists(cands[i])) return cands[i];
        i++;
    }
    if (save != "") return save + name;
    return working_directory + name;
}

function vs_songstore_tmp_src(_tmp)
{
    if (_tmp == undefined || _tmp == "") return "";
    if (file_exists(_tmp)) return _tmp;
    var abs = vs_songstore_tmp_abs(_tmp);
    if (abs != "" && file_exists(abs)) return abs;
    return "";
}

function vs_songstore_parent(_path)
{
    var p = string_replace_all(string(_path), "\\", "/");
    var cut = string_last_pos("/", p);
    if (cut <= 0) return "";
    return string_copy(p, 1, cut);
}

function vs_songstore_clear_save_songs()
{
}

function vs_songstore_destroy_dir(_dir)
{
    if (_dir == undefined || _dir == "") return;
    var d = string_replace_all(string(_dir), "\\", "/");
    if (d != "" && string_char_at(d, string_length(d)) != "/") d += "/";
    if (d == "" || d == "/" || !directory_exists(d)) return;
    var files = vs_songstore_list_names(d, false);
    var i = 0;
    repeat (array_length(files))
    {
        var f = d + files[i];
        if (file_exists(f) && !directory_exists(f)) file_delete(f);
        i++;
    }
    var dirs = vs_songstore_list_names(d, true);
    i = 0;
    repeat (array_length(dirs))
    {
        var sub = dirs[i];
        if (sub != "." && sub != "..") vs_songstore_destroy_dir(d + sub + "/");
        i++;
    }
    directory_destroy(d);
}

function vs_songstore_file_ready(_rel)
{
    if (_rel == undefined || _rel == "") return false;
    if (file_exists(_rel)) return true;
    return file_exists(vs_songstore_install_path(_rel));
}

function vs_songstore_real_tmp(_tmp)
{
    var name = filename_name(string(_tmp));
    var save = vs_songstore_save_dir();
    if (save != "") return save + name;
    return string(_tmp);
}

function vs_songstore_placed_ok()
{
    var p = vs_songstore_save_dir() + "vsonline_placed";
    if (!file_exists(p)) p = "vsonline_placed";
    if (!file_exists(p)) return false;
    var f = file_text_open_read(p);
    if (f < 0) return false;
    var s = file_text_read_string(f);
    file_text_close(f);
    return string_pos("1", s) > 0;
}

function vs_songstore_dir_has_chart(_dir)
{
    if (_dir == undefined || _dir == "") return false;
    return file_exists(_dir + "info.json") || file_exists(_dir + "shatterinfo.json");
}

function vs_songstore_local_dir(_chartId)
{
    return vs_songstore_root() + _chartId + "/";
}

function vs_songstore_has_chart(_chartId)
{
    if (_chartId == undefined || _chartId == "") return false;
    var rel = vs_songstore_local_dir(_chartId);
    return vs_songstore_dir_has_chart(rel) || vs_songstore_dir_has_chart(vs_songstore_install_path(rel));
}

function vs_songstore_ensure_dir(_dir)
{
    if (_dir == undefined || _dir == "") return;
    var d = string_replace_all(string(_dir), "\\", "/");
    if (d != "" && string_char_at(d, string_length(d)) == "/") d = string_copy(d, 1, string_length(d) - 1);
    if (d == "") return;
    var cur = "";
    var seg = "";
    var i = 1;
    var n = string_length(d);
    while (i <= n)
    {
        var c = string_char_at(d, i);
        if (c == "/")
        {
            if (seg != "")
            {
                cur = (cur == "") ? seg : (cur + "/" + seg);
                if (!directory_exists(cur)) directory_create(cur);
                seg = "";
            }
        }
        else seg += c;
        i++;
    }
    if (seg != "")
    {
        cur = (cur == "") ? seg : (cur + "/" + seg);
        if (!directory_exists(cur)) directory_create(cur);
    }
}

function vs_songstore_remove_chart(_chartId)
{
    if (_chartId == undefined || _chartId == "") return;
    try { vs_media_stop_preview(); } catch (_m) { }
    vs_songstore_clear_save_songs();
    var rel = vs_songstore_local_dir(_chartId);
    var paths = [rel, vs_songstore_install_path(rel)];
    var save = vs_csm_save_songs_root();
    if (save != "") array_push(paths, save + _chartId + "/");
    var steam = vs_csm_steam_songs_root();
    if (steam != "") array_push(paths, steam + _chartId + "/");
    var seen = {};
    var i = 0;
    repeat (array_length(paths))
    {
        var d = paths[i];
        var key = string_lower(string_replace_all(string(d), "\\", "/"));
        if (d != "" && !variable_struct_exists(seen, key))
        {
            variable_struct_set(seen, key, true);
            vs_songstore_destroy_dir(d);
        }
        i++;
    }
    try { vs_dlmgr_untrack(_chartId); } catch (_u) { }
}

function vs_songstore_cleanup_stub(_chartId)
{
    if (_chartId == undefined || _chartId == "") return;
    vs_songstore_clear_save_songs();
    if (vs_songstore_has_chart(_chartId)) return;
    vs_songstore_remove_chart(_chartId);
}

function vs_songstore_list_names(_dir, _dirs)
{
    var out = [];
    var n = file_find_first(_dir + "*", _dirs ? 16 : 0);
    while (n != "")
    {
        if (n != "." && n != "..") array_push(out, n);
        n = file_find_next();
    }
    file_find_close();
    return out;
}

function vs_songstore_copy_tree(_src, _dst, _skip)
{
    if (!directory_exists(_src)) return;
    vs_songstore_ensure_dir(_dst);
    var files = vs_songstore_list_names(_src, false);
    var i = 0;
    repeat (array_length(files))
    {
        var f = files[i];
        if (f != _skip && file_exists(_src + f) && !directory_exists(_src + f))
        {
            if (file_exists(_dst + f)) file_delete(_dst + f);
            file_copy(_src + f, _dst + f);
        }
        i++;
    }
    var dirs = vs_songstore_list_names(_src, true);
    i = 0;
    repeat (array_length(dirs))
    {
        var d = dirs[i];
        if (directory_exists(_src + d) || directory_exists(_src + d + "/"))
        {
            vs_songstore_copy_tree(_src + d + "/", _dst + d + "/", "");
        }
        i++;
    }
}

function vs_songstore_install_from_zip(_zip, _chartId)
{
    var root = vs_songstore_root();
    vs_songstore_ensure_dir(root);
    var staging = root + _chartId + ".vs_partial/";
    if (directory_exists(staging)) directory_destroy(staging);
    directory_create(staging);
    var n = zip_unzip(_zip, staging);
    if (file_exists(_zip)) file_delete(_zip);
    if (n <= 0)
    {
        if (directory_exists(staging)) directory_destroy(staging);
        vs_songstore_set_err("unzip failed (" + string(n) + ")");
        return false;
    }
    var dest = root + _chartId + "/";
    vs_songstore_copy_tree(staging, dest, "info.json");
    if (file_exists(dest + "shatterinfo.json")) file_delete(dest + "shatterinfo.json");
    if (file_exists(staging + "info.json"))
    {
        if (file_exists(dest + "info.json")) file_delete(dest + "info.json");
        file_copy(staging + "info.json", dest + "info.json");
    }
    if (file_exists(staging + "shatterinfo.json"))
    {
        file_copy(staging + "shatterinfo.json", dest + "shatterinfo.json");
    }
    if (directory_exists(staging)) directory_destroy(staging);
    if (!vs_songstore_dir_has_chart(dest))
    {
        vs_songstore_set_err("package missing info.json");
        vs_songstore_cleanup_stub(_chartId);
        return false;
    }
    return true;
}

function vs_songstore_basename(_name)
{
    if (_name == undefined) return "";
    var n = string_replace_all(string(_name), "\\", "/");
    var cut = string_last_pos("/", n);
    if (cut > 0) return string_copy(n, cut + 1, string_length(n));
    return n;
}

// Sanitize a server files[].name entry. Keeps safe relative subpaths
// (images/cover.png) so info.json jacket paths resolve after download.
function vs_songstore_safe_relpath(_name)
{
    if (_name == undefined) return "";
    var n = string_replace_all(string(_name), "\\", "/");
    while (string_pos("//", n) > 0)
    {
        n = string_replace_all(n, "//", "/");
    }
    if (string_copy(n, 1, 1) == "/") n = string_copy(n, 2, string_length(n));
    while (string_length(n) > 0 && string_char_at(n, string_length(n)) == "/")
    {
        n = string_copy(n, 1, string_length(n) - 1);
    }
    if (n == "" || n == "." || n == "..") return "";
    // Reject .. segments and empty components.
    var out = "";
    var seg = "";
    var i = 1;
    var len = string_length(n);
    while (i <= len)
    {
        var c = string_char_at(n, i);
        if (c == "/")
        {
            if (seg == "" || seg == "." || seg == ".." || string_pos(":", seg) > 0) return "";
            out = (out == "") ? seg : (out + "/" + seg);
            seg = "";
        }
        else seg += c;
        i++;
    }
    if (seg == "" || seg == "." || seg == ".." || string_pos(":", seg) > 0) return "";
    return (out == "") ? seg : (out + "/" + seg);
}

function vs_songstore_file_exists_rel(_relPath)
{
    if (_relPath == undefined || _relPath == "") return false;
    if (file_exists(_relPath)) return true;
    return file_exists(vs_songstore_install_path(_relPath));
}

function vs_songstore_hash_rel(_relPath)
{
    if (_relPath == undefined || _relPath == "") return "";
    var p = vs_songstore_install_path(_relPath);
    if (!file_exists(p)) p = _relPath;
    if (!file_exists(p)) return "";
    return sha1_file(p);
}

function vs_songstore_ends_with(_s, _suf)
{
    var s = string_lower(string(_s));
    var f = string_lower(string(_suf));
    var n = string_length(s);
    var m = string_length(f);
    if (n < m) return false;
    return string_copy(s, n - m + 1, m) == f;
}

// Runtime / editor sidecars. CSM rewrites *.stats_custom on play; vs-chart.json
// is web-editor metadata. Neither is a playable chart file — including them
// in the sha1 diff makes a chart look permanently out of date.
function vs_songstore_skip_file(_name)
{
    var n = string_lower(string(_name));
    var base = string_lower(vs_songstore_basename(_name));
    if (base == "vs-chart.json" || base == ".vs_download.json") return true;
    if (vs_songstore_ends_with(n, ".stats_custom")) return true;
    if (vs_songstore_ends_with(n, ".stats")) return true;
    return false;
}

function vs_songstore_is_root_info(_rel)
{
    var n = string_lower(string(_rel));
    return n == "info.json" || n == "shatterinfo.json";
}

// Detail GET is one-at-a-time with a FIFO of callbacks. A single global
// on_done slot dropped Check-all when opening a row (and vice versa).
function vs_songstore_fetch_slot()
{
    if (!variable_global_exists("vs_store_fetch"))
    {
        global.vs_store_fetch = { busy: false, q: [] };
    }
    if (!variable_struct_exists(global.vs_store_fetch, "q") || !is_array(global.vs_store_fetch.q))
    {
        global.vs_store_fetch.q = [];
    }
    return global.vs_store_fetch;
}

function vs_songstore_fetch_busy()
{
    var st = vs_songstore_fetch_slot();
    return st.busy || array_length(st.q) > 0;
}

function vs_songstore_fetch_kick()
{
    var st = vs_songstore_fetch_slot();
    if (st.busy) return;
    if (array_length(st.q) <= 0) return;
    st.busy = true;
    var job = st.q[0];
    var path = (job.kind == 2) ? "/api/v1/shatters/" : "/api/v1/songs/";
    vs_online_get_json(path + job.id, false, vs_songstore_fetch_http);
}

function vs_songstore_fetch_http(_ok, _data, _status)
{
    var st = vs_songstore_fetch_slot();
    var job = undefined;
    if (array_length(st.q) > 0)
    {
        job = st.q[0];
        array_delete(st.q, 0, 1);
    }
    st.busy = false;
    if (job != undefined)
    {
        if (job.via == "check") vs_dlmgr_check_apply(job, _ok, _data, _status);
        else if (job.on_done != undefined) job.on_done(_ok, _data, _status);
    }
    vs_songstore_fetch_kick();
}

function vs_songstore_fetch_push(_kind, _id, _on_done, _via, _chartId)
{
    var st = vs_songstore_fetch_slot();
    var job = {};
    variable_struct_set(job, "kind", _kind);
    variable_struct_set(job, "id", string(_id));
    variable_struct_set(job, "on_done", _on_done);
    variable_struct_set(job, "via", string(_via));
    variable_struct_set(job, "chartId", string(_chartId));
    array_push(st.q, job);
    vs_songstore_fetch_kick();
}

// _kind 2 = shatter (GET /shatters/:id), otherwise song (GET /songs/:id).
function vs_songstore_fetch(_kind, _id, _on_done)
{
    vs_songstore_fetch_push(_kind, _id, _on_done, "", "");
}

function vs_songstore_detail(_songId, _on_done)
{
    vs_songstore_fetch(0, _songId, _on_done);
}

function vs_songstore_diff(_files, _chartId)
{
    var need = [];
    var info = undefined;
    if (_files == undefined) return need;
    vs_songstore_clear_save_songs();
    var dir = vs_songstore_local_dir(_chartId);
    var seen = {};
    for (var i = 0; i < array_length(_files); i++)
    {
        var f = _files[i];
        var rel = vs_songstore_safe_relpath(f.name);
        if (rel == "" || vs_songstore_skip_file(rel))
        {
            if (rel == "") show_debug_message("VS Songstore: skip unsafe file name -> " + string(f.name));
            continue;
        }
        var relKey = string_lower(rel);
        if (variable_struct_exists(seen, relKey)) continue;
        variable_struct_set(seen, relKey, true);
        var localPath = dir + rel;
        var localHash = vs_songstore_hash_rel(localPath);
        var atTarget = vs_songstore_file_exists_rel(localPath);
        // Pre-nested installs stored images/cover.png as cover.png at chart root.
        var legacyPath = "";
        if (!atTarget && rel != vs_songstore_basename(rel))
        {
            legacyPath = dir + vs_songstore_basename(rel);
            if (localHash == "") localHash = vs_songstore_hash_rel(legacyPath);
        }
        var serverHash = string_lower(string(f.sha1));
        var matched = (localHash != "" && serverHash != "" && string_lower(localHash) == serverHash);
        if (!matched)
        {
            var item = { name: f.name, url: f.url, localPath: localPath };
            if (vs_songstore_is_root_info(rel)) info = item;
            else array_push(need, item);
        }
        else if (!atTarget && legacyPath != "")
        {
            var mv = { name: f.name, url: f.url, localPath: localPath, relocateOnly: true, relocateFrom: legacyPath };
            if (vs_songstore_is_root_info(rel)) info = mv;
            else array_push(need, mv);
        }
    }
    if (info != undefined) array_push(need, info);
    return need;
}

function vs_songstore_relocate_file(_from, _to)
{
    if (_from == undefined || _to == undefined || _from == "" || _to == "") return false;
    var src = vs_songstore_install_path(_from);
    if (!file_exists(src)) src = _from;
    if (!file_exists(src)) return false;
    vs_songstore_ensure_dir(vs_songstore_parent(_to));
    var put = vs_songstore_install_path(_to);
    if (file_exists(_to)) file_delete(_to);
    if (file_exists(put)) file_delete(put);
    file_copy(src, _to);
    if (!file_exists(_to) && !file_exists(put)) file_copy(src, put);
    var ok = file_exists(_to) || file_exists(put);
    if (!ok) return false;
    // Move off the legacy flat path so a/x.txt and b/x.txt cannot both
    // claim the same root basename during one update batch.
    if (file_exists(_from)) file_delete(_from);
    if (file_exists(src) && src != _to && src != put) file_delete(src);
    return true;
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
        marker = "/avatars/";
        p = string_pos(marker, u);
    }
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
    return vs_songstore_encode_url(string_replace_all(u, " ", "%20"));
}

function vs_songstore_encode_url(_url)
{
    var u = string(_url);
    var proto = "";
    var rest = u;
    var sp = string_pos("://", u);
    if (sp > 0)
    {
        proto = string_copy(u, 1, sp + 2);
        rest = string_copy(u, sp + 3, string_length(u));
    }
    var slash = string_pos("/", rest);
    if (slash <= 0) return u;
    var host = string_copy(rest, 1, slash - 1);
    var path = string_copy(rest, slash, string_length(rest));
    var query = "";
    var qpos = string_pos("?", path);
    if (qpos > 0)
    {
        query = string_copy(path, qpos, string_length(path));
        path = string_copy(path, 1, qpos - 1);
    }
    var out = "";
    var seg = "";
    var i = 1;
    var n = string_length(path);
    while (i <= n)
    {
        var c = string_char_at(path, i);
        if (c == "/")
        {
            // Skip empty segments so "/uploads/..." does not become "//uploads/...".
            if (seg != "")
            {
                out += "/" + ((string_pos("%", seg) > 0) ? seg : vs_online_url_encode(seg));
                seg = "";
            }
        }
        else seg += c;
        i++;
    }
    if (seg != "") out += "/" + ((string_pos("%", seg) > 0) ? seg : vs_online_url_encode(seg));
    if (out == "") out = "/";
    return proto + host + out + query;
}

function vs_songstore_log(_msg)
{
    var line = "VS DL: " + string(_msg);
    show_debug_message(line);
    var path = working_directory + "vsonline.dl.log";
    if (!variable_global_exists("vs_dl_log_n")) global.vs_dl_log_n = 0;
    global.vs_dl_log_n += 1;
    if (global.vs_dl_log_n > 2000)
    {
        if (file_exists(path)) file_delete(path);
        global.vs_dl_log_n = 1;
    }
    var f = file_text_open_append(path);
    if (f < 0) return;
    file_text_write_string(f, date_date_string(date_current_datetime()) + " " + date_time_string(date_current_datetime()) + "  " + line);
    file_text_writeln(f);
    file_text_close(f);
}

function vs_songstore_set_err(_msg)
{
    if (variable_global_exists("vs_dlmgr_dl"))
    {
        global.vs_dlmgr_dl.err = _msg;
    }
    vs_songstore_log(string(_msg));
}

function vs_songstore_sweep_tmp()
{
    var keep = "";
    if (variable_global_exists("vs_dl_busy") && global.vs_dl_busy && variable_global_exists("vs_dl_state"))
    {
        keep = string(global.vs_dl_state.tmpPath);
    }
    var names = [];
    var n = file_find_first("vsonline_dl_*.bin", 0);
    while (n != "")
    {
        array_push(names, n);
        n = file_find_next();
    }
    file_find_close();
    n = file_find_first(working_directory + "vsonline_dl_*.bin", 0);
    while (n != "")
    {
        array_push(names, working_directory + n);
        n = file_find_next();
    }
    file_find_close();
    var save = vs_songstore_save_dir();
    if (save != "")
    {
        n = file_find_first(save + "vsonline_dl_*.bin", 0);
        while (n != "")
        {
            array_push(names, save + n);
            n = file_find_next();
        }
        file_find_close();
    }
    var i = 0;
    repeat (array_length(names))
    {
        var p = names[i];
        if (keep != "" && (p == keep || p == working_directory + keep || filename_name(p) == filename_name(keep)))
        {
            i++;
            continue;
        }
        if (file_exists(p)) file_delete(p);
        i++;
    }
    if (keep == "" || keep != "vsonline_dl.bin")
    {
        if (file_exists("vsonline_dl.bin")) file_delete("vsonline_dl.bin");
        if (file_exists(working_directory + "vsonline_dl.bin")) file_delete(working_directory + "vsonline_dl.bin");
    }
}

function vs_songstore_dl_init()
{
    if (!variable_global_exists("vs_dl_q"))
    {
        global.vs_dl_q = [];
        global.vs_dl_busy = false;
        global.vs_dl_scheduled = false;
        global.vs_dl_state = { rid: -1, gen: 0, url: "", localPath: "", tmpPath: "vsonline_dl.bin", on_done: undefined, got: 0, total: 0, httpStatus: -1, placing: false, placeTries: 0 };
        vs_songstore_sweep_tmp();
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
        vs_songstore_dl_complete(false);
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
    global.vs_dl_state.httpStatus = -1;
    global.vs_dl_state.placing = false;
    global.vs_dl_state.placeTries = 0;
    global.vs_dl_state.gen = global.vs_dl_gen;
    global.vs_dl_state.rid = http_get_file(url, tmp);
    if (global.vs_dl_state.rid == undefined || global.vs_dl_state.rid < 0)
    {
        vs_songstore_set_err("http_get_file failed");
        vs_songstore_dl_finish(false);
        return;
    }
    array_push(global.vs_dl_to, global.vs_dl_state.gen);
    call_later(60 * 300, time_source_units_frames, vs_songstore_dl_on_timeout);
    vs_songstore_log("start " + string(job.localPath) + " url=" + url + " rid=" + string(global.vs_dl_state.rid));
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
    vs_songstore_set_err("timeout " + string(st.url));
    vs_songstore_dl_complete(false);
}

function vs_songstore_dl_commit(_ok)
{
    var st = global.vs_dl_state;
    var tmp = st.tmpPath;
    var src = vs_songstore_tmp_src(tmp);
    var dest = st.localPath;
    if (_ok)
    {
        if (src != "")
        {
            vs_songstore_ensure_dir(vs_songstore_parent(dest));
            var put = vs_songstore_install_path(dest);
            if (file_exists(dest)) file_delete(dest);
            if (file_exists(put)) file_delete(put);
            file_copy(src, dest);
            if (!file_exists(dest) && !file_exists(put)) file_copy(src, put);
            if (file_exists(src)) file_delete(src);
            dest = file_exists(dest) ? dest : put;
        }
        _ok = file_exists(dest) || file_exists(vs_songstore_install_path(st.localPath));
        if (!_ok) vs_songstore_set_err("could not write " + vs_songstore_install_path(st.localPath));
        else vs_songstore_log("wrote " + vs_songstore_install_path(st.localPath));
    }
    else if (src != "")
    {
        file_delete(src);
    }
    vs_songstore_sweep_tmp();
    return _ok;
}

function vs_songstore_dl_complete(_ok)
{
    vs_songstore_dl_init();
    var st = global.vs_dl_state;
    var cb = st.on_done;
    var path = st.localPath;
    var tmp = st.tmpPath;
    var src = vs_songstore_tmp_src(tmp);
    if (src != "") file_delete(src);
    else if (tmp != "" && file_exists(tmp)) file_delete(tmp);
    st.on_done = undefined;
    st.rid = -1;
    st.gen = 0;
    st.placing = false;
    st.placeTries = 0;
    global.vs_dl_busy = false;
    if (cb != undefined) { cb(_ok, path); }
    vs_songstore_dl_schedule();
}

function vs_songstore_dl_finish(_ok)
{
    vs_songstore_dl_init();
    _ok = vs_songstore_dl_commit(_ok);
    vs_songstore_dl_complete(_ok);
}

function vs_songstore_dl_wait_tmp()
{
    var st = global.vs_dl_state;
    if (st.placing) return;
    st.placing = true;
    st.placeTries = 0;
    vs_songstore_log("wait tmp " + string(st.localPath));
    call_later(1, time_source_units_frames, vs_songstore_dl_on_place);
}

function vs_songstore_dl_on_place()
{
    vs_songstore_dl_init();
    if (!global.vs_dl_busy) return;
    var st = global.vs_dl_state;
    if (!st.placing) return;
    if (variable_struct_exists(st, "httpStatus") && st.httpStatus >= 400)
    {
        vs_songstore_set_err("http " + string(st.httpStatus) + " for " + string(st.url));
        vs_songstore_dl_finish(false);
        return;
    }
    if (vs_songstore_tmp_src(st.tmpPath) != "")
    {
        vs_songstore_log("tmp ready " + string(st.localPath));
        vs_songstore_dl_finish(true);
        return;
    }
    st.placeTries += 1;
    if (st.placeTries >= 45)
    {
        vs_songstore_set_err("could not write " + vs_songstore_install_path(st.localPath));
        vs_songstore_dl_finish(false);
        return;
    }
    call_later(1, time_source_units_frames, vs_songstore_dl_on_place);
}

function vs_songstore_on_http()
{
    if (!variable_global_exists("vs_dl_busy") || !global.vs_dl_busy) return;
    var st = global.vs_dl_state;
    if (st == undefined || st.rid < 0) return;
    if (async_load == -1) return;
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || string(rid) != string(st.rid)) return;
    var gmStatus = vs_http_num(ds_map_find_value(async_load, "status"), -1);
    var got = vs_http_num(ds_map_find_value(async_load, "sizeDownloaded"), -1);
    var tot = vs_http_num(ds_map_find_value(async_load, "contentLength"), -1);
    if (got >= 0) st.got = got;
    if (tot >= 0) st.total = tot;
    if (variable_global_exists("vs_dlmgr_dl"))
    {
        global.vs_dlmgr_dl.fileGot = st.got;
        global.vs_dlmgr_dl.fileTotal = st.total;
    }
    var doneProg = (st.total > 0 && st.got >= st.total);
    var tmpHere = (vs_songstore_tmp_src(st.tmpPath) != "");
    var httpStatus = vs_http_num(ds_map_find_value(async_load, "http_status"), -1);
    if (httpStatus >= 0) st.httpStatus = httpStatus;
    if (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel)
    {
        vs_songstore_dl_finish(false);
        return;
    }
    var settle = vs_http_file_settle(gmStatus, httpStatus, tmpHere, doneProg);
    if (settle == 0)
    {
        if (httpStatus >= 400)
        {
            vs_songstore_set_err("http " + string(httpStatus) + " for " + string(st.url));
            vs_songstore_dl_finish(false);
            return;
        }
        if (doneProg || gmStatus == 0) vs_songstore_dl_wait_tmp();
        return;
    }
    var ok = (settle > 0);
    if (!ok && httpStatus >= 400) vs_songstore_set_err("http " + string(httpStatus) + " for " + string(st.url));
    else if (!ok) vs_songstore_set_err("download file missing after http " + string(httpStatus) + " st=" + string(gmStatus));
    vs_songstore_log("done " + string(st.localPath) + " ok=" + string(ok) + " http=" + string(httpStatus) + " st=" + string(gmStatus) + " tmp=" + string(tmpHere));
    vs_songstore_dl_finish(ok);
}

function vs_songstore_download_package(_songId, _chartId, _on_done)
{
    if (!variable_global_exists("vs_dl_pkg"))
    {
        global.vs_dl_pkg = { on_done: undefined, chartId: "" };
    }
    global.vs_dl_pkg.on_done = _on_done;
    global.vs_dl_pkg.chartId = _chartId;
    var url = vs_online_server_url() + "/api/v1/songs/" + _songId + "/package";
    vs_songstore_download_file(url, "vsonline_pkg.zip", vs_songstore_pkg_file_done);
}

function vs_songstore_pkg_file_done(_ok, _path)
{
    var cb = global.vs_dl_pkg.on_done;
    var chartId = global.vs_dl_pkg.chartId;
    global.vs_dl_pkg.on_done = undefined;
    if (!_ok || _path == undefined || !file_exists(_path))
    {
        if (cb != undefined) cb(false, _path);
        return;
    }
    var dest = vs_songstore_root() + chartId + "/";
    var ok = vs_songstore_install_from_zip(_path, chartId);
    if (cb != undefined) cb(ok, dest);
}
