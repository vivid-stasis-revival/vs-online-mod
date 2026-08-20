// ============================================================================
// vs_packmgr.gml — local pack subscriptions (chartId lists, loose songs).
//
// Songs stay in Custom Songs/<chart_id>/. Pack metadata is written from
// GET /api/v1/packs/:id as Custom Songs/pack-<id>/songpack_info.json — the
// same JSON GET /packs/:id/package puts in the zip — so CSM sees a pack and
// sha1_file() can track name/description/colors.
// Local state is working_directory/vsonline.packs.json:
//   [{ id, name, description, color1, color2, version, infoSha1, songs: [{ id, chartId, kind, name }] }]
// kind 0 = song, 2 = shatter. Unsub removes the list and the info file,
// never the song folders.
// ============================================================================

function vs_packmgr_path()
{
    return working_directory + "vsonline.packs.json";
}

function vs_packmgr_load()
{
    var path = vs_packmgr_path();
    if (!file_exists(path)) return [];
    var f = file_text_open_read(path);
    var raw = "";
    while (!file_text_eof(f)) { raw += file_text_readln(f); }
    file_text_close(f);
    try
    {
        var j = json_parse(raw);
        if (j != undefined && is_array(j)) return j;
    }
    catch (_e) { }
    return [];
}

function vs_packmgr_save(_list)
{
    var fw = file_text_open_write(vs_packmgr_path());
    file_text_write_string(fw, json_stringify(_list));
    file_text_close(fw);
}

function vs_packmgr_get(_packId)
{
    var pid = string(_packId);
    if (pid == "") return undefined;
    var list = vs_packmgr_load();
    var i = 0;
    repeat (array_length(list))
    {
        var e = list[i];
        if (e != undefined && variable_struct_exists(e, "id") && string(e.id) == pid)
        {
            return e;
        }
        i++;
    }
    return undefined;
}

function vs_packmgr_subscribed(_packId)
{
    return vs_packmgr_get(_packId) != undefined;
}

function vs_packmgr_upsert(_pack)
{
    if (_pack == undefined || !variable_struct_exists(_pack, "id")) return;
    var pid = string(_pack.id);
    if (pid == "") return;
    var list = vs_packmgr_load();
    var out = [];
    var i = 0;
    repeat (array_length(list))
    {
        var e = list[i];
        if (e == undefined || !variable_struct_exists(e, "id") || string(e.id) != pid)
        {
            array_push(out, e);
        }
        i++;
    }
    array_push(out, _pack);
    vs_packmgr_save(out);
}

function vs_packmgr_unsub(_packId)
{
    var pid = string(_packId);
    if (pid == "") return;
    var list = vs_packmgr_load();
    var out = [];
    var i = 0;
    repeat (array_length(list))
    {
        var e = list[i];
        if (e == undefined || !variable_struct_exists(e, "id") || string(e.id) != pid)
        {
            array_push(out, e);
        }
        i++;
    }
    vs_packmgr_save(out);
    vs_songstore_destroy_dir(vs_packmgr_dir(pid));
}

function vs_packmgr_folder(_packId)
{
    return "pack-" + string(_packId);
}

function vs_packmgr_dir(_packId)
{
    return vs_songstore_root() + vs_packmgr_folder(_packId) + "/";
}

function vs_packmgr_id_from_folder(_name)
{
    var n = string(_name);
    if (string_starts_with(n, "pack-") && string_length(n) > 5)
        return string_copy(n, 6, string_length(n) - 5);
    return "";
}

function vs_packmgr_info_struct(_data)
{
    var s = { name: "", description: "", color1: 0, color2: 0 };
    if (_data == undefined) return s;
    if (variable_struct_exists(_data, "name")) s.name = string(_data.name);
    if (variable_struct_exists(_data, "description")) s.description = string(_data.description);
    s.color1 = floor(vs_csm_safe_real(struct_get_fallback(_data, "color1", 0), 0));
    s.color2 = floor(vs_csm_safe_real(struct_get_fallback(_data, "color2", 0), 0));
    return s;
}

function vs_packmgr_info_json(_data)
{
    return json_stringify(vs_packmgr_info_struct(_data));
}

