// ============================================================================
// vs_media.gml — lazy jacket + preview for Chart Downloader
//
// http_get_file into vs_jackets/ and vs_previews/, then sprite_add /
// audio_create_stream. Only the selected row is requested. Completion is
// handled on the official HTTP event via vs_media_on_http.
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
    }
}

function vs_media_jacket(_id)
{
    vs_media_init();
    if (_id == undefined || _id == "") return -1;
    if (variable_struct_exists(global.vs_jk_fail, _id)) return -1;
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
    vs_media_pump();
}

function vs_media_select(_id, _jacketUrl, _previewUrl)
{
    vs_media_init();
    global.vs_media_want_pv = (_id == undefined) ? "" : string(_id);
    vs_media_request("jacket", _id, _jacketUrl);
    vs_media_request("preview", _id, _previewUrl);
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
    var id = global.vs_media_want_pv;
    if (id == "") return;
    if (!variable_struct_exists(global.vs_pv_snd, id)) return;
    var snd = variable_struct_get(global.vs_pv_snd, id);
    if (snd == undefined || snd < 0) return;
    if (global.vs_pv_inst != -1 && audio_is_playing(global.vs_pv_inst)) audio_stop_sound(global.vs_pv_inst);
    global.vs_pv_inst = audio_play_sound(snd, 1, false);
}

function vs_media_pump()
{
    vs_media_init();
    if (global.vs_media_busy) return;
    if (array_length(global.vs_media_q) == 0) return;
    var job = global.vs_media_q[0];
    array_delete(global.vs_media_q, 0, 1);
    var dir = (job.kind == "jacket") ? "vs_jackets/" : "vs_previews/";
    if (!directory_exists(dir)) directory_create(dir);
    var ext = (job.kind == "jacket") ? ".img" : ".ogg";
    var dest = dir + job.id + ext;
    var url = vs_songstore_abs_url(job.url);
    global.vs_media_busy = true;
    global.vs_media_kind = job.kind;
    global.vs_media_id = job.id;
    global.vs_media_path = dest;
    global.vs_media_rid = http_get_file(url, dest);
    if (global.vs_media_rid == undefined || global.vs_media_rid < 0)
    {
        vs_media_finish(false);
        return;
    }
}

function vs_media_finish(_ok)
{
    vs_media_init();
    var id = global.vs_media_id;
    var kind = global.vs_media_kind;
    var path = global.vs_media_path;
    global.vs_media_busy = false;
    global.vs_media_rid = -1;
    global.vs_media_kind = "";
    global.vs_media_id = "";
    global.vs_media_path = "";
    if (_ok && file_exists(path))
    {
        if (kind == "jacket")
        {
            var spr = sprite_add(path, 1, false, false, 0, 0);
            if (spr != -1) variable_struct_set(global.vs_jk_spr, id, spr);
            else variable_struct_set(global.vs_jk_fail, id, true);
        }
        else
        {
            var snd = audio_create_stream(path);
            if (snd != -1)
            {
                variable_struct_set(global.vs_pv_snd, id, snd);
                vs_media_try_play();
            }
            else variable_struct_set(global.vs_pv_fail, id, true);
        }
    }
    else if (id != "")
    {
        if (kind == "jacket") variable_struct_set(global.vs_jk_fail, id, true);
        else variable_struct_set(global.vs_pv_fail, id, true);
    }
    vs_media_pump();
}

function vs_media_on_http()
{
    vs_media_init();
    if (!global.vs_media_busy || global.vs_media_rid < 0) return;
    if (async_load == -1) return;
    var rid = ds_map_find_value(async_load, "id");
    if (rid == undefined || string(rid) != string(global.vs_media_rid)) return;
    var gmStatus = ds_map_find_value(async_load, "status");
    if (gmStatus == 1) return;
    var httpStatus = ds_map_find_value(async_load, "http_status");
    var httpOk = (httpStatus == undefined || (httpStatus >= 200 && httpStatus < 300));
    var ok = (gmStatus >= 0) && httpOk && file_exists(global.vs_media_path);
    vs_media_finish(ok);
}
