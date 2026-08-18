// ============================================================================
// vs_dlbr.gml — Chart Downloader UI (named scripts, not object anons).
// Object Create/Step/Draw call these; self is the vs_downloader_browser
// instance. Requires vsml to Import() codes/ GlobalScripts + Object events
// in one CodeImportGroup so vs_* names resolve as global functions.
// ============================================================================

function vs_dlbr_open_from_menu()
{
    if (instance_exists(vs_downloader_browser))
    {
        with (vs_downloader_browser) instance_destroy();
    }
    instance_create_depth(0, 0, -10001, vs_downloader_browser);
    if (instance_exists(vs_downloader_browser))
    {
        with (vs_downloader_browser)
        {
            do_step = method(id, vs_dlbr_step);
            do_draw = method(id, vs_dlbr_draw);
            do_destroy = method(id, vs_dlbr_on_close);
            vs_dlbr_fetch_page();
        }
    }
}

function vs_dlbr_restore_menu()
{
    if (!variable_global_exists("vs_dlbr_restore_menu") || !global.vs_dlbr_restore_menu) return;
    global.vs_dlbr_restore_menu = false;
    if (instance_exists(vs_downloader_browser)) return;
    if (instance_exists(o_newmenu_main)) o_newmenu_main.is_active = true;
}

function vs_dlbr_set_status(_msg)
{
    status = _msg;
}

function vs_dlbr_build_row(_song)
{
    var ch = variable_struct_exists(_song, "chartId") ? _song.chartId : "";
    return
    {
        id: variable_struct_exists(_song, "id") ? _song.id : "",
        chartId: ch,
        name: variable_struct_exists(_song, "name") ? _song.name : "",
        artist: variable_struct_exists(_song, "artist") ? _song.artist : "",
        chartCount: variable_struct_exists(_song, "chartCount") ? _song.chartCount : 0,
        diffName: variable_struct_exists(_song, "difficultyName") ? _song.difficultyName : "",
        diffNum: variable_struct_exists(_song, "difficultyNumber") ? string(_song.difficultyNumber) : "",
        jacketUrl: variable_struct_exists(_song, "jacketUrl") ? _song.jacketUrl : "",
        previewUrl: variable_struct_exists(_song, "previewUrl") ? _song.previewUrl : "",
        musicUrl: variable_struct_exists(_song, "musicUrl") ? _song.musicUrl : "",
        ownerName: variable_struct_exists(_song, "ownerName") ? _song.ownerName : "",
        downloads: variable_struct_exists(_song, "downloads") ? _song.downloads : 0,
        hasBackstage: variable_struct_exists(_song, "hasBackstage") ? _song.hasBackstage : false,
        kind: (catalog == 2) ? 2 : 0,
        downloaded: vs_dlmgr_downloaded(ch),
        tracked: vs_dlmgr_tracked(ch),
        checked: false,
        need: -1
    };
}

function vs_dlbr_row_all_index(_chartId)
{
    var n = array_length(rows_all);
    var i = 0;
    repeat (n)
    {
        if (rows_all[i].chartId == _chartId) return i;
        i++;
    }
    return -1;
}

function vs_dlbr_apply_filter()
{
    var arr = [];
    var n = array_length(rows_all);
    var i = 0;
    repeat (n)
    {
        var r = rows_all[i];
        var keep = true;
        if (filter == 1 && r.downloaded) keep = false;
        else if (filter == 2 && !r.tracked) keep = false;
        else if (filter == 3)
        {
            keep = (r.tracked && r.checked && r.need > 0);
        }
        if (keep) array_push(arr, r);
        i++;
    }
    rows = arr;
    if (sel >= array_length(rows)) sel = array_length(rows) - 1;
    if (sel < 0) sel = 0;
}

function vs_dlbr_row_jacket(_r)
{
    if (_r == undefined) return "";
    if (variable_struct_exists(_r, "jacketUrl") && _r.jacketUrl != "") return string(_r.jacketUrl);
    var sid = "";
    if (variable_struct_exists(_r, "id")) sid = string(_r.id);
    if (sid == "") return "";
    var fold = (variable_struct_exists(_r, "kind") && _r.kind == 2) ? "/uploads/shatters/" : "/uploads/songs/";
    return vs_online_server_url() + fold + sid + "/jacket.png";
}

function vs_dlbr_row_audio(_r)
{
    if (_r == undefined) return "";
    if (variable_struct_exists(_r, "previewUrl") && _r.previewUrl != "") return string(_r.previewUrl);
    if (variable_struct_exists(_r, "musicUrl") && _r.musicUrl != "") return string(_r.musicUrl);
    return vs_media_audio_url("", vs_dlbr_row_jacket(_r), variable_struct_exists(_r, "id") ? _r.id : "");
}

function vs_dlbr_selected_refresh()
{
    if (array_length(rows) == 0)
    {
        vs_dlbr_set_status(view == 0 ? "No charts match the current filter/page." : "No local charts in Custom Songs/.");
        return;
    }
    var r = rows[sel];
    if (checking && check_chart == r.chartId)
        vs_dlbr_set_status("Checking " + r.chartId + " ...");
    else
        vs_dlbr_set_status(vs_dlmgr_row_status(r));
    vs_media_select(r.id, vs_dlbr_row_jacket(r), vs_dlbr_row_audio(r));
    vs_dlbr_maybe_check_selected();
}

function vs_dlbr_maybe_check_selected()
{
    if (view != 0 || checking || updating || loading || check_all) return;
    if (array_length(rows) == 0) return;
    var r = rows[sel];
    if (!r.downloaded || r.checked) return;
    var ai = vs_dlbr_row_all_index(r.chartId);
    if (ai >= 0) vs_dlbr_check_row_index(ai);
}

function vs_dlbr_current_web_row()
{
    if (detail_open && !detail_local)
    {
        return vs_dlbr_detail_row();
    }
    if (view == 0 && array_length(rows) > 0 && sel >= 0 && sel < array_length(rows))
    {
        return rows[sel];
    }
    return undefined;
}

