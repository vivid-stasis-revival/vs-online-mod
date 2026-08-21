// ============================================================================
// vs_media.gml — lazy jacket + preview for Chart Downloader
//
// Cache files go in the save area (working_directory/vs_jackets|vs_previews).
// http_get_file starts on the next frame — starting it from a JSON HTTP
// callback (list load -> selected_refresh) never completes on this runner.
// Finish only when the dest file exists (same settle as chart downloads).
// sprite_add / audio_create_stream run the frame after the file is on disk.
//
// Runtime sprite/stream handles are capped (LRU) and purged on browser close.
// Timeouts use a gen queue (same pattern as vs_http_to / vs_dl_to) so a
// stale timer cannot abort a newer download.
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
        global.vs_media_to = [];
        global.vs_jk_order = [];
        global.vs_pv_order = [];
        global.vs_media_busy = false;
        global.vs_media_rid = -1;
        global.vs_media_kind = "";
        global.vs_media_id = "";
        global.vs_media_path = "";
        global.vs_media_want_pv = "";
        global.vs_media_pin_jk = "";
        global.vs_pv_inst = -1;
        global.vs_media_scheduled = false;
        global.vs_jk_load_key = "";
        global.vs_jk_load_path = "";
        global.vs_media_gen = 0;
        global.vs_media_job_gen = 0;
        global.vs_media_place_gen = 0;
        global.vs_media_got = 0;
        global.vs_media_total = 0;
        global.vs_media_bgm_paused = false;
        global.vs_media_lobby_paused = false;
        global.vs_media_placing = false;
        global.vs_media_placeTries = 0;
    }
    if (!variable_global_exists("vs_media_to")) global.vs_media_to = [];
    if (!variable_global_exists("vs_jk_order")) global.vs_jk_order = [];
    if (!variable_global_exists("vs_pv_order")) global.vs_pv_order = [];
    if (!variable_global_exists("vs_media_place_gen")) global.vs_media_place_gen = 0;
    if (!variable_global_exists("vs_media_pin_jk")) global.vs_media_pin_jk = "";
    if (!variable_global_exists("vs_media_placing"))
    {
        global.vs_media_placing = false;
        global.vs_media_placeTries = 0;
    }
    if (!variable_global_exists("vs_media_lobby_paused")) global.vs_media_lobby_paused = false;
}

function vs_media_jk_cap()
{
    return 48;
}

function vs_media_pv_cap()
{
    return 6;
}

function vs_media_pause_home()
{
    vs_media_init();
    if (global.vs_media_bgm_paused) return;
    if (!variable_global_exists("bgm")) return;
    if (global.bgm == undefined || global.bgm < 0) return;
    if (!audio_is_playing(global.bgm)) return;
    audio_pause_sound(global.bgm);
    global.vs_media_bgm_paused = true;
}

function vs_media_pause_lobby()
{
    vs_media_init();
    if (global.vs_media_lobby_paused) return;
    if (!instance_exists(obj_multiplayer_lobby)) return;
    var paused = false;
    with (obj_multiplayer_lobby)
    {
        if (variable_instance_exists(self, "real_bgm") && real_bgm != undefined && real_bgm >= 0)
        {
            audio_pause_sound(real_bgm);
            paused = true;
        }
        if (variable_instance_exists(self, "muted_bgm") && muted_bgm != undefined && muted_bgm >= 0)
        {
            audio_pause_sound(muted_bgm);
            paused = true;
        }
    }
    if (paused) global.vs_media_lobby_paused = true;
}

function vs_media_resume_lobby()
{
    vs_media_init();
    if (!global.vs_media_lobby_paused) return;
    global.vs_media_lobby_paused = false;
    if (!instance_exists(obj_multiplayer_lobby)) return;
    with (obj_multiplayer_lobby)
    {
        if (variable_instance_exists(self, "real_bgm") && real_bgm != undefined && real_bgm >= 0)
        {
            if (audio_is_paused(real_bgm)) audio_resume_sound(real_bgm);
        }
        if (variable_instance_exists(self, "muted_bgm") && muted_bgm != undefined && muted_bgm >= 0)
        {
            if (audio_is_paused(muted_bgm)) audio_resume_sound(muted_bgm);
        }
    }
}

