// ============================================================================
// vs_songstore.gml — custom-song store data layer (vs-server-go /songs)
//
// Shared download primitives used by the home-page Chart Downloader:
//   - vs_songstore_detail      fetch a song's full metadata (files[] + sha1)
//   - vs_songstore_diff        sha1-diff the server files[] against local
//   - vs_songstore_download_file  download one file (http_get_file)
//
// Charts use CSM's Custom Songs/<id>/ next to the exe.
// http_get_file can only land in the save area (AppData). GML file_copy /
// directory_create to program_directory are remapped back there too, so
// they never create the Steam folder CSM reads. After the temp file is
// ready, cmd copies it using program_directory (the game folder from the
// download log — not parameter_string(0), which became D:\).
// Detect with file_exists on the relative path. Never delete
// working_directory/Custom Songs — here that is the Steam folder.
// Only an AppData Custom Songs shadow is safe to remove. info.json last.
// ============================================================================

function vs_songstore_root()
{
    return "Custom Songs/";
}

function vs_songstore_install_path(_rel)
{
    var r = string_replace_all(string(_rel), "\\", "/");
    var p = program_directory;
    if (p == undefined || p == "") return r;
    p = string_replace_all(string(p), "\\", "/");
    if (p != "" && string_char_at(p, string_length(p)) != "/") p += "/";
    var low = string_lower(p);
    if (string_length(low) >= 10 && string_copy(low, string_length(low) - 9, 10) == "modloader/")
    {
        p = string_copy(p, 1, string_length(p) - 10);
    }
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

function vs_songstore_parent(_path)
{
    var p = string_replace_all(string(_path), "\\", "/");
    var cut = string_last_pos("/", p);
    if (cut <= 0) return "";
    return string_copy(p, 1, cut);
}

function vs_songstore_clear_save_songs()
{
    var save = vs_songstore_save_dir();
    var game = vs_songstore_install_path("");
    if (save == "" || vs_songstore_same_dir(save, game)) return;
    var p = save + "Custom Songs";
    if (directory_exists(p)) directory_destroy(p);
    p = save + "Custom Songs/";
    if (directory_exists(p)) directory_destroy(p);
}

function vs_songstore_file_ready(_rel)
{
    if (_rel == undefined || _rel == "") return false;
    if (file_exists(_rel)) return true;
    return file_exists(vs_songstore_install_path(_rel));
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
    vs_songstore_clear_save_songs();
    var rel = vs_songstore_local_dir(_chartId);
    return vs_songstore_dir_has_chart(rel);
}

function vs_songstore_ensure_dir(_dir)
{
}

function vs_songstore_remove_chart(_chartId)
{
    if (_chartId == undefined || _chartId == "") return;
    vs_songstore_clear_save_songs();
    var d = vs_songstore_install_path(vs_songstore_local_dir(_chartId));
    if (directory_exists(d)) directory_destroy(d);
}

function vs_songstore_cleanup_stub(_chartId)
{
    if (_chartId == undefined || _chartId == "") return;
    vs_songstore_clear_save_songs();
    if (vs_songstore_has_chart(_chartId)) return;
    var d = vs_songstore_install_path(vs_songstore_local_dir(_chartId));
    if (directory_exists(d) && !vs_songstore_dir_has_chart(d))
    {
        if (file_exists(d + ".vs_download.json")) file_delete(d + ".vs_download.json");
        directory_destroy(d);
    }
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

function vs_songstore_flatten_name(_name)
{
    if (_name == undefined) return "";
    var n = string_replace_all(string(_name), "\\", "/");
    while (string_pos("//", n) > 0)
    {
        n = string_replace_all(n, "//", "/");
    }
    if (string_copy(n, 1, 1) == "/") n = string_copy(n, 2, string_length(n));
    if (n == "" || n == "." || n == ".." || string_pos("..", n) > 0)
    {
        return "";
    }
    // CSM reads info.json / *.vsc at the folder root. Nested names
    // (Cui/info.json) would write Custom Songs/Cui/Cui/info.json, then
    // has_chart misses it and cleanup_stub deletes the install.
    var cut = string_last_pos("/", n);
    if (cut > 0) n = string_copy(n, cut + 1, string_length(n));
    if (n == "" || n == "." || n == "..") return "";
    return n;
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
    if (n == "vs-chart.json" || n == ".vs_download.json") return true;
    if (vs_songstore_ends_with(n, ".stats_custom")) return true;
    if (vs_songstore_ends_with(n, ".stats")) return true;
    return false;
}

// _kind 2 = shatter (GET /shatters/:id), otherwise song (GET /songs/:id).
function vs_songstore_fetch(_kind, _id, _on_done)
{
    if (!variable_global_exists("vs_store_detail_cb"))
    {
        global.vs_store_detail_cb = { on_done: undefined };
    }
    global.vs_store_detail_cb.on_done = _on_done;
    var path = (_kind == 2) ? "/api/v1/shatters/" : "/api/v1/songs/";
    vs_online_get_json(path + _id, false,
        function(_ok, _data, _status)
        {
            var cb = global.vs_store_detail_cb.on_done;
            global.vs_store_detail_cb.on_done = undefined;
            if (cb != undefined) { cb(_ok, _data); }
        });
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
    for (var i = 0; i < array_length(_files); i++)
    {
        var f = _files[i];
        var flat = vs_songstore_flatten_name(f.name);
        if (flat == "" || vs_songstore_skip_file(flat))
        {
            if (flat == "") show_debug_message("VS Songstore: skip unsafe file name -> " + string(f.name));
            continue;
        }
        var localPath = dir + flat;
        var readPath = vs_songstore_install_path(localPath);
        if (!file_exists(readPath)) readPath = localPath;
        var localHash = file_exists(readPath) ? sha1_file(readPath) : "";
        if (string_lower(localHash) != string_lower(f.sha1))
        {
            var item = { name: f.name, url: f.url, localPath: localPath };
            if (string_lower(flat) == "info.json" || string_lower(flat) == "shatterinfo.json") info = item;
            else array_push(need, item);
        }
    }
    if (info != undefined) array_push(need, info);
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
        global.vs_dl_state = { rid: -1, gen: 0, url: "", localPath: "", tmpPath: "vsonline_dl.bin", on_done: undefined, got: 0, total: 0, placing: false, placeTries: 0 };
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

function vs_songstore_os_copy(_src, _dst)
{
    if (_src == undefined || _src == "" || _dst == undefined || _dst == "") return false;
    var src = vs_songstore_win_path(_src);
    var dst = vs_songstore_win_path(_dst);
    var dstDir = filename_dir(dst);
    var save = vs_songstore_save_dir();
    if (save == "") save = working_directory;
    var bat = save + "vsonline_place.bat";
    var logp = vs_songstore_win_path(save + "vsonline_place_cmd.log");
    var f = file_text_open_write(bat);
    if (f < 0)
    {
        vs_songstore_log("could not write place bat " + string(bat));
        return false;
    }
    file_text_write_string(f, "@echo off");
    file_text_writeln(f);
    file_text_write_string(f, "echo src=" + src + " > \"" + logp + "\"");
    file_text_writeln(f);
    file_text_write_string(f, "echo dst=" + dst + " >> \"" + logp + "\"");
    file_text_writeln(f);
    file_text_write_string(f, "if exist \"" + src + "\" (echo src_exists=1 >> \"" + logp + "\") else (echo src_exists=0 >> \"" + logp + "\")");
    file_text_writeln(f);
    file_text_write_string(f, "mkdir \"" + dstDir + "\" >> \"" + logp + "\" 2>&1");
    file_text_writeln(f);
    file_text_write_string(f, "copy /Y \"" + src + "\" \"" + dst + "\" >> \"" + logp + "\" 2>&1");
    file_text_writeln(f);
    file_text_write_string(f, "echo ERRORLEVEL=%ERRORLEVEL% >> \"" + logp + "\"");
    file_text_writeln(f);
    file_text_write_string(f, "if exist \"" + dst + "\" (echo placed=1 >> \"" + logp + "\") else (echo placed=0 >> \"" + logp + "\")");
    file_text_writeln(f);
    file_text_close(f);
    execute_shell_simple(vs_songstore_win_path(bat), "", "open", 0);
    return true;
}

function vs_songstore_place_start()
{
    var st = global.vs_dl_state;
    var tmp = st.tmpPath;
    var dest = st.localPath;
    var src = vs_songstore_tmp_abs(tmp);
    vs_songstore_log("paths wd=" + string(working_directory) + " pd=" + string(program_directory) + " save=" + vs_songstore_save_dir());
    vs_songstore_log("tmp rel=" + string(tmp) + " exists=" + string(file_exists(tmp)) + " src=" + string(src) + " src_exists=" + string(file_exists(src)));
    if (src == "" || !file_exists(src))
    {
        vs_songstore_log("place missing tmp " + string(tmp));
        return false;
    }
    var dst = vs_songstore_install_path(dest);
    if (dst == "" || dst == dest)
    {
        vs_songstore_log("place bad dest, program_directory empty");
        return false;
    }
    if (!vs_songstore_os_copy(src, dst)) return false;
    vs_songstore_log("place " + string(src) + " -> " + string(dst));
    return true;
}

function vs_songstore_dl_complete(_ok)
{
    vs_songstore_dl_init();
    var st = global.vs_dl_state;
    var cb = st.on_done;
    var path = st.localPath;
    var tmp = st.tmpPath;
    if (tmp != "" && file_exists(tmp)) file_delete(tmp);
    vs_songstore_sweep_tmp();
    st.on_done = undefined;
    st.rid = -1;
    st.gen = 0;
    st.placing = false;
    st.placeTries = 0;
    global.vs_dl_busy = false;
    if (_ok) vs_songstore_log("wrote " + vs_songstore_install_path(path));
    if (cb != undefined) { cb(_ok, path); }
    vs_songstore_dl_schedule();
}

function vs_songstore_dl_on_placed()
{
    vs_songstore_dl_init();
    if (!global.vs_dl_busy) return;
    var st = global.vs_dl_state;
    if (!variable_struct_exists(st, "placing") || !st.placing) return;
    if (vs_songstore_file_ready(st.localPath))
    {
        vs_songstore_dl_complete(true);
        return;
    }
    st.placeTries += 1;
    if (st.placeTries < 12)
    {
        call_later(8, time_source_units_frames, vs_songstore_dl_on_placed);
        return;
    }
    var clog = vs_songstore_save_dir() + "vsonline_place_cmd.log";
    if (file_exists(clog))
    {
        var cf = file_text_open_read(clog);
        var raw = "";
        if (cf >= 0)
        {
            while (!file_text_eof(cf)) { raw += file_text_readln(cf); }
            file_text_close(cf);
        }
        vs_songstore_log("place cmd: " + raw);
    }
    vs_songstore_set_err("could not write " + vs_songstore_install_path(st.localPath));
    vs_songstore_dl_complete(false);
}

function vs_songstore_dl_finish(_ok)
{
    vs_songstore_dl_init();
    var st = global.vs_dl_state;
    if (_ok)
    {
        if (vs_songstore_place_start())
        {
            st.rid = -1;
            st.placing = true;
            st.placeTries = 0;
            call_later(8, time_source_units_frames, vs_songstore_dl_on_placed);
            return;
        }
        vs_songstore_set_err("could not write " + string(st.localPath));
    }
    vs_songstore_dl_complete(false);
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
    var tmpHere = (st.tmpPath != "" && (file_exists(st.tmpPath) || file_exists(vs_songstore_tmp_abs(st.tmpPath))));
    var ok = httpOk && ((gmStatus >= 0) || doneProg || tmpHere);
    if (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel)
    {
        ok = false;
    }
    if (!ok && !httpOk) vs_songstore_set_err("http " + string(httpStatus) + " for " + string(st.url));
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