function vs_dlbr_page_url(_r)
{
    if (_r == undefined) return "";
    var sid = "";
    if (variable_struct_exists(_r, "id") && _r.id != "") sid = string(_r.id);
    if (sid == "") return "";
    var path = "/songs/";
    if (variable_struct_exists(_r, "kind") && _r.kind == 2) path = "/shatters/";
    return vs_online_frontend_url() + path + sid;
}

function vs_dlbr_toggle_preview_auto()
{
    var on = !vs_online_preview_auto();
    vs_online_set_preview_auto(on);
    if (!on)
    {
        vs_media_stop_preview();
        vs_dlbr_set_status("Preview auto-play off");
        return;
    }
    vs_dlbr_set_status("Preview auto-play on");
    var r = vs_dlbr_current_web_row();
    if (r != undefined)
    {
        vs_media_select(r.id, vs_dlbr_row_jacket(r), vs_dlbr_row_audio(r));
    }
}

function vs_dlbr_open_page()
{
    var page = vs_dlbr_page_url(vs_dlbr_current_web_row());
    if (page == "")
    {
        vs_dlbr_set_status("No web page for this chart.");
        return;
    }
    url_open(page);
    vs_dlbr_set_status("Opened page");
}

function vs_dlbr_media_keys()
{
    if (keyboard_check_pressed(ord("P")))
    {
        vs_dlbr_toggle_preview_auto();
        return true;
    }
    if (keyboard_check_pressed(ord("W")))
    {
        vs_dlbr_open_page();
        return true;
    }
    return false;
}

function vs_dlbr_fetch_page()
{
    if (view == 1)
    {
        vs_dlbr_reload_local();
        return;
    }
    loading = true;
    if (!vs_online_is_custom())
    {
        loading = false;
        rows_all = [];
        vs_dlbr_apply_filter();
        vs_dlbr_set_status("Custom Server is off - enable it in Settings, or press V for Local charts.");
        return;
    }
    if (!vs_online_is_account())
    {
        loading = false;
        rows_all = [];
        total = 0;
        maxpage = 1;
        vs_dlbr_apply_filter();
        vs_dlbr_set_status("Guest / not logged in - online catalog disabled. Play downloaded charts (V -> Local) or log in: Settings -> VS Online -> Account Management.");
        return;
    }
    vs_dlbr_set_status(query == "" ? "Loading charts..." : "Search: \"" + query + "\" ...");
    vs_dlmgr_list(query, page, catalog, method(self, vs_dlbr_on_list));
    if (instance_exists(vs_online_error))
    {
        loading = false;
        vs_dlbr_set_status("Server unreachable.");
    }
}

function vs_dlbr_on_list(_ok, _data)
{
    loading = false;
    if (_ok && _data != undefined)
    {
        var arr = [];
        var items = [];
        if (variable_struct_exists(_data, "shatters") && is_array(_data.shatters)) items = _data.shatters;
        else if (variable_struct_exists(_data, "songs") && is_array(_data.songs)) items = _data.songs;
        total = variable_struct_exists(_data, "total") ? floor(_data.total) : array_length(items);
        maxpage = max(1, ceil(total / 100));
        var i = 0;
        repeat (array_length(items))
        {
            array_push(arr, vs_dlbr_build_row(items[i]));
            i++;
        }
        rows_all = arr;
    }
    else
    {
        total = 0;
        maxpage = 1;
        rows_all = [];
    }
    vs_dlbr_apply_filter();
    vs_dlbr_selected_refresh();
    if (note != "") vs_dlbr_set_status(note);
}

function vs_dlbr_check_row_index(_ai)
{
    if (_ai < 0 || _ai >= array_length(rows_all)) return;
    var r = rows_all[_ai];
    if (!r.downloaded || r.checked) return;
    r.checked = true;
    checking = true;
    check_chart = r.chartId;
    vs_dlbr_set_status("Checking " + r.chartId + " ...");
    vs_dlmgr_check(r.id, r.chartId, r.kind, method(self, vs_dlbr_on_check));
}

function vs_dlbr_on_check(_ok, _need)
{
    checking = false;
    var n = array_length(rows_all);
    var i = 0;
    repeat (n)
    {
        if (rows_all[i].chartId == check_chart)
        {
            var rr = rows_all[i];
            var cnt = _ok ? array_length(_need) : -2;
            if (rr.tracked)
            {
                rr.need = cnt;
            }
            else if (cnt == 0 && _ok)
            {
                vs_dlmgr_write_meta(rr.chartId, rr.id, rr.name);
                rr.tracked = true;
                rr.need = 0;
                vs_dlbr_set_status(rr.chartId + " matches server.");
            }
            else
            {
                rr.need = _ok ? cnt : 0;
                vs_dlbr_set_status(rr.chartId + " incomplete - Get to finish.");
            }
            break;
        }
        i++;
    }
    if (check_all)
    {
        vs_dlbr_set_status("Checking " + string(check_idx) + "/" + string(n) + " ...");
        vs_dlbr_check_next();
        return;
    }
    vs_dlbr_apply_filter();
    vs_dlbr_selected_refresh();
    if (enter_act)
    {
        enter_act = false;
        var ai2 = vs_dlbr_row_all_index(check_chart);
        if (ai2 >= 0)
        {
            var after = rows_all[ai2];
            if (after.need > 0)
            {
                vs_dlbr_start_download(after);
                return;
            }
            if (after.tracked && after.need == 0)
            {
                vs_dlbr_set_status(after.chartId + " is up to date.");
            }
        }
    }
}

function vs_dlbr_check_next()
{
    var n = array_length(rows_all);
    while (check_idx < n)
    {
        var r = rows_all[check_idx];
        if (r.downloaded && !r.checked)
        {
            check_idx++;
            vs_dlbr_check_row_index(check_idx - 1);
            return;
        }
        check_idx++;
    }
    check_all = false;
    vs_dlbr_apply_filter();
    vs_dlbr_selected_refresh();
    vs_dlbr_set_status("Checked " + string(n) + " chart(s) on this page.");
}

function vs_dlbr_check_all_rows()
{
    if (view == 1) return;
    if (checking || updating) return;
    check_all = true;
    check_idx = 0;
    vs_dlbr_set_status("Checking whole page for updates...");
    vs_dlbr_check_next();
}