function vs_packmgr_info_path(_packId)
{
    return vs_packmgr_dir(_packId) + "songpack_info.json";
}

function vs_packmgr_info_sha1(_packId)
{
    var p = vs_packmgr_info_path(_packId);
    if (file_exists(p)) return sha1_file(p);
    var abs = vs_songstore_install_path(p);
    if (file_exists(abs)) return sha1_file(abs);
    return "";
}

function vs_packmgr_write_info(_packId, _data)
{
    var pid = string(_packId);
    if (pid == "") return "";
    var dir = vs_packmgr_dir(pid);
    vs_songstore_ensure_dir(dir);
    var raw = vs_packmgr_info_json(_data);
    var fw = file_text_open_write(dir + "songpack_info.json");
    if (fw < 0) return "";
    file_text_write_string(fw, raw);
    file_text_close(fw);
    return vs_packmgr_info_sha1(pid);
}

function vs_packmgr_info_stale(_packId, _data)
{
    var expectSha = sha1_string_utf8(vs_packmgr_info_json(_data));
    var localSha = vs_packmgr_info_sha1(_packId);
    if (localSha != "" && localSha == expectSha) return false;
    var p = vs_packmgr_info_path(_packId);
    var local = vs_csm_read_json_file(p);
    if (local == undefined) local = vs_csm_read_json_file(vs_songstore_install_path(p));
    if (local == undefined) return true;
    var expect = vs_packmgr_info_struct(_data);
    if (string(struct_get_fallback(local, "name", "")) != expect.name) return true;
    if (string(struct_get_fallback(local, "description", "")) != expect.description) return true;
    if (floor(vs_csm_safe_real(struct_get_fallback(local, "color1", 0), 0)) != expect.color1) return true;
    if (floor(vs_csm_safe_real(struct_get_fallback(local, "color2", 0), 0)) != expect.color2) return true;
    return false;
}

function vs_packmgr_read_info_file(_packId)
{
    var p = vs_packmgr_info_path(_packId);
    var j = vs_csm_read_json_file(p);
    if (j == undefined) j = vs_csm_read_json_file(vs_songstore_install_path(p));
    return j;
}

// Song-select copy: disk songpack_info.json, then vsonline.packs.json, then
// the "Online pack." placeholder only if nothing was stored.
function vs_packmgr_display_meta(_packId, _entry)
{
    var s = { name: "", description: "", color1: 8388479, color2: 16776960 };
    var disk = vs_packmgr_info_struct(vs_packmgr_read_info_file(_packId));
    if (disk.name != "") s.name = disk.name;
    if (disk.description != "") s.description = disk.description;
    if (disk.name != "" || disk.description != "" || disk.color1 != 0 || disk.color2 != 0)
    {
        s.color1 = disk.color1;
        s.color2 = disk.color2;
    }
    if (_entry != undefined)
    {
        if (s.name == "" && variable_struct_exists(_entry, "name")) s.name = string(_entry.name);
        if (s.description == "" && variable_struct_exists(_entry, "description"))
            s.description = string(_entry.description);
        if (variable_struct_exists(_entry, "color1"))
            s.color1 = floor(vs_csm_safe_real(_entry.color1, s.color1));
        if (variable_struct_exists(_entry, "color2"))
            s.color2 = floor(vs_csm_safe_real(_entry.color2, s.color2));
    }
    if (s.name == "") s.name = string(_packId);
    if (s.description == "") s.description = "Online pack.";
    return s;
}

function vs_packmgr_store_meta(_packId, _info)
{
    var pid = string(_packId);
    if (pid == "" || _info == undefined) return;
    vs_packmgr_write_info(pid, _info);
    var local = vs_packmgr_get(pid);
    if (local == undefined) return;
    local.name = _info.name;
    local.description = _info.description;
    local.color1 = _info.color1;
    local.color2 = _info.color2;
    vs_packmgr_upsert(local);
}

