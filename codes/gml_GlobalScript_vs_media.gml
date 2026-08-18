// ============================================================================
// vs_media.gml — lazy jacket + preview for Chart Downloader
//
// Cache files go in the save area (working_directory/vs_jackets|vs_previews).
// http_get_file starts on the next frame — starting it from a JSON HTTP
// callback (list load -> selected_refresh) never completes on this runner.
// HTTP completion matches chart downloads: status 0, or status 1 with
// sizeDownloaded >= contentLength. sprite_add / audio_create_stream run
// the frame after the file is on disk.
// ============================================================================

function vs_media_init()
{
    if (!variable_global_exists("vs_jk_spr"))
    {
        global.vs_jk_spr = {};
        global.vs_jk_fail = {};
        global.vs_pv_snd = {};
        global.vs_pv_fail = {};
        global.vs_media_q = [];
        global.vs_media_busy = false;
        global.vs_media_rid = -1;
        global.vs_media_kind = "";
        global.vs_media_id = "";
        global.vs_media_path = "";
        global.vs_media_want_pv = "";
        global.vs_pv_inst = -1;
        global.vs_media_scheduled = false;
        global.vs_jk_load_key = "";
        global.vs_jk_load_path = "";
        global.vs_media_gen = 0;
        global.vs_media_got = 0;
        global.vs_media_total = 0;
    }
}

function vs_media_abs(_rel)
{
    if (_rel == undefined || _rel == "") return "";
    var p = string(_rel);
    if (string_pos(":", p) > 0) return p;
    return working_directory + p;
}

function vs_media_ext(_url)
{
    var u = string_lower(string(_url));
    var qpos = string_pos("?", u);
    if (qpos > 0) u = string_copy(u, 1, qpos - 1);
    if (vs_songstore_ends_with(u, ".png")) return ".png";
    if (vs_songstore_ends_with(u, ".jpg") || vs_songstore_ends_with(u, ".jpeg")) return ".jpg";
    if (vs_songstore_ends_with(u, ".gif")) return ".gif";
    return ".png";
}

function vs_media_audio_ext(_url)
{
    var u = string_lower(string(_url));
    var qpos = string_pos("?", u);
    if (qpos > 0) u = string_copy(u, 1, qpos - 1);
    if (vs_songstore_ends_with(u, ".mp3")) return ".mp3";
    if (vs_songstore_ends_with(u, ".wav")) return ".wav";
    return ".ogg";
}

function vs_media_file_key(_id)
{
    var k = string_replace_all(string(_id), "/", "_");
    k = string_replace_all(k, "\\", "_");
    return k;
}

function vs_media_jacket(_id)
{
    vs_media_init();
    if (_id == undefined || _id == "") return -1;
    if (variable_struct_exists(global.vs_jk_spr, _id))
    {
        return variable_struct_get(global.vs_jk_spr, _id);
    }
    return -1;
}

function vs_media_request(_kind, _id, _url)
{
    vs_media_init();
    if (_id == undefined || _id == "" || _url == undefined || _url == "") return;
    if (_kind == "jacket")
    {
        if (variable_struct_exists(global.vs_jk_spr, _id) || variable_struct_exists(global.vs_jk_fail, _id)) return;
    }
    else
    {
        if (variable_struct_exists(global.vs_pv_snd, _id) || variable_struct_exists(global.vs_pv_fail, _id)) return;
    }
    var i = 0;
    repeat (array_length(global.vs_media_q))
    {
        var j = global.vs_media_q[i];
        if (j.id == _id && j.kind == _kind) return;
        i++;
    }
    if (global.vs_media_busy && global.vs_media_id == _id && global.vs_media_kind == _kind) return;
    array_push(global.vs_media_q, { kind: _kind, id: _id, url: _url });
    vs_media_schedule();
}

function vs_media_audio_url(_previewUrl, _jacketUrl, _id)
{
    if (_previewUrl != undefined && string(_previewUrl) != "") return string(_previewUrl);
    var u = (_jacketUrl != undefined) ? string(_jacketUrl) : "";
    var cut = string_last_pos("/", u);
    if (cut > 0) return string_copy(u, 1, cut) + "music.ogg";
    if (_id == undefined || string(_id) == "") return "";
    return vs_online_server_url() + "/uploads/songs/" + string(_id) + "/music.ogg";
}

function vs_media_select(_id, _jacketUrl, _previewUrl)
{
    vs_media_init();
    vs_media_request("jacket", _id, _jacketUrl);
    var audio = vs_media_audio_url(_previewUrl, _jacketUrl, _id);
    if (audio != "") vs_media_request("preview", _id, audio);
    if (!vs_online_preview_auto())
    {
        if (global.vs_media_want_pv != "") vs_media_stop_preview();
        return;
    }
    global.vs_media_want_pv = (_id == undefined) ? "" : string(_id);
    vs_media_try_play();
}