function vs_dlbr_finalize_install()
{
    vs_localcharts_refresh();
    vs_dlbr_fetch_page();
}

function vs_dlbr_start_download(_r)
{
    if (updating) return;
    updating = true;
    cur_id = _r.id;
    cur_chart = _r.chartId;
    note = "";
    vs_dlbr_set_status("Downloading " + _r.name + " ...");
    vs_dlmgr_download(_r.id, _r.chartId, _r.kind, method(self, vs_dlbr_on_download));
}

function vs_dlbr_on_download(_ok)
{
    updating = false;
    vs_dlbr_close_detail();
    var cancelled = variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel;
    if (cancelled)
    {
        note = "Download cancelled.";
        vs_dlbr_set_status(note);
        vs_dlbr_fetch_page();
        return;
    }
    if (_ok)
    {
        note = "Done - " + cur_chart;
        vs_dlbr_set_status(note + " (rescanning custom songs...)");
        vs_dlbr_finalize_install();
    }
    else
    {
        var why = "";
        if (variable_global_exists("vs_dlmgr_dl") && variable_struct_exists(global.vs_dlmgr_dl, "err") && global.vs_dlmgr_dl.err != "")
        {
            why = " - " + string(global.vs_dlmgr_dl.err);
        }
        note = "Failed - " + cur_chart + why + " (vsonline.dl.log)";
        vs_dlbr_set_status(note);
        vs_dlbr_fetch_page();
    }
}

function vs_dlbr_do_selected_action()
{
    if (array_length(rows) == 0) return;
    if (updating) return;
    vs_dlbr_open_detail(rows[sel], false);
}

function vs_dlbr_batch_update()
{
    if (view == 1 || updating || checking) return;
    var q = [];
    var n = array_length(rows_all);
    var i = 0;
    repeat (n)
    {
        var r = rows_all[i];
        if (r.tracked && r.checked && r.need > 0) array_push(q, i);
        i++;
    }
    if (array_length(q) == 0)
    {
        vs_dlbr_set_status("No tracked updates on this page. Press K to check the page first.");
        return;
    }
    update_queue = q;
    update_qidx = 0;
    updating = true;
    vs_dlbr_set_status("Updating " + string(array_length(q)) + " chart(s) on this page...");
    vs_dlbr_batch_next();
}

function vs_dlbr_batch_next()
{
    if (update_qidx >= array_length(update_queue))
    {
        updating = false;
        update_queue = [];
        vs_dlbr_set_status("Page updates done - rescanning custom songs ...");
        vs_dlbr_finalize_install();
        return;
    }
    var ri = update_queue[update_qidx];
    var r = rows_all[ri];
    batch_name = r.name;
    vs_dlmgr_download(r.id, r.chartId, r.kind, method(self, vs_dlbr_on_batch));
}

function vs_dlbr_on_batch(_ok)
{
    if (variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel)
    {
        updating = false;
        update_queue = [];
        vs_dlbr_set_status("Download cancelled.");
        return;
    }
    update_qidx++;
    vs_dlbr_set_status("Updating " + batch_name + " (" + string(update_qidx) + "/" + string(array_length(update_queue)) + ") ...");
    vs_dlbr_batch_next();
}

function vs_dlbr_cycle_filter()
{
    if (view == 1) return;
    filter = (filter + 1) % 4;
    vs_dlbr_set_status("Filter: " + vs_dlmgr_filter_name(filter));
    if (filter == 3)
    {
        vs_dlbr_check_all_rows();
        return;
    }
    vs_dlbr_apply_filter();
    vs_dlbr_selected_refresh();
}

function vs_dlbr_toggle_view()
{
    vs_dlbr_close_detail();
    vs_media_stop_preview();
    view = (view == 0) ? 1 : 0;
    page = 1;
    sel = 0;
    vs_dlbr_fetch_page();
}

function vs_dlbr_set_catalog(_c)
{
    vs_dlbr_close_detail();
    vs_media_stop_preview();
    view = 0;
    catalog = _c;
    page = 1;
    sel = 0;
    vs_dlbr_fetch_page();
}

function vs_dlbr_cycle_catalog()
{
    vs_dlbr_set_catalog((catalog + 1) % 3);
}

function vs_dlbr_catalog_key()
{
    if (keyboard_check_pressed(ord("T")))
    {
        vs_dlbr_cycle_catalog();
        return true;
    }
    if (keyboard_check_pressed(ord("1")))
    {
        vs_dlbr_set_catalog(0);
        return true;
    }
    if (keyboard_check_pressed(ord("2")))
    {
        vs_dlbr_set_catalog(1);
        return true;
    }
    if (keyboard_check_pressed(ord("3")))
    {
        vs_dlbr_set_catalog(2);
        return true;
    }
    return false;
}

function vs_dlbr_apply_local_filter()
{
    var src = local_all;
    var q = string_lower(query);
    var arr = [];
    var n = array_length(src);
    var i = 0;
    repeat (n)
    {
        var r = src[i];
        var keep = (q == "");
        if (!keep)
        {
            keep = string_pos(q, string_lower(r.name)) > 0
                || string_pos(q, string_lower(r.artist)) > 0
                || string_pos(q, string_lower(r.chart_id)) > 0
                || string_pos(q, string_lower(r.pack)) > 0;
        }
        if (keep) array_push(arr, r);
        i++;
    }
    local_rows = arr;
    if (sel >= array_length(local_rows)) sel = array_length(local_rows) - 1;
    if (sel < 0) sel = 0;
}

function vs_dlbr_reload_local()
{
    local_all = vs_localcharts_scan();
    vs_dlbr_apply_local_filter();
    vs_dlbr_set_status((array_length(local_rows) > 0)
        ? ("Local " + string(array_length(local_rows)) + "/" + string(array_length(local_all)))
        : (query == "" ? "No local charts in Custom Songs/." : "No local charts match \"" + query + "\"."));
}