function vs_packmgr_csm_has(_packId)
{
    var pid = string(_packId);
    if (pid == "" || !variable_global_exists("custom_song_packs")) return false;
    var i = 0;
    repeat (array_length(global.custom_song_packs))
    {
        var pk = global.custom_song_packs[i];
        if (pk != undefined && variable_struct_exists(pk, "vs_pack_id") && string(pk.vs_pack_id) == pid)
            return true;
        i++;
    }
    return false;
}

function vs_packmgr_csm_fill(_packInfo, _packId)
{
    if (_packInfo == undefined) return;
    var local = vs_packmgr_get(_packId);
    var meta = vs_packmgr_display_meta(_packId, local);
    _packInfo.name = meta.name;
    _packInfo.description = meta.description;
    _packInfo.color1 = meta.color1;
    _packInfo.color2 = meta.color2;
    if (local == undefined || !variable_struct_exists(local, "songs") || !is_array(local.songs)) return;
    if (!variable_struct_exists(_packInfo, "songs") || !is_array(_packInfo.songs))
        _packInfo.songs = [];
    var have = {};
    var i = 0;
    repeat (array_length(_packInfo.songs))
    {
        var sid0 = _packInfo.songs[i];
        if (is_real(sid0) && sid0 >= 0 && sid0 < array_length(global.song_list))
        {
            var cid0 = string_lower(string(struct_get_fallback(global.song_list[sid0], "chart_id", "")));
            if (cid0 != "") variable_struct_set(have, cid0, true);
        }
        i++;
    }
    i = 0;
    repeat (array_length(local.songs))
    {
        var m = local.songs[i];
        var kind = (m != undefined && variable_struct_exists(m, "kind")) ? m.kind : 0;
        if (m != undefined && kind != 2 && variable_struct_exists(m, "chartId"))
        {
            var cid = string_lower(string(m.chartId));
            var sid = vs_csm_song_index(string(m.chartId));
            if (sid >= 0 && (cid == "" || !variable_struct_exists(have, cid)))
            {
                array_push(_packInfo.songs, sid);
                if (cid != "") variable_struct_set(have, cid, true);
            }
        }
        i++;
    }
}

function vs_packmgr_chart_pack_map()
{
    var out = {};
    var list = vs_packmgr_load();
    var i = 0;
    repeat (array_length(list))
    {
        var e = list[i];
        if (e != undefined && variable_struct_exists(e, "songs") && is_array(e.songs))
        {
            var pname = variable_struct_exists(e, "name") ? string(e.name) : "";
            if (pname == "" && variable_struct_exists(e, "id")) pname = string(e.id);
            var j = 0;
            repeat (array_length(e.songs))
            {
                var s = e.songs[j];
                if (s != undefined && variable_struct_exists(s, "chartId"))
                {
                    var cid = string_lower(string(s.chartId));
                    if (cid != "" && pname != "" && !variable_struct_exists(out, cid))
                        variable_struct_set(out, cid, pname);
                }
                j++;
            }
        }
        i++;
    }
    return out;
}

function vs_packmgr_chart_pack_name(_chartId)
{
    var cid = string_lower(string(_chartId));
    if (cid == "") return "";
    var map = vs_packmgr_chart_pack_map();
    if (variable_struct_exists(map, cid)) return variable_struct_get(map, cid);
    return "";
}

// Push subscribed online packs into global.custom_song_packs (before All
// Custom Songs). Members stay in the catch-all list too, like a CSM folder pack.
function vs_packmgr_csm_append()
{
    if (!variable_global_exists("custom_song_packs") || !variable_global_exists("song_list"))
        return;
    var list = vs_packmgr_load();
    var i = 0;
    repeat (array_length(list))
    {
        var e = list[i];
        if (e != undefined && variable_struct_exists(e, "id") && variable_struct_exists(e, "songs") && is_array(e.songs))
        {
            if (vs_packmgr_csm_has(string(e.id)))
            {
                i++;
                continue;
            }
            var songs = [];
            var j = 0;
            repeat (array_length(e.songs))
            {
                var m = e.songs[j];
                var kind = (m != undefined && variable_struct_exists(m, "kind")) ? m.kind : 0;
                if (m != undefined && kind != 2 && variable_struct_exists(m, "chartId"))
                {
                    var sid = vs_csm_song_index(string(m.chartId));
                    if (sid >= 0) array_push(songs, sid);
                }
                j++;
            }
            if (array_length(songs) > 0)
            {
                var meta = vs_packmgr_display_meta(string(e.id), e);
                array_push(global.custom_song_packs,
                {
                    name: meta.name,
                    songs: songs,
                    color1: meta.color1,
                    color2: meta.color2,
                    description: meta.description,
                    vs_pack_id: string(e.id)
                });
            }
        }
        i++;
    }
}