function vs_media_from_lobby()
{
    return variable_global_exists("vs_dlbr_from_lobby") && global.vs_dlbr_from_lobby;
}

function vs_media_resume_home()
{
    vs_media_init();
    if (global.vs_media_bgm_paused)
    {
        global.vs_media_bgm_paused = false;
        if (variable_global_exists("bgm") && global.bgm != undefined && global.bgm >= 0)
        {
            if (audio_is_paused(global.bgm)) audio_resume_sound(global.bgm);
        }
    }
    if (!vs_media_from_lobby()) vs_media_resume_lobby();
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

function vs_media_file_bytes(_path)
{
    if (_path == undefined || _path == "") return -1;
    var p = string(_path);
    if (!file_exists(p))
    {
        p = vs_media_abs(_path);
        if (!file_exists(p)) return -1;
    }
    var bin = -1;
    try { bin = file_bin_open(p, 0); } catch (_e0) { bin = -1; }
    if (bin < 0) return -1;
    var n = -1;
    try { n = file_bin_size(bin); } catch (_e1) { n = -1; }
    try { file_bin_close(bin); } catch (_e2) {}
    return n;
}

function vs_media_cache_usable(_path, _kind)
{
    var n = vs_media_file_bytes(_path);
    if (n < 0) return false;
    var minb = (_kind == "jacket") ? 64 : 256;
    return n >= minb;
}

function vs_media_delete_path(_path)
{
    if (_path == undefined || _path == "") return;
    var abs = vs_media_abs(_path);
    if (file_exists(abs))
    {
        try { file_delete(abs); } catch (_e0) {}
    }
    if (file_exists(_path))
    {
        try { file_delete(_path); } catch (_e1) {}
    }
}

function vs_media_order_touch(_order, _key)
{
    var i = 0;
    repeat (array_length(_order))
    {
        if (_order[i] == _key)
        {
            array_delete(_order, i, 1);
            break;
        }
        i++;
    }
    array_push(_order, _key);
}

function vs_media_free_sprite(_spr)
{
    if (_spr == undefined || _spr == -1) return;
    if (!sprite_exists(_spr)) return;
    try { sprite_delete(_spr); } catch (_e) {}
}

function vs_media_destroy_stream_asset(_snd)
{
    if (_snd == undefined || _snd == -1) return;
    try { audio_destroy_stream(_snd); } catch (_e1) {}
}

function vs_media_order_remove(_order, _key)
{
    var i = 0;
    repeat (array_length(_order))
    {
        if (_order[i] == _key)
        {
            array_delete(_order, i, 1);
            return;
        }
        i++;
    }
}

function vs_media_drop_jacket(_key)
{
    if (_key == undefined || _key == "") return;
    vs_media_order_remove(global.vs_jk_order, _key);
    if (!variable_struct_exists(global.vs_jk_spr, _key)) return;
    var spr = variable_struct_get(global.vs_jk_spr, _key);
    variable_struct_remove(global.vs_jk_spr, _key);
    vs_media_free_sprite(spr);
}

function vs_media_drop_preview(_key)
{
    if (_key == undefined || _key == "") return;
    vs_media_order_remove(global.vs_pv_order, _key);
    if (global.vs_media_want_pv == _key)
    {
        if (global.vs_pv_inst != -1)
        {
            if (audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
            global.vs_pv_inst = -1;
        }
        global.vs_media_want_pv = "";
    }
    if (!variable_struct_exists(global.vs_pv_snd, _key)) return;
    var snd = variable_struct_get(global.vs_pv_snd, _key);
    variable_struct_remove(global.vs_pv_snd, _key);
    vs_media_destroy_stream_asset(snd);
}

function vs_media_evict_jackets()
{
    vs_media_init();
    var maxn = vs_media_jk_cap();
    var skips = 0;
    while (array_length(global.vs_jk_order) > maxn)
    {
        var old = global.vs_jk_order[0];
        array_delete(global.vs_jk_order, 0, 1);
        // Keep the currently selected / detail jacket visible.
        if (old == global.vs_media_pin_jk || old == global.vs_media_want_pv)
        {
            array_push(global.vs_jk_order, old);
            skips += 1;
            if (skips > array_length(global.vs_jk_order)) break;
            continue;
        }
        skips = 0;
        vs_media_drop_jacket(old);
    }
}

function vs_media_evict_previews()
{
    vs_media_init();
    var maxn = vs_media_pv_cap();
    var skips = 0;
    while (array_length(global.vs_pv_order) > maxn)
    {
        var old = global.vs_pv_order[0];
        array_delete(global.vs_pv_order, 0, 1);
        if (old == global.vs_media_want_pv)
        {
            array_push(global.vs_pv_order, old);
            skips += 1;
            if (skips > array_length(global.vs_pv_order)) break;
            continue;
        }
        skips = 0;
        vs_media_drop_preview(old);
    }
}

function vs_media_remember_jacket(_key, _spr)
{
    if (_key == undefined || _key == "" || _spr == undefined || _spr == -1) return;
    if (!sprite_exists(_spr)) return;
    if (variable_struct_exists(global.vs_jk_spr, _key))
    {
        var prev = variable_struct_get(global.vs_jk_spr, _key);
        if (prev != _spr) vs_media_free_sprite(prev);
    }
    variable_struct_set(global.vs_jk_spr, _key, _spr);
    vs_media_order_touch(global.vs_jk_order, _key);
    vs_media_evict_jackets();
}

function vs_media_remember_preview(_key, _snd)
{
    if (_key == undefined || _key == "" || _snd == undefined || _snd == -1) return;
    if (variable_struct_exists(global.vs_pv_snd, _key))
    {
        var prev = variable_struct_get(global.vs_pv_snd, _key);
        if (prev != _snd)
        {
            if (global.vs_media_want_pv == _key && global.vs_pv_inst != -1)
            {
                if (audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
                global.vs_pv_inst = -1;
            }
            vs_media_destroy_stream_asset(prev);
        }
    }
    variable_struct_set(global.vs_pv_snd, _key, _snd);
    vs_media_order_touch(global.vs_pv_order, _key);
    vs_media_evict_previews();
}

// Free GPU/audio handles; disk cache under vs_jackets/ / vs_previews/ is kept.
function vs_media_purge_cache()
{
    vs_media_init();
    if (global.vs_pv_inst != -1)
    {
        if (audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
        global.vs_pv_inst = -1;
    }
    global.vs_media_want_pv = "";
    global.vs_media_pin_jk = "";
    var jkNames = variable_struct_get_names(global.vs_jk_spr);
    var ji = 0;
    repeat (array_length(jkNames))
    {
        vs_media_drop_jacket(jkNames[ji]);
        ji++;
    }
    var pvNames = variable_struct_get_names(global.vs_pv_snd);
    var pvi = 0;
    repeat (array_length(pvNames))
    {
        vs_media_drop_preview(pvNames[pvi]);
        pvi++;
    }
    global.vs_jk_spr = {};
    global.vs_pv_snd = {};
    global.vs_jk_fail = {};
    global.vs_pv_fail = {};
    global.vs_jk_order = [];
    global.vs_pv_order = [];
    global.vs_jk_load_key = "";
    global.vs_jk_load_path = "";
    vs_media_resume_home();
}

function vs_media_jacket(_id)
{
    vs_media_init();
    if (_id == undefined || _id == "") return -1;
    if (variable_struct_exists(global.vs_jk_spr, _id))
    {
        vs_media_order_touch(global.vs_jk_order, _id);
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
        if (variable_struct_exists(global.vs_jk_spr, _id))
        {
            vs_media_order_touch(global.vs_jk_order, _id);
            return;
        }
        if (variable_struct_exists(global.vs_jk_fail, _id)) variable_struct_set(global.vs_jk_fail, _id, false);
    }
    else
    {
        if (variable_struct_exists(global.vs_pv_snd, _id))
        {
            vs_media_order_touch(global.vs_pv_order, _id);
            return;
        }
        if (variable_struct_exists(global.vs_pv_fail, _id)) variable_struct_set(global.vs_pv_fail, _id, false);
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

// Only real preview URLs — never invent music.ogg (full-track streams hitch + leak).
function vs_media_audio_url(_previewUrl, _jacketUrl, _id)
{
    if (_previewUrl != undefined && string(_previewUrl) != "") return string(_previewUrl);
    return "";
}

function vs_media_cancel()
{
    vs_media_init();
    // Drop in-progress download so a later cache hit cannot use a truncated file.
    if (global.vs_media_busy && global.vs_media_path != "")
        vs_media_delete_path(global.vs_media_path);
    global.vs_media_q = [];
    global.vs_media_gen += 1;
    global.vs_media_want_pv = "";
    global.vs_media_pin_jk = "";
    if (global.vs_pv_inst != -1)
    {
        if (audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
        global.vs_pv_inst = -1;
    }
    global.vs_jk_load_key = "";
    global.vs_jk_load_path = "";
    global.vs_media_busy = false;
    global.vs_media_rid = -1;
    global.vs_media_kind = "";
    global.vs_media_id = "";
    global.vs_media_path = "";
    global.vs_media_placing = false;
    global.vs_media_placeTries = 0;
    global.vs_media_got = 0;
    global.vs_media_total = 0;
    global.vs_media_scheduled = false;
}

function vs_media_select(_id, _jacketUrl, _previewUrl)
{
    vs_media_init();
    if (!instance_exists(vs_downloader_browser)) return;
    global.vs_media_pin_jk = (_id == undefined) ? "" : string(_id);
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
    vs_media_resume_home();
}

function vs_media_try_play()
{
    vs_media_init();
    if (!instance_exists(vs_downloader_browser)) return;
    var key = global.vs_media_want_pv;
    if (key == "") return;
    if (!variable_struct_exists(global.vs_pv_snd, key)) return;
    var snd = variable_struct_get(global.vs_pv_snd, key);
    if (snd == undefined || snd < 0) return;
    if (global.vs_pv_inst != -1 && audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
    global.vs_pv_inst = audio_play_sound(snd, 1, false);
    vs_media_order_touch(global.vs_pv_order, key);
    vs_media_pause_home();
    vs_media_pause_lobby();
}

function vs_media_poll()
{
    vs_media_init();
    if (global.vs_pv_inst == -1) return;
    if (audio_is_playing(global.vs_pv_inst)) return;
    global.vs_pv_inst = -1;
    vs_media_resume_home();
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
        if (!vs_media_cache_usable(path, "jacket"))
        {
            vs_media_delete_path(path);
            variable_struct_set(global.vs_jk_fail, key, true);
        }
        else
        {
            var spr = -1;
            var abs = vs_media_abs(path);
            if (file_exists(abs)) spr = sprite_add(abs, 1, false, false, 0, 0);
            if ((spr == -1 || !sprite_exists(spr)) && file_exists(path)) spr = sprite_add(path, 1, false, false, 0, 0);
            if (spr != -1 && sprite_exists(spr)) vs_media_remember_jacket(key, spr);
            else
            {
                vs_media_delete_path(path);
                variable_struct_set(global.vs_jk_fail, key, true);
            }
        }
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
    global.vs_media_placing = false;
    global.vs_media_placeTries = 0;
    if (vs_media_cache_usable(dest, job.kind))
    {
        vs_media_finish(true);
        return;
    }
    // Stale / truncated download left on disk — force a fresh fetch.
    if (file_exists(vs_media_abs(dest)) || file_exists(dest)) vs_media_delete_path(dest);
    var url = vs_songstore_abs_url(job.url);
    global.vs_media_gen += 1;
    global.vs_media_job_gen = global.vs_media_gen;
    global.vs_media_rid = http_get_file(url, dest);
    if (global.vs_media_rid == undefined || global.vs_media_rid < 0)
    {
        vs_media_finish(false);
        return;
    }
    array_push(global.vs_media_to, global.vs_media_job_gen);
    call_later(60 * 30, time_source_units_frames, vs_media_on_timeout);
    show_debug_message("VS Media: start " + string(job.kind) + " " + string(job.id) + " url=" + url);
}

function vs_media_on_timeout()
{
    vs_media_init();
    if (!variable_global_exists("vs_media_to") || array_length(global.vs_media_to) == 0) return;
    var g = global.vs_media_to[0];
    array_delete(global.vs_media_to, 0, 1);
    if (!global.vs_media_busy) return;
    if (global.vs_media_job_gen != g) return;
    show_debug_message("VS Media: timeout " + string(global.vs_media_kind) + " " + string(global.vs_media_id));
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
    global.vs_media_placing = false;
    global.vs_media_placeTries = 0;
    if (_ok && key != "" && !vs_media_cache_usable(path, kind))
    {
        _ok = false;
    }
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
                vs_media_remember_preview(key, snd);
                vs_media_try_play();
            }
            else
            {
                vs_media_delete_path(path);
                variable_struct_set(global.vs_pv_fail, key, true);
            }
        }
    }
    else if (key != "")
    {
        vs_media_delete_path(path);
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
        if (file_exists(p) && vs_media_cache_usable(p, "jacket")) spr = sprite_add(p, 1, false, false, 0, 0);
        if ((spr == -1 || !sprite_exists(spr)) && file_exists(vs_media_abs(p)) && vs_media_cache_usable(vs_media_abs(p), "jacket"))
        {
            spr = sprite_add(vs_media_abs(p), 1, false, false, 0, 0);
        }
        if (spr != -1 && sprite_exists(spr))
        {
            vs_media_remember_jacket(_key, spr);
            return;
        }
        i++;
    }
}

function vs_media_wait_file()
{
    if (global.vs_media_placing) return;
    global.vs_media_placing = true;
    global.vs_media_placeTries = 0;
    global.vs_media_place_gen = global.vs_media_job_gen;
    call_later(1, time_source_units_frames, vs_media_on_place);
}

function vs_media_on_place()
{
    vs_media_init();
    if (!global.vs_media_busy || !global.vs_media_placing) return;
    if (global.vs_media_place_gen != global.vs_media_job_gen) return;
    if (vs_http_file_here(global.vs_media_path) || file_exists(vs_media_abs(global.vs_media_path)))
    {
        show_debug_message("VS Media: file ready " + string(global.vs_media_kind) + " " + string(global.vs_media_id));
        vs_media_finish(true);
        return;
    }
    global.vs_media_placeTries += 1;
    if (global.vs_media_placeTries >= 45)
    {
        show_debug_message("VS Media: file missing " + string(global.vs_media_kind) + " " + string(global.vs_media_id));
        vs_media_finish(false);
        return;
    }
    call_later(1, time_source_units_frames, vs_media_on_place);
}

function vs_media_on_http()
{
    vs_media_init();
    if (!global.vs_media_busy || global.vs_media_rid < 0) return;
    if (async_load == -1) return;
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || string(rid) != string(global.vs_media_rid)) return;
    var gmStatus = vs_http_num(ds_map_find_value(async_load, "status"), -1);
    var got = vs_http_num(ds_map_find_value(async_load, "sizeDownloaded"), -1);
    var tot = vs_http_num(ds_map_find_value(async_load, "contentLength"), -1);
    if (got >= 0) global.vs_media_got = got;
    if (tot >= 0) global.vs_media_total = tot;
    var doneProg = (global.vs_media_total > 0 && global.vs_media_got >= global.vs_media_total);
    var here = vs_http_file_here(global.vs_media_path) || file_exists(vs_media_abs(global.vs_media_path));
    var httpStatus = vs_http_num(ds_map_find_value(async_load, "http_status"), -1);
    var settle = vs_http_file_settle(gmStatus, httpStatus, here, doneProg);
    if (settle == 0)
    {
        if (doneProg || gmStatus == 0) vs_media_wait_file();
        return;
    }
    var ok = (settle > 0);
    show_debug_message("VS Media: done " + string(global.vs_media_kind) + " " + string(global.vs_media_id) + " ok=" + string(ok) + " http=" + string(httpStatus) + " st=" + string(gmStatus));
    vs_media_finish(ok);
}