function vs_dlbr_jump_chart(_chartId, _kind, _name)
{
    if (_chartId == undefined || _chartId == "") return;
    vs_localcharts_refresh();
    if (_kind == 2)
    {
        if (vs_localcharts_jump_shatter(_chartId)) return;
        vs_dlbr_set_status(_name + " is not in the shatter list.");
        return;
    }
    if (vs_localcharts_jump(_chartId)) return;
    vs_dlbr_set_status(_name + " is not in All Custom Songs yet.");
}

function vs_dlbr_jump_from_local()
{
    if (array_length(local_rows) == 0) return;
    var lr = local_rows[sel];
    var kind = variable_struct_exists(lr, "kind") ? lr.kind : 0;
    vs_dlbr_jump_chart(lr.chart_id, kind, lr.name);
}

function vs_dlbr_jump_from_detail()
{
    var chartId = detail_chart;
    var kind = 0;
    var name = chartId;
    if (detail_local)
    {
        if (sel >= 0 && sel < array_length(local_rows))
        {
            var lr = local_rows[sel];
            chartId = lr.chart_id;
            kind = variable_struct_exists(lr, "kind") ? lr.kind : 0;
            name = lr.name;
        }
    }
    else
    {
        var r = vs_dlbr_detail_row();
        if (r != undefined)
        {
            chartId = r.chartId;
            kind = variable_struct_exists(r, "kind") ? r.kind : 0;
            name = r.name;
        }
    }
    vs_dlbr_close_detail();
    vs_dlbr_jump_chart(chartId, kind, name);
}

function vs_dlbr_reload_data()
{
    vs_dlbr_fetch_page();
}

function vs_dlbr_step()
{
    vs_media_poll();
    if (instance_exists(vs_online_error))
    {
        if (loading)
        {
            loading = false;
            vs_dlbr_set_status("Server unreachable.");
        }
        return;
    }

    started++;
    if (keyboard_check_pressed(vk_escape) && !searching && !updating && !detail_open)
    {
        vs_media_stop_preview();
        instance_destroy();
        return;
    }
    if (started < 8) return;

    if (searching)
    {
        vs_media_stop_preview();
        query = keyboard_string;
        if (keyboard_check_pressed(vk_enter))
        {
            searching = false;
            if (view == 1)
            {
                vs_dlbr_apply_local_filter();
                vs_dlbr_set_status((array_length(local_rows) > 0)
                    ? ("Local search: " + string(array_length(local_rows)) + "/" + string(array_length(local_all)))
                    : ("No local charts match \"" + query + "\"."));
            }
            else
            {
                page = 1;
                vs_dlbr_fetch_page();
            }
        }
        else if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_tab))
        {
            searching = false;
            keyboard_string = query;
        }
        return;
    }

    if (updating)
    {
        if (keyboard_check_pressed(vk_escape))
        {
            vs_dlmgr_cancel();
            vs_dlbr_set_status("Cancelling download...");
        }
        return;
    }

    if (detail_open)
    {
        vs_dlbr_step_detail();
        return;
    }

    if (loading) return;

    if (view == 0)
    {
        var n = array_length(rows);

        if (n == 0)
        {
            if (vs_dlbr_catalog_key()) return;
            if (vs_dlbr_media_keys()) return;
            if (keyboard_check_pressed(ord("R"))) vs_dlbr_reload_data();
            else if (keyboard_check_pressed(ord("V"))) vs_dlbr_toggle_view();
            else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
            else if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_pageup))
            {
                if (page > 1) { page--; vs_dlbr_fetch_page(); }
            }
            else if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_pagedown))
            {
                if (page < maxpage) { page++; vs_dlbr_fetch_page(); }
            }
            return;
        }

        if (keyboard_check_pressed(vk_up))
        {
            note = "";
            sel = (sel + n - 1) % n;
            vs_dlbr_selected_refresh();
        }
        else if (keyboard_check_pressed(vk_down))
        {
            note = "";
            sel = (sel + 1) % n;
            vs_dlbr_selected_refresh();
        }
        else if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_pageup))
        {
            if (page > 1) { page--; vs_dlbr_fetch_page(); }
        }
        else if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_pagedown))
        {
            if (page < maxpage) { page++; vs_dlbr_fetch_page(); }
        }
        else if (keyboard_check_pressed(vk_tab))
        {
            searching = true;
            keyboard_string = query;
        }
        else if (keyboard_check_pressed(ord("F")))
        {
            vs_dlbr_cycle_filter();
        }
        else if (keyboard_check_pressed(ord("K")))
        {
            vs_dlbr_check_all_rows();
        }
        else if (keyboard_check_pressed(ord("G")))
        {
            vs_dlbr_batch_update();
        }
        else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
        {
            vs_dlbr_open_detail(rows[sel], false);
        }
        else if (keyboard_check_pressed(ord("V")))
        {
            vs_dlbr_toggle_view();
        }
        else if (keyboard_check_pressed(ord("R")))
        {
            vs_dlbr_reload_data();
        }
        else if (vs_dlbr_media_keys()) { }
        else if (vs_dlbr_catalog_key()) { }
    }
    else
    {
        var ln = array_length(local_rows);

        if (ln == 0)
        {
            if (vs_dlbr_catalog_key()) return;
            if (vs_dlbr_media_keys()) return;
            if (keyboard_check_pressed(ord("R"))) vs_dlbr_reload_local();
            else if (keyboard_check_pressed(ord("V"))) vs_dlbr_toggle_view();
            else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
            return;
        }

        if (keyboard_check_pressed(vk_up))
        {
            sel = (sel + ln - 1) % ln;
            vs_dlbr_set_status(local_rows[sel].pack + "  " + local_rows[sel].name);
        }
        else if (keyboard_check_pressed(vk_down))
        {
            sel = (sel + 1) % ln;
            vs_dlbr_set_status(local_rows[sel].pack + "  " + local_rows[sel].name);
        }
        else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
        {
            vs_dlbr_open_detail(local_rows[sel], true);
        }
        else if (keyboard_check_pressed(ord("V")))
        {
            vs_dlbr_toggle_view();
        }
        else if (keyboard_check_pressed(ord("R")))
        {
            vs_dlbr_reload_local();
        }
        else if (keyboard_check_pressed(vk_tab))
        {
            searching = true;
            keyboard_string = query;
        }
        else if (vs_dlbr_media_keys()) { }
        else if (vs_dlbr_catalog_key()) { }
    }
}