function vs_packmgr_chart_refs(_chartId)
{
    var cid = string(_chartId);
    if (cid == "") return 0;
    var list = vs_packmgr_load();
    var n = 0;
    var i = 0;
    repeat (array_length(list))
    {
        var e = list[i];
        if (e != undefined && variable_struct_exists(e, "songs") && is_array(e.songs))
        {
            var j = 0;
            repeat (array_length(e.songs))
            {
                var s = e.songs[j];
                if (s != undefined && variable_struct_exists(s, "chartId") && string(s.chartId) == cid)
                {
                    n++;
                    break;
                }
                j++;
            }
        }
        i++;
    }
    return n;
}

function vs_packmgr_members_from_detail(_data)
{
    var out = [];
    if (_data == undefined) return out;
    if (variable_struct_exists(_data, "songs") && is_array(_data.songs))
    {
        var i = 0;
        repeat (array_length(_data.songs))
        {
            var s = _data.songs[i];
            if (s != undefined && variable_struct_exists(s, "chartId"))
            {
                array_push(out,
                {
                    id: variable_struct_exists(s, "id") ? s.id : "",
                    chartId: string(s.chartId),
                    kind: 0,
                    name: variable_struct_exists(s, "name") ? s.name : string(s.chartId)
                });
            }
            i++;
        }
    }
    if (variable_struct_exists(_data, "shatters") && is_array(_data.shatters))
    {
        var k = 0;
        repeat (array_length(_data.shatters))
        {
            var sh = _data.shatters[k];
            if (sh != undefined && variable_struct_exists(sh, "chartId"))
            {
                array_push(out,
                {
                    id: variable_struct_exists(sh, "id") ? sh.id : "",
                    chartId: string(sh.chartId),
                    kind: 2,
                    name: variable_struct_exists(sh, "name") ? sh.name : string(sh.chartId),
                    diffName: variable_struct_exists(sh, "difficultyName") ? sh.difficultyName : ""
                });
            }
            k++;
        }
    }
    return out;
}

function vs_packmgr_member_protected(_m)
{
    if (_m == undefined) return false;
    var cid = string(_m.chartId);
    return vs_songstore_has_chart(cid) && !vs_dlmgr_tracked(cid);
}

function vs_packmgr_member_missing(_m)
{
    if (_m == undefined) return true;
    return !vs_songstore_has_chart(string(_m.chartId));
}

function vs_packmgr_queue_from_members(_members)
{
    var q = [];
    var i = 0;
    repeat (array_length(_members))
    {
        var m = _members[i];
        if (m != undefined && variable_struct_exists(m, "id") && string(m.id) != "" && !vs_packmgr_member_protected(m))
        {
            array_push(q, m);
        }
        i++;
    }
    return q;
}

function vs_packmgr_check_items(_members)
{
    var charts = [];
    var diffs = ["opening", "middle", "finale", "encore", "prelude"];
    var i = 0;
    repeat (array_length(_members))
    {
        var m = _members[i];
        if (m != undefined && vs_songstore_has_chart(string(m.chartId)) && vs_dlmgr_tracked(string(m.chartId)))
        {
            if (variable_struct_exists(m, "kind") && m.kind == 2)
            {
                var dn = variable_struct_exists(m, "diffName") ? string(m.diffName) : "";
                if (dn == "") dn = "finale";
                var sha = vs_online_chart_sha1(m.chartId, dn);
                if (sha != "")
                {
                    var item = { chartId: m.chartId, difficulty: vs_online_diff_api(dn), sha1: sha };
                    var vsm = vs_online_chart_vsm_sha1(m.chartId, dn);
                    if (vsm != "") item.vsmSha1 = vsm;
                    array_push(charts, item);
                }
            }
            else
            {
                var d = 0;
                repeat (array_length(diffs))
                {
                    var sha2 = vs_online_chart_sha1(m.chartId, diffs[d]);
                    if (sha2 != "")
                    {
                        var it = { chartId: m.chartId, difficulty: diffs[d], sha1: sha2 };
                        var v2 = vs_online_chart_vsm_sha1(m.chartId, diffs[d]);
                        if (v2 != "") it.vsmSha1 = v2;
                        array_push(charts, it);
                    }
                    d++;
                }
            }
        }
        i++;
    }
    return charts;
}

