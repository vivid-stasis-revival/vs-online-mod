// ============================================================================
// vs_dlbr.gml — Chart Downloader UI (named scripts, not object anons).
// Object Create/Step/Draw call these; self is the vs_downloader_browser
// instance. Requires vsml to Import() codes/ GlobalScripts + Object events
// in one CodeImportGroup so vs_* names resolve as global functions.
// ============================================================================

function vs_dlbr_open_from_menu()
{
    if (!instance_exists(vs_downloader_browser))
    {
        instance_create_depth(0, 0, -10000, vs_downloader_browser);
    }
    if (instance_exists(vs_downloader_browser))
    {
        with (vs_downloader_browser)
        {
            do_step = method(id, vs_dlbr_step);
            do_draw = method(id, vs_dlbr_draw);
            vs_dlbr_fetch_page();
        }
    }
}

function vs_dlbr_set_status(_msg)
{
    status = _msg;
}

function vs_dlbr_build_row(_song)
{
    var ch = variable_struct_exists(_song, "chartId") ? _song.chartId : "";
    if (ch != "" && !vs_songstore_has_chart(ch)) vs_songstore_cleanup_stub(ch);
    return
    {
        id: variable_struct_exists(_song, "id") ? _song.id : "",
        chartId: ch,
        name: variable_struct_exists(_song, "name") ? _song.name : "",
        artist: variable_struct_exists(_song, "artist") ? _song.artist : "",
        chartCount: variable_struct_exists(_song, "chartCount") ? _song.chartCount : 0,
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

function vs_dlbr_selected_refresh()
{
    if (array_length(rows) == 0)
    {
        vs_dlbr_set_status(view == 0 ? "No charts match the current filter/page." : "No local charts in Custom Songs/.");
        return;
    }
    var r = rows[sel];
    vs_dlbr_set_status(vs_dlmgr_row_status(r));
    if (view == 0 && r.downloaded && !r.checked)
    {
        var ai = vs_dlbr_row_all_index(r.chartId);
        if (ai >= 0) vs_dlbr_check_row_index(ai);
    }
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
    vs_dlmgr_list(query, page, method(self, vs_dlbr_on_list));
}

function vs_dlbr_on_list(_ok, _data)
{
    loading = false;
    if (_ok && _data != undefined)
    {
        var arr = [];
        var songs = _data.songs;
        total = floor(_data.total);
        maxpage = max(1, ceil(total / 100));
        var i = 0;
        repeat (array_length(songs))
        {
            array_push(arr, vs_dlbr_build_row(songs[i]));
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
    vs_dlmgr_check(r.id, r.chartId, method(self, vs_dlbr_on_check));
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
                vs_dlbr_set_status(rr.chartId + " recognized as downloaded (content matches server) - recorded.");
            }
            else
            {
                rr.need = -3;
                vs_dlbr_set_status(rr.chartId + " is a local chart without a download record - protected, not overwritten.");
            }
            break;
        }
        i++;
    }
    if (check_all)
    {
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
            if (after.tracked && after.need > 0)
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
    vs_dlbr_set_status("Downloading " + _r.name + " ...");
    vs_dlmgr_download(_r.id, _r.chartId, method(self, vs_dlbr_on_download));
}

function vs_dlbr_on_download(_ok)
{
    updating = false;
    var cancelled = variable_global_exists("vs_dlmgr_dl") && global.vs_dlmgr_dl.cancel;
    if (cancelled)
    {
        vs_dlbr_set_status("Download cancelled.");
        vs_dlbr_fetch_page();
        return;
    }
    if (_ok)
    {
        vs_dlbr_set_status("Done - " + cur_chart + " (rescanning custom songs...)");
        vs_dlbr_finalize_install();
    }
    else
    {
        var why = "";
        if (variable_global_exists("vs_dlmgr_dl") && variable_struct_exists(global.vs_dlmgr_dl, "err") && global.vs_dlmgr_dl.err != "")
        {
            why = " - " + string(global.vs_dlmgr_dl.err);
        }
        vs_dlbr_set_status("Failed - " + cur_chart + why);
        vs_dlbr_fetch_page();
    }
}

function vs_dlbr_do_selected_action()
{
    if (array_length(rows) == 0) return;
    if (updating) return;
    var r = rows[sel];
    if (!r.downloaded)
    {
        vs_dlbr_start_download(r);
        return;
    }
    var ai = vs_dlbr_row_all_index(r.chartId);
    if (ai < 0) return;
    var rr = rows_all[ai];
    if (rr.tracked)
    {
        if (!rr.checked)
        {
            enter_act = true;
            vs_dlbr_check_row_index(ai);
            return;
        }
        if (rr.need > 0)
        {
            vs_dlbr_start_download(rr);
        }
        else
        {
            vs_dlbr_set_status(r.chartId + " is up to date.");
        }
    }
    else
    {
        if (!vs_songstore_has_chart(r.chartId))
        {
            vs_dlbr_start_download(r);
            return;
        }
        if (!rr.checked) { vs_dlbr_check_row_index(ai); }
        vs_dlbr_set_status(r.chartId + " is a local chart without a download record - not overwritten.");
    }
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
    vs_dlmgr_download(r.id, r.chartId, method(self, vs_dlbr_on_batch));
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
    view = (view == 0) ? 1 : 0;
    page = 1;
    sel = 0;
    vs_dlbr_fetch_page();
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

function vs_dlbr_jump_from_local()
{
    if (array_length(local_rows) == 0) return;
    var lr = local_rows[sel];
    if (vs_localcharts_jump(lr.chart_id))
    {
        return;
    }
    vs_dlbr_set_status(lr.name + " is not in the song list - enable the Custom Songs Mod and reload (R).");
}

function vs_dlbr_reload_data()
{
    vs_dlbr_fetch_page();
}

function vs_dlbr_step()
{
    if (instance_exists(vs_online_error)) return;

    started++;
    if (started < 8) return;

    if (searching)
    {
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

    if (keyboard_check_pressed(vk_escape))
    {
        instance_destroy();
        return;
    }

    if (loading || checking) return;

    if (view == 0)
    {
        var n = array_length(rows);

        if (n == 0)
        {
            if (keyboard_check_pressed(ord("R"))) vs_dlbr_reload_data();
            else if (keyboard_check_pressed(ord("V"))) vs_dlbr_toggle_view();
            else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
            return;
        }

        if (keyboard_check_pressed(vk_up))
        {
            sel = (sel + n - 1) % n;
            vs_dlbr_selected_refresh();
        }
        else if (keyboard_check_pressed(vk_down))
        {
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
            vs_dlbr_do_selected_action();
        }
        else if (keyboard_check_pressed(ord("V")))
        {
            vs_dlbr_toggle_view();
        }
        else if (keyboard_check_pressed(ord("R")))
        {
            vs_dlbr_reload_data();
        }
    }
    else
    {
        var ln = array_length(local_rows);

        if (ln == 0)
        {
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
            vs_dlbr_jump_from_local();
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
    }
}

function vs_dlbr_draw()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var bw = 320;
    var bh = 176;
    var bx = (cw - bw) / 2;
    var by = (ch - bh) / 2;
    var rowh = 13;

    draw_set_alpha(0.7);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);

    draw_set_color(c_black);
    draw_rectangle(bx - 2, by - 2, bx + bw + 2, by + bh + 2, false);
    draw_set_color(c_white);
    draw_rectangle(bx, by, bx + bw, by + bh, true);

    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_aqua);
    draw_text(bx + 6, by + 3, "Chart Downloader");
    draw_set_font(global.default_font);

    if (view == 0)
    {
        var head = "WEB  page " + string(page) + "/" + string(maxpage) + "  (" + string(total) + ")";
        if (query != "") head += "  q=\"" + query + "\"";
        head += "  [" + vs_dlmgr_filter_name(filter) + "]";
        draw_set_color(c_white);
        draw_text(bx + 6, by + 15, head);

        if (searching)
        {
            draw_set_color(c_lime);
            draw_text(bx + 6, by + 15, "Search: " + query + "_");
        }

        var vis = 8;
        var start_idx = max(0, sel - 3);
        var end_idx = min(array_length(rows), start_idx + vis);
        var ty = by + 27;
        for (var r = start_idx; r < end_idx; r++)
        {
            var s = rows[r];
            var isSel = (r == sel);
            var st = ".";
            if (s.downloaded && !s.tracked) st = "L";
            else if (s.downloaded) st = (s.checked && s.need > 0) ? "U" : "D";
            draw_set_color(isSel ? c_yellow : (st == "U" ? c_aqua : (st == "L" ? c_orange : c_white)));
            var line = (isSel ? ">" : " ") + st + "  " + s.name + "  -  " + s.artist;
            if (s.chartCount > 0) line += "  [" + string(s.chartCount) + "]";
            draw_text(bx + 6, ty + ((r - start_idx) * rowh), line);
        }
        if (array_length(rows) == 0)
        {
            draw_set_color(c_white);
            draw_text(bx + 6, ty + 2, "No charts match.");
        }
    }
    else
    {
        draw_set_color(c_white);
        var lhead = "LOCAL  (" + string(array_length(local_rows)) + "/" + string(array_length(local_all)) + ")";
        if (query != "") lhead += "  q=\"" + query + "\"";
        draw_text(bx + 6, by + 15, lhead);
        if (searching)
        {
            draw_set_color(c_lime);
            draw_text(bx + 6, by + 15, "Search: " + query + "_");
        }

        var vis = 8;
        var start_idx = max(0, sel - 3);
        var end_idx = min(array_length(local_rows), start_idx + vis);
        var ty = by + 27;
        for (var r = start_idx; r < end_idx; r++)
        {
            var s = local_rows[r];
            var isSel = (r == sel);
            var st = vs_dlmgr_tracked(s.chart_id) ? "D" : "L";
            draw_set_color(isSel ? c_yellow : (st == "D" ? c_white : c_orange));
            draw_text(bx + 6, ty + ((r - start_idx) * rowh), (isSel ? ">" : " ") + st + "  " + s.name + "  -  " + s.artist);
            if (isSel)
            {
                var dstr = "";
                var d = 0;
                repeat (array_length(s.diffs))
                {
                    if (d > 0) dstr += "/";
                    dstr += s.diffs[d];
                    d++;
                }
                var tag = vs_dlmgr_tracked(s.chart_id) ? " downloaded" : " local (no record)";
                draw_set_color(c_gray);
                draw_text(bx + 6, ty + ((r - start_idx) * rowh) + 14, "[" + s.pack + "]  " + dstr + tag + (s.in_select ? "" : "  (not in select)"));
            }
        }
        if (array_length(local_rows) == 0)
        {
            draw_set_color(c_white);
            draw_text(bx + 6, ty + 2, "No custom charts in Custom Songs/.");
        }
    }

    var st = string(status);
    if (string_length(st) > 52) st = string_copy(st, 1, 49) + "...";
    draw_set_color(c_lime);
    draw_text(bx + 6, by + bh - 28, st);

    var hint1 = "";
    var hint2 = "";
    if (searching)
    {
        hint1 = "Enter confirm";
        hint2 = "Esc cancel";
    }
    else if (view == 0)
    {
        hint1 = "Enter act   Tab search   F filter";
        hint2 = "<> page   V local   Esc close";
    }
    else
    {
        hint1 = "Enter jump   Tab search";
        hint2 = "V web   Esc close";
    }
    draw_set_color(c_gray);
    draw_text(bx + 6, by + bh - 17, hint1);
    draw_text(bx + 6, by + bh - 8, hint2);

    if (updating) vs_dlbr_draw_dl_popup();

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

function vs_dlbr_draw_dl_popup()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var pw = 220;
    var ph = 78;
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
    draw_text(px + pw / 2, py + 4, title);
    draw_set_font(global.default_font);
    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text(px + 8, py + 20, files);
    draw_set_color(c_gray);
    if (string_length(fname) > 28) fname = string_copy(fname, 1, 25) + "...";
    draw_text(px + 8, py + 32, fname);

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