function vs_dlbr_clip_text(_s, _maxw)
{
    var s = string(_s);
    if (_maxw <= 0 || string_width(s) <= _maxw) return s;
    while (string_length(s) > 1 && string_width(s + "..") > _maxw)
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    return s + "..";
}

function vs_dlbr_draw()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pad = 4;
    var bw = max(80, cw - pad * 2);
    var bh = max(60, ch - pad * 2);
    var bx = pad;
    var by = pad;
    var rowh = 14;

    draw_set_alpha(0.72);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);

    draw_set_color(make_color_rgb(12, 14, 18));
    draw_rectangle(bx, by, bx + bw, by + bh, false);
    draw_set_color(make_color_rgb(48, 52, 60));
    draw_rectangle(bx, by, bx + bw, by + bh, true);

    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(make_color_rgb(80, 220, 230));
    draw_text(bx + 6, by + 2, "Downloader");
    draw_set_font(global.default_font);

    var pg = (view == 0)
        ? ("[" + string(page) + "/" + string(maxpage) + "]")
        : ("[" + string(array_length(local_rows)) + "/" + string(array_length(local_all)) + "]");
    draw_set_halign(fa_right);
    draw_set_color(make_color_rgb(180, 186, 196));
    draw_text(bx + bw - 6, by + 3, pg);
    draw_set_halign(fa_left);

    vs_dlbr_draw_tabs(bx + 6, by + 14, bw - 12);

    var listTop = by + 26;
    var listBot = by + bh - 24;
    var vis = max(1, floor((listBot - listTop) / rowh));
    var n = (view == 0) ? array_length(rows) : array_length(local_rows);
    var start_idx = max(0, sel - floor(vis / 2));
    if (start_idx + vis > n) start_idx = max(0, n - vis);
    var end_idx = min(n, start_idx + vis);

    if (n == 0)
    {
        draw_set_color(c_white);
        draw_text(bx + 8, listTop + 6, vs_dlbr_clip_text((view == 0) ? "No charts match." : "No custom charts.", bw - 16));
    }
    else
    {
        var i = start_idx;
        repeat (end_idx - start_idx)
        {
            vs_dlbr_draw_bar(bx + 4, listTop + ((i - start_idx) * rowh), bw - 8, rowh - 2, i);
            i++;
        }
    }

    var st = vs_dlbr_clip_text(string(status), bw - 12);
    draw_set_color(make_color_rgb(120, 210, 140));
    draw_text(bx + 6, by + bh - 22, st);
    vs_dlbr_draw_hints(bx + 6, by + bh - 12, bw - 12);

    if (detail_open) vs_dlbr_draw_detail();
    if (updating) vs_dlbr_draw_dl_popup();
    if (searching) vs_dlbr_draw_search();

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

function vs_dlbr_draw_dl_popup()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pw = min(220, max(80, cw - 8));
    var ph = min(78, max(48, ch - 8));
    var px = (cw - pw) / 2;
    var py = (ch - ph) / 2;
    draw_set_alpha(0.55);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);
    draw_set_color(c_black);
    draw_rectangle(px - 2, py - 2, px + pw + 2, py + ph + 2, false);
    draw_set_color(c_white);
    draw_rectangle(px, py, px + pw, py + ph, true);

    var title = "Downloading";
    var fname = "";
    var files = "Preparing...";
    var frac = 0;
    if (variable_global_exists("vs_dlmgr_dl"))
    {
        var st = global.vs_dlmgr_dl;
        if (st.name != "") title = st.name;
        var n = array_length(st.need);
        var cur = st.idx + 1;
        if (cur > n) cur = n;
        files = "File " + string(cur) + "/" + string(n);
        fname = string(st.fileName);
        frac = vs_dlmgr_prog_frac();
        if (st.cancel) title = "Cancelling...";
    }

    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_center);
    draw_set_color(c_aqua);
    draw_text(px + pw / 2, py + 4, vs_dlbr_clip_text(title, pw - 12));
    draw_set_font(global.default_font);
    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text(px + 8, py + 20, vs_dlbr_clip_text(files, pw - 16));
    draw_set_color(c_gray);
    draw_text(px + 8, py + 32, vs_dlbr_clip_text(fname, pw - 16));

    var barx = px + 8;
    var bary = py + 46;
    var barw = pw - 16;
    var barh = 8;
    draw_set_color(make_color_rgb(40, 40, 40));
    draw_rectangle(barx, bary, barx + barw, bary + barh, false);
    draw_set_color(c_gray);
    draw_rectangle(barx, bary, barx + barw, bary + barh, true);
    var fill = floor(barw * frac);
    if (fill > 0)
    {
        draw_set_color(c_lime);
        draw_rectangle(barx, bary, barx + fill, bary + barh, false);
    }
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_text(px + pw / 2, py + 58, string(floor(frac * 100)) + "%   Esc cancel");
}

function vs_dlbr_on_close()
{
    vs_media_stop_preview();
    global.vs_dlbr_restore_menu = true;
    call_later(1, time_source_units_frames, vs_dlbr_restore_menu);
}

function vs_dlbr_draw_keychip(_x, _y, _key, _hint, _max)
{
    var kw = string_width(_key);
    var hw = string_width(_hint);
    var need = kw + 4 + hw + 6;
    if (_max > 0 && _x + need > _max) return _x;
    draw_set_color(make_color_rgb(80, 220, 230));
    draw_rectangle(_x - 1, _y - 1, _x + kw + 1, _y + 8, false);
    draw_set_color(c_black);
    draw_text(_x, _y, _key);
    draw_set_color(make_color_rgb(170, 176, 186));
    draw_text(_x + kw + 4, _y, _hint);
    return _x + need;
}