function vs_packmgr_missing_count(_members)
{
    var n = 0;
    var i = 0;
    repeat (array_length(_members))
    {
        if (vs_packmgr_member_missing(_members[i])) n++;
        i++;
    }
    return n;
}

function vs_packmgr_slot()
{
    if (!variable_global_exists("vs_pack_job"))
    {
        global.vs_pack_job =
        {
            on_done: undefined,
            packId: "",
            name: "",
            version: 0,
            members: [],
            queue: [],
            idx: 0,
            need: 0,
            failed: false,
            cancel: false,
            mode: "",
            info: { name: "", description: "", color1: 0, color2: 0 }
        };
    }
    if (!variable_struct_exists(global.vs_pack_job, "info"))
        global.vs_pack_job.info = { name: "", description: "", color1: 0, color2: 0 };
    return global.vs_pack_job;
}

function vs_packmgr_check(_packId, _on_done)
{
    var st = vs_packmgr_slot();
    st.on_done = _on_done;
    st.packId = string(_packId);
    st.mode = "check";
    st.need = 0;
    st.failed = false;
    st.cancel = false;
    vs_online_get_json("/api/v1/packs/" + st.packId, false, vs_packmgr_check_got);
}

function vs_packmgr_check_got(_ok, _data, _status)
{
    var st = vs_packmgr_slot();
    var cb = st.on_done;
    if (!_ok || _data == undefined)
    {
        st.on_done = undefined;
        if (cb != undefined) cb(false, -1);
        return;
    }
    var members = vs_packmgr_members_from_detail(_data);
    st.members = members;
    st.name = variable_struct_exists(_data, "name") ? _data.name : st.packId;
    st.version = variable_struct_exists(_data, "version") ? _data.version : 0;
    st.info = vs_packmgr_info_struct(_data);
    vs_packmgr_store_meta(st.packId, st.info);
    vs_packmgr_run_sha(members, st.version);
}

function vs_packmgr_check_members(_packId, _members, _version, _on_done)
{
    var st = vs_packmgr_slot();
    st.on_done = _on_done;
    st.packId = string(_packId);
    st.mode = "check";
    st.members = _members;
    st.version = (_version == undefined) ? 0 : _version;
    st.failed = false;
    st.cancel = false;
    if (st.info != undefined && (string(st.info.name) != "" || string(st.info.description) != ""))
        vs_packmgr_store_meta(st.packId, st.info);
    vs_packmgr_run_sha(_members, st.version);
}

function vs_packmgr_run_sha(_members, _version)
{
    var st = vs_packmgr_slot();
    var cb = st.on_done;
    st.members = _members;
    st.need = vs_packmgr_missing_count(_members);
    var local = vs_packmgr_get(st.packId);
    if (local != undefined && variable_struct_exists(local, "version") && local.version != _version)
    {
        if (st.need < 1) st.need = 1;
    }
    if (vs_packmgr_info_stale(st.packId, st.info))
    {
        if (st.need < 1) st.need = 1;
    }
    var charts = vs_packmgr_check_items(_members);
    if (array_length(charts) == 0)
    {
        st.on_done = undefined;
        if (cb != undefined) cb(true, st.need);
        return;
    }
    vs_online_post_json("/api/v1/charts/check-updates", { charts: charts }, vs_packmgr_check_sha);
}