function vs_media_stop_preview()
{
    vs_media_init();
    if (global.vs_pv_inst != -1)
    {
        if (audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
        global.vs_pv_inst = -1;
    }
    global.vs_media_want_pv = "";
}

function vs_media_try_play()
{
    vs_media_init();
    var key = global.vs_media_want_pv;
    if (key == "") return;
    if (!variable_struct_exists(global.vs_pv_snd, key)) return;
    var snd = variable_struct_get(global.vs_pv_snd, key);
    if (snd == undefined || snd < 0) return;
    if (global.vs_pv_inst != -1 && audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
    global.vs_pv_inst = audio_play_sound(snd, 1, false);
}

function vs_media_schedule()
{
    vs_media_init();
    if (global.vs_media_scheduled) return;
    global.vs_media_scheduled = true;
    call_later(1, time_source_units_frames, vs_media_on_later);
}

function vs_media_on_later()
{
    vs_media_init();
    global.vs_media_scheduled = false;
    if (global.vs_jk_load_path != "")
    {
        var key = global.vs_jk_load_key;
        var path = global.vs_jk_load_path;
        global.vs_jk_load_key = "";
        global.vs_jk_load_path = "";
        var spr = -1;
        var abs = vs_media_abs(path);
        if (file_exists(abs)) spr = sprite_add(abs, 1, false, false, 0, 0);
        if ((spr == -1 || !sprite_exists(spr)) && file_exists(path)) spr = sprite_add(path, 1, false, false, 0, 0);
        if (spr != -1 && sprite_exists(spr)) variable_struct_set(global.vs_jk_spr, key, spr);
        else variable_struct_set(global.vs_jk_fail, key, true);
    }
    vs_media_start();
}

function vs_media_start()
{
    vs_media_init();
    if (global.vs_media_busy) return;
    if (array_length(global.vs_media_q) == 0) return;
    var job = global.vs_media_q[0];
    array_delete(global.vs_media_q, 0, 1);
    var dir = (job.kind == "jacket") ? "vs_jackets/" : "vs_previews/";
    if (!directory_exists(dir)) directory_create(dir);
    var ext = (job.kind == "jacket") ? vs_media_ext(job.url) : vs_media_audio_ext(job.url);
    var dest = dir + vs_media_file_key(job.id) + ext;
    global.vs_media_busy = true;
    global.vs_media_kind = job.kind;
    global.vs_media_id = job.id;
    global.vs_media_path = dest;
    global.vs_media_got = 0;
    global.vs_media_total = 0;
    if (file_exists(vs_media_abs(dest)) || file_exists(dest))
    {
        vs_media_finish(true);
        return;
    }
    var url = vs_songstore_abs_url(job.url);
    global.vs_media_gen += 1;
    global.vs_media_rid = http_get_file(url, dest);
    if (global.vs_media_rid == undefined || global.vs_media_rid < 0)
    {
        vs_media_finish(false);
        return;
    }
    call_later(60 * 30, time_source_units_frames, vs_media_on_timeout);
    show_debug_message("VS Media: start " + string(job.kind) + " " + string(job.id) + " url=" + url);
}

function vs_media_on_timeout()
{
    vs_media_init();
    if (!global.vs_media_busy) return;
    vs_media_finish(false);
}

function vs_media_finish(_ok)
{
    vs_media_init();
    var key = global.vs_media_id;
    var kind = global.vs_media_kind;
    var path = global.vs_media_path;
    global.vs_media_busy = false;
    global.vs_media_rid = -1;
    global.vs_media_kind = "";
    global.vs_media_id = "";
    global.vs_media_path = "";
    if (_ok && key != "")
    {
        if (kind == "jacket")
        {
            global.vs_jk_load_key = key;
            global.vs_jk_load_path = path;
        }
        else
        {
            var snd = -1;
            var abs = vs_media_abs(path);
            if (file_exists(abs)) snd = audio_create_stream(abs);
            if ((snd == -1 || snd == undefined) && file_exists(path)) snd = audio_create_stream(path);
            if (snd != -1 && snd != undefined)
            {
                variable_struct_set(global.vs_pv_snd, key, snd);
                vs_media_try_play();
            }
            else variable_struct_set(global.vs_pv_fail, key, true);
        }
    }
    else if (key != "")
    {
        if (kind == "jacket") variable_struct_set(global.vs_jk_fail, key, true);
        else variable_struct_set(global.vs_pv_fail, key, true);
    }
    vs_media_schedule();
}

function vs_media_load_folder(_key, _dir)
{
    vs_media_init();
    if (_key == undefined || _key == "" || _dir == undefined || _dir == "") return;
    if (variable_struct_exists(global.vs_jk_spr, _key) || variable_struct_exists(global.vs_jk_fail, _key)) return;
    var names = ["jacket.png", "jacket.jpg", "jacket.jpeg", "jacket.gif"];
    var i = 0;
    repeat (4)
    {
        var p = _dir + names[i];
        var spr = -1;
        if (file_exists(p)) spr = sprite_add(p, 1, false, false, 0, 0);
        if ((spr == -1 || !sprite_exists(spr)) && file_exists(vs_media_abs(p)))
        {
            spr = sprite_add(vs_media_abs(p), 1, false, false, 0, 0);
        }
        if (spr != -1 && sprite_exists(spr))
        {
            variable_struct_set(global.vs_jk_spr, _key, spr);
            return;
        }
        i++;
    }
}

function vs_media_on_http()
{
    vs_media_init();
    if (!global.vs_media_busy || global.vs_media_rid < 0) return;
    if (async_load == -1) return;
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || string(rid) != string(global.vs_media_rid)) return;
    var gmStatus = ds_map_find_value(async_load, "status");
    var got = ds_map_find_value(async_load, "sizeDownloaded");
    var tot = ds_map_find_value(async_load, "contentLength");
    if (got != undefined) global.vs_media_got = real(got);
    if (tot != undefined) global.vs_media_total = real(tot);
    var doneProg = (global.vs_media_total > 0 && global.vs_media_got >= global.vs_media_total);
    if (gmStatus == 1 && !doneProg)
    {
        return;
    }
    var httpStatus = ds_map_find_value(async_load, "http_status");
    var httpOk = (httpStatus == undefined || (httpStatus >= 200 && httpStatus < 300));
    var ok = ((gmStatus >= 0) || doneProg) && httpOk;
    show_debug_message("VS Media: done " + string(global.vs_media_kind) + " " + string(global.vs_media_id) + " ok=" + string(ok) + " http=" + string(httpStatus) + " st=" + string(gmStatus));
    vs_media_finish(ok);
}