function vs_dlbr_draw_hints(_x, _y, _w)
{
    var right = _x + _w;
    if (searching)
    {
        _x = vs_dlbr_draw_keychip(_x, _y, "ENTER", "ok", right);
        vs_dlbr_draw_keychip(_x, _y, "ESC", "back", right);
        return;
    }
    _x = vs_dlbr_draw_keychip(_x, _y, "ENTER", "open", right);
    _x = vs_dlbr_draw_keychip(_x, _y, "TAB", "find", right);
    if (view == 0)
    {
        _x = vs_dlbr_draw_keychip(_x, _y, "T", "cat", right);
        _x = vs_dlbr_draw_keychip(_x, _y, "F", "filt", right);
        _x = vs_dlbr_draw_keychip(_x, _y, "P", "auto", right);
        _x = vs_dlbr_draw_keychip(_x, _y, "W", "web", right);
    }
    _x = vs_dlbr_draw_keychip(_x, _y, "V", (view == 0) ? "loc" : "web", right);
    vs_dlbr_draw_keychip(_x, _y, "ESC", "back", right);
}

function vs_dlbr_draw_tabs(_x, _y, _w)
{
    var names = ["SONG", "BACK", "SHTR", "LOC"];
    var tx = _x;
    var i = 0;
    repeat (4)
    {
        var on = (i == 3) ? (view == 1) : (view == 0 && catalog == i);
        var lab = names[i];
        var tw = string_width(lab) + 8;
        if (tx + tw > _x + _w) break;
        draw_set_color(on ? make_color_rgb(80, 220, 230) : make_color_rgb(110, 116, 126));
        draw_text(tx, _y, lab);
        tx += tw;
        i++;
    }
}

function vs_dlbr_draw_search()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pw = min(260, max(80, cw - 8));
    var ph = min(56, max(40, ch - 8));
    var px = (cw - pw) / 2;
    var py = (ch - ph) / 2;
    draw_set_alpha(0.62);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);
    draw_set_color(c_black);
    draw_rectangle(px, py, px + pw, py + ph, false);
    draw_set_color(make_color_rgb(80, 220, 230));
    draw_rectangle(px, py, px + pw, py + ph, true);
    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text(px + 8, py + 3, "Search");
    draw_set_font(global.default_font);
    draw_set_color(c_lime);
    draw_text(px + 8, py + 18, vs_dlbr_clip_text(query + "_", pw - 16));
    draw_set_color(make_color_rgb(120, 126, 136));
    draw_text(px + 8, py + ph - 12, "Enter  Esc");
}

function vs_dlbr_mark(_r)
{
    if (_r == undefined) return ".";
    if (variable_struct_exists(_r, "chart_id"))
    {
        return vs_dlmgr_tracked(_r.chart_id) ? "D" : "L";
    }
    if (_r.downloaded && !_r.tracked) return "L";
    if (_r.downloaded && _r.checked && _r.need > 0) return "U";
    if (_r.downloaded) return "D";
    return ".";
}

function vs_dlbr_mark_color(_m, _sel)
{
    if (_sel) return c_black;
    if (_m == "U") return make_color_rgb(80, 220, 230);
    if (_m == "L") return make_color_rgb(240, 160, 70);
    if (_m == "D") return make_color_rgb(140, 220, 150);
    return make_color_rgb(200, 204, 212);
}

function vs_dlbr_draw_bar(_x, _y, _w, _h, _idx)
{
    var web = (view == 0);
    var r = web ? rows[_idx] : local_rows[_idx];
    var isSel = (_idx == sel);
    var mk = vs_dlbr_mark(r);
    if (isSel)
    {
        draw_set_color(make_color_rgb(240, 210, 70));
        draw_rectangle(_x, _y, _x + _w, _y + _h, false);
    }
    else
    {
        draw_set_color(make_color_rgb(22, 24, 30));
        draw_rectangle(_x, _y, _x + _w, _y + _h, false);
        draw_set_color(make_color_rgb(40, 44, 52));
        draw_rectangle(_x, _y, _x + _w, _y + _h, true);
    }
    draw_set_color(isSel ? c_black : vs_dlbr_mark_color(mk, false));
    draw_text(_x + 4, _y + 2, mk);
    var line = r.name;
    if (r.artist != "") line += " - " + r.artist;
    if (web && variable_struct_exists(r, "kind") && r.kind == 2)
    {
        var dlab = r.diffName;
        if (r.diffNum != "") dlab = (dlab != "") ? (dlab + " " + r.diffNum) : r.diffNum;
        if (dlab != "") line += " [" + dlab + "]";
    }
    else if (web && r.chartCount > 0) line += " [" + string(r.chartCount) + "]";
    if (web && r.hasBackstage) line += " B";
    draw_set_color(isSel ? c_black : c_white);
    draw_text(_x + 16, _y + 2, vs_dlbr_clip_text((isSel ? "> " : "") + line, _w - 20));
}

function vs_dlbr_open_detail(_r, _local)
{
    if (_r == undefined) return;
    detail_open = true;
    detail_local = _local;
    detail_confirm = false;
    detail_btn = 0;
    detail_loading = !_local;
    detail = undefined;
    if (_local)
    {
        detail_id = _r.chart_id;
        detail_chart = _r.chart_id;
        detail =
        {
            name: _r.name,
            artist: _r.artist,
            chartId: _r.chart_id,
            ownerName: "",
            bpmDisplay: "",
            jacketArtist: "",
            jacketUrl: "",
            previewUrl: "",
            charts: [],
            diffs: _r.diffs,
            pack: _r.pack
        };
        if (variable_struct_exists(_r, "chart_path")) vs_media_load_folder(_r.chart_id, _r.chart_path);
        return;
    }
    detail_id = _r.id;
    detail_chart = _r.chartId;
    vs_media_select(_r.id, vs_dlbr_row_jacket(_r), vs_dlbr_row_audio(_r));
    vs_songstore_fetch(variable_struct_exists(_r, "kind") ? _r.kind : 0, _r.id, vs_dlbr_on_detail);
}