function vs_packmgr_check_sha(_ok, _data, _status)
{
    var st = vs_packmgr_slot();
    var cb = st.on_done;
    st.on_done = undefined;
    if (_ok && _data != undefined && variable_struct_exists(_data, "results") && is_array(_data.results))
    {
        var seen = {};
        var i = 0;
        repeat (array_length(_data.results))
        {
            var r = _data.results[i];
            if (r != undefined && variable_struct_exists(r, "needsUpdate") && r.needsUpdate)
            {
                var cid = string(r.chartId);
                if (!variable_struct_exists(seen, cid))
                {
                    variable_struct_set(seen, cid, true);
                    st.need += 1;
                }
            }
            i++;
        }
    }
    if (cb != undefined) cb(true, st.need);
}

function vs_packmgr_install(_packId, _on_done)
{
    var st = vs_packmgr_slot();
    st.on_done = _on_done;
    st.packId = string(_packId);
    st.mode = "install";
    st.idx = 0;
    st.failed = false;
    st.cancel = false;
    st.queue = [];
    vs_online_get_json("/api/v1/packs/" + st.packId, false, vs_packmgr_install_got);
}

function vs_packmgr_install_got(_ok, _data, _status)
{
    var st = vs_packmgr_slot();
    if (st.cancel)
    {
        vs_packmgr_install_finish(false);
        return;
    }
    if (!_ok || _data == undefined)
    {
        vs_packmgr_install_finish(false);
        return;
    }
    var members = vs_packmgr_members_from_detail(_data);
    st.members = members;
    st.name = variable_struct_exists(_data, "name") ? _data.name : st.packId;
    st.version = variable_struct_exists(_data, "version") ? _data.version : 1;
    st.info = vs_packmgr_info_struct(_data);
    st.queue = vs_packmgr_queue_from_members(members);
    st.idx = 0;
    vs_packmgr_install_next();
}

function vs_packmgr_install_next()
{
    var st = vs_packmgr_slot();
    if (st.cancel)
    {
        vs_packmgr_install_finish(false);
        return;
    }
    if (st.idx >= array_length(st.queue))
    {
        vs_packmgr_install_finish(!st.failed);
        return;
    }
    var m = st.queue[st.idx];
    vs_dlmgr_download(m.id, m.chartId, m.kind, vs_packmgr_install_one);
}

function vs_packmgr_install_one(_ok)
{
    var st = vs_packmgr_slot();
    if (st.cancel || (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel))
    {
        st.cancel = true;
        vs_packmgr_install_finish(false);
        return;
    }
    if (!_ok) st.failed = true;
    st.idx++;
    vs_packmgr_install_next();
}

function vs_packmgr_install_finish(_ok)
{
    var st = vs_packmgr_slot();
    var cb = st.on_done;
    st.on_done = undefined;
    st.mode = "";
    if (_ok)
    {
        var infoSha = vs_packmgr_write_info(st.packId, st.info);
        var iname = (st.info != undefined && st.info.name != "") ? st.info.name : st.name;
        vs_packmgr_upsert(
        {
            id: st.packId,
            name: iname,
            description: (st.info != undefined) ? st.info.description : "",
            color1: (st.info != undefined) ? st.info.color1 : 0,
            color2: (st.info != undefined) ? st.info.color2 : 0,
            version: st.version,
            infoSha1: infoSha,
            songs: st.members
        });
    }
    if (cb != undefined) cb(_ok);
}

function vs_packmgr_cancel()
{
    var st = vs_packmgr_slot();
    st.cancel = true;
    vs_dlmgr_cancel();
}

function vs_packmgr_row_status(_r)
{
    if (_r == undefined) return "pack";
    var n = variable_struct_exists(_r, "songCount") ? _r.songCount : 0;
    var ver = variable_struct_exists(_r, "version") ? _r.version : 0;
    var head = _r.name + "  v" + string(ver) + "  " + string(n) + " song(s)";
    if (!_r.downloaded) return head + "  -  not subscribed";
    if (_r.checked && _r.need > 0) return head + "  -  UPDATE (" + string(_r.need) + ")";
    if (_r.checked) return head + "  -  up to date";
    return head + "  -  subscribed";
}