function vs_dlbr_on_detail(_ok, _data)
{
    if (!instance_exists(vs_downloader_browser)) return;
    with (vs_downloader_browser)
    {
        detail_loading = false;
        if (!_ok || _data == undefined)
        {
            vs_dlbr_set_status("Could not load details.");
            return;
        }
        detail = _data;
        var ju = variable_struct_exists(_data, "jacketUrl") ? _data.jacketUrl : "";
        var pu = variable_struct_exists(_data, "previewUrl") ? _data.previewUrl : "";
        var mu = variable_struct_exists(_data, "musicUrl") ? _data.musicUrl : "";
        vs_media_select(detail_id, (ju != "") ? ju : vs_dlbr_row_jacket(vs_dlbr_detail_row()), (pu != "") ? pu : mu);
        var ai = vs_dlbr_row_all_index(detail_chart);
        if (ai < 0) return;
        var rr = rows_all[ai];
        rr.checked = true;
        var need = vs_songstore_diff(_data.files, rr.chartId);
        if (rr.tracked)
        {
            rr.need = array_length(need);
        }
        else if (array_length(need) == 0 && vs_songstore_has_chart(rr.chartId))
        {
            vs_dlmgr_write_meta(rr.chartId, rr.id, rr.name);
            rr.tracked = true;
            rr.need = 0;
        }
        else if (vs_songstore_has_chart(rr.chartId))
        {
            rr.need = array_length(need);
        }
    }
}

function vs_dlbr_close_detail()
{
    detail_open = false;
    detail_local = false;
    detail_loading = false;
    detail = undefined;
    detail_confirm = false;
    detail_btn = 0;
}

function vs_dlbr_detail_row()
{
    if (detail_local)
    {
        if (sel < 0 || sel >= array_length(local_rows)) return undefined;
        return local_rows[sel];
    }
    var ai = vs_dlbr_row_all_index(detail_chart);
    if (ai < 0) return undefined;
    return rows_all[ai];
}

function vs_dlbr_detail_buttons()
{
    var b = [];
    if (detail_confirm)
    {
        array_push(b, { id: "yes", label: "Confirm delete" });
        array_push(b, { id: "no", label: "Cancel" });
        return b;
    }
    if (detail_local)
    {
        array_push(b, { id: "jump", label: "Play" });
        array_push(b, { id: "del", label: "Del" });
        array_push(b, { id: "close", label: "Close" });
        return b;
    }
    var r = vs_dlbr_detail_row();
    if (r != undefined)
    {
        if (r.downloaded) array_push(b, { id: "jump", label: "Play" });
        if (!r.downloaded) array_push(b, { id: "dl", label: "Get" });
        else if (!r.tracked || r.need > 0) array_push(b, { id: "dl", label: r.tracked ? "Update" : "Get" });
        if (r.downloaded) array_push(b, { id: "del", label: "Del" });
    }
    array_push(b, { id: "auto", label: vs_online_preview_auto() ? "Mute" : "Auto" });
    array_push(b, { id: "page", label: "Page" });
    array_push(b, { id: "close", label: "Close" });
    return b;
}

function vs_dlbr_do_delete()
{
    var chartId = detail_chart;
    vs_songstore_remove_chart(chartId);
    vs_dlbr_close_detail();
    vs_localcharts_refresh();
    vs_dlbr_fetch_page();
    vs_dlbr_set_status("Deleted " + chartId);
}

function vs_dlbr_detail_act(_id)
{
    if (_id == "close" || _id == "no")
    {
        if (_id == "no") { detail_confirm = false; detail_btn = 0; return; }
        vs_dlbr_close_detail();
        return;
    }
    if (_id == "yes")
    {
        vs_dlbr_do_delete();
        return;
    }
    if (_id == "del")
    {
        detail_confirm = true;
        detail_btn = 0;
        return;
    }
    if (_id == "jump")
    {
        vs_dlbr_jump_from_detail();
        return;
    }
    if (_id == "auto")
    {
        vs_dlbr_toggle_preview_auto();
        return;
    }
    if (_id == "page")
    {
        vs_dlbr_open_page();
        return;
    }
    if (_id == "dl")
    {
        var r = vs_dlbr_detail_row();
        if (r == undefined) return;
        if (!r.downloaded || !r.tracked || r.need > 0)
        {
            vs_dlbr_close_detail();
            vs_dlbr_start_download(r);
        }
    }
}

function vs_dlbr_step_detail()
{
    var btns = vs_dlbr_detail_buttons();
    var n = array_length(btns);
    if (n <= 0) return;
    if (detail_btn >= n) detail_btn = n - 1;
    if (keyboard_check_pressed(vk_escape))
    {
        if (detail_confirm) { detail_confirm = false; detail_btn = 0; return; }
        vs_dlbr_close_detail();
        return;
    }
    if (keyboard_check_pressed(vk_left))
    {
        detail_btn = (detail_btn + n - 1) % n;
    }
    else if (keyboard_check_pressed(vk_right))
    {
        detail_btn = (detail_btn + 1) % n;
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        vs_dlbr_detail_act(btns[detail_btn].id);
    }
    else vs_dlbr_media_keys();
}

function vs_dlbr_diff_color(_d)
{
    var k = string_lower(string(_d));
    if (k == "opening") return make_color_rgb(38, 217, 217);
    if (k == "middle") return make_color_rgb(252, 184, 43);
    if (k == "finale") return make_color_rgb(241, 75, 107);
    if (k == "encore") return make_color_rgb(176, 107, 240);
    return make_color_rgb(145, 151, 164);
}

function vs_dlbr_draw_detail()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pw = min(300, max(80, cw - 8));
    var ph = min(150, max(70, ch - 8));
    var px = (cw - pw) / 2;
    var py = (ch - ph) / 2;

    draw_set_alpha(0.55);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(14, 16, 20));
    draw_rectangle(px, py, px + pw, py + ph, false);
    draw_set_color(make_color_rgb(80, 220, 230));
    draw_rectangle(px, py, px + pw, py + ph, true);

    var jx = px + 6;
    var jy = py + 6;
    var js = min(40, ph - 36);
    draw_set_color(make_color_rgb(28, 30, 36));
    draw_rectangle(jx, jy, jx + js, jy + js, false);
    var spr = vs_media_jacket(detail_id);
    if (spr != -1 && sprite_exists(spr))
    {
        draw_set_color(c_white);
        draw_set_alpha(1);
        gpu_set_tex_filter(true);
        draw_sprite_stretched(spr, 0, jx, jy, js, js);
        gpu_set_tex_filter(false);
    }
    else
    {
        draw_set_color(make_color_rgb(80, 84, 92));
        draw_set_halign(fa_center);
        draw_text(jx + js / 2, jy + js / 2 - 4, detail_loading ? "..." : " ");
        draw_set_halign(fa_left);
    }

    var tx = jx + js + 6;
    var name = detail_chart;
    var artist = "";
    var owner = "";
    var bpm = "";
    var jacketBy = "";
    if (detail != undefined)
    {
        if (variable_struct_exists(detail, "name") && detail.name != "") name = detail.name;
        if (variable_struct_exists(detail, "artist")) artist = string(detail.artist);
        if (variable_struct_exists(detail, "ownerName")) owner = string(detail.ownerName);
        if (variable_struct_exists(detail, "bpmDisplay")) bpm = string(detail.bpmDisplay);
        if (variable_struct_exists(detail, "jacketArtist")) jacketBy = string(detail.jacketArtist);
        if (variable_struct_exists(detail, "chartId") && detail.chartId != "") detail_chart = detail.chartId;
    }
    var textw = px + pw - tx - 6;
    draw_set_font(fnt_monacovs);
    draw_set_color(c_white);
    draw_text(tx, py + 6, vs_dlbr_clip_text(name, textw));
    draw_set_font(global.default_font);
    draw_set_color(make_color_rgb(180, 186, 196));
    draw_text(tx, py + 18, vs_dlbr_clip_text((artist != "") ? artist : " ", textw));
    draw_set_color(make_color_rgb(140, 146, 156));
    var meta = detail_chart;
    if (owner != "") meta += "  " + owner;
    if (bpm != "") meta += "  BPM " + bpm;
    draw_text(tx, py + 28, vs_dlbr_clip_text(meta, textw));
    if (jacketBy != "") draw_text(tx, py + 38, vs_dlbr_clip_text("Jacket " + jacketBy, textw));

    var right = px + pw - 6;
    var byb = py + ph - 22;
    var dy = py + js + 10;
    draw_set_color(make_color_rgb(200, 204, 212));
    if (dy + 12 < byb)
    {
        if (detail_loading)
        {
            draw_text(px + 6, dy, vs_dlbr_clip_text("Loading...", right - px - 6));
        }
        else if (detail != undefined && variable_struct_exists(detail, "charts") && is_array(detail.charts))
        {
            var charts = detail.charts;
            var cx = px + 6;
            var i = 0;
            repeat (array_length(charts))
            {
                var chd = charts[i];
                var diff = variable_struct_exists(chd, "difficulty") ? string(chd.difficulty) : "";
                var pill = string_upper(diff);
                if (variable_struct_exists(chd, "difficultyDisplay") && chd.difficultyDisplay != "") pill += " " + string(chd.difficultyDisplay);
                else if (variable_struct_exists(chd, "difficultyConstant")) pill += " " + string(chd.difficultyConstant);
                var pw2 = string_width(pill) + 8;
                if (cx + pw2 > right) break;
                draw_set_color(vs_dlbr_diff_color(diff));
                draw_rectangle(cx, dy, cx + pw2, dy + 11, false);
                draw_set_color(c_black);
                draw_text(cx + 4, dy + 1, pill);
                cx += pw2 + 4;
                i++;
            }
        }
        else if (detail != undefined && variable_struct_exists(detail, "diffs") && is_array(detail.diffs))
        {
            var cx = px + 6;
            var i = 0;
            repeat (array_length(detail.diffs))
            {
                var lab = string(detail.diffs[i]);
                var pw2 = string_width(lab) + 8;
                if (cx + pw2 > right) break;
                draw_set_color(vs_dlbr_diff_color(lab));
                draw_rectangle(cx, dy, cx + pw2, dy + 11, false);
                draw_set_color(c_black);
                draw_text(cx + 4, dy + 1, lab);
                cx += pw2 + 4;
                i++;
            }
        }
        else if (detail != undefined && variable_struct_exists(detail, "difficultyName"))
        {
            var lab = string(detail.difficultyName);
            if (variable_struct_exists(detail, "difficultyNumber") && detail.difficultyNumber != "") lab += " " + string(detail.difficultyNumber);
            lab = vs_dlbr_clip_text(lab, right - px - 14);
            var pw2 = string_width(lab) + 8;
            draw_set_color(make_color_rgb(176, 107, 240));
            draw_rectangle(px + 6, dy, px + 6 + pw2, dy + 11, false);
            draw_set_color(c_black);
            draw_text(px + 10, dy + 1, lab);
        }
    }

    var btns = vs_dlbr_detail_buttons();
    var bn = array_length(btns);
    var startx = px + 6;
    var maxw = right - startx;
    var used = 0;
    var rows = 1;
    var i = 0;
    repeat (bn)
    {
        var bw2 = string_width(btns[i].label) + 12;
        if (used + bw2 > maxw && used > 0)
        {
            rows++;
            used = 0;
        }
        used += bw2 + 4;
        i++;
    }
    var rowY = byb - (rows - 1) * 14;
    var bx = startx;
    used = 0;
    i = 0;
    repeat (bn)
    {
        var lab = btns[i].label;
        var bw2 = string_width(lab) + 12;
        if (used + bw2 > maxw && used > 0)
        {
            rowY += 14;
            bx = startx;
            used = 0;
        }
        var on = (i == detail_btn);
        if (on)
        {
            draw_set_color((btns[i].id == "yes" || btns[i].id == "del") ? make_color_rgb(241, 75, 107) : make_color_rgb(240, 210, 70));
            draw_rectangle(bx, rowY, bx + bw2, rowY + 12, false);
            draw_set_color(c_black);
        }
        else
        {
            draw_set_color(make_color_rgb(40, 44, 52));
            draw_rectangle(bx, rowY, bx + bw2, rowY + 12, false);
            draw_set_color(c_white);
        }
        draw_text(bx + 6, rowY + 2, lab);
        bx += bw2 + 4;
        used += bw2 + 4;
        i++;
    }
}
