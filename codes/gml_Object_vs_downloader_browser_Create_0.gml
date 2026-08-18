// ============================================================================
// Chart Downloader — Create  (vs_downloader_browser)
//
// Web tab:  browse the live vs-server-go catalog (page/size=100), search by
//           ?q=, filter (All / Not downloaded / Downloaded / Updates
//           available), per-row local state (downloaded / UPDATE (N files))
//           with lazy sha1 diff, single + batch (page) download/update.
// Local tab: list local custom songs (CSM format) and jump into the song
//           select at a chart's position.
//
// Keys:
//   Up/Down     move selection
//   Left/Right  previous / next page (Web tab)
//   Tab         search (type + Enter; Esc/Tab to exit)
//   F           cycle filter
//   K           check the whole current page for updates
//   G           update every outdated chart on the current page
//   Enter       download / update the selected chart (Web) or jump (Local)
//   V           toggle Web / Local
//   R           reload (search keeps, local rescan)
//   Esc         back
// ============================================================================
depth = -10000;

view = 0;            // 0 = Web, 1 = Local
page = 1;
maxpage = 1;
total = 0;
query = "";
searching = false;
filter = 0;          // 0 all, 1 not downloaded, 2 downloaded, 3 updates

rows_all = [];       // current server page rows (annotated, unfiltered)
rows = [];           // filtered display rows
local_all = [];      // unfiltered local scan
local_rows = [];     // local view rows (search-filtered)

sel = 0;
started = 0;         // input debounce after opening

loading = false;     // server list request in flight
checking = false;    // a single sha1 check in flight
updating = false;    // download in flight (single or batch)
check_all = false;   // page-wide check in progress
check_idx = 0;       // cursor for page-wide check
update_queue = [];   // batch update queue (indices into rows_all)
update_qidx = 0;

// instance-held context for callbacks (no closure capture)
check_chart = "";
batch_name = "";
cur_id = "";
cur_chart = "";

status = "Chart Downloader - loading...";

// ---------------------------------------------------------------------------
self.build_row = function(_song)
{
    var ch = variable_struct_exists(_song, "chartId") ? _song.chartId : "";
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
};

self.set_status = function(_msg)
{
    status = _msg;
};

// Index of a chart inside rows_all (-1 when absent).
self.row_all_index = function(_chartId)
{
    var n = array_length(rows_all);
    for (var i = 0; i < n; i++)
    {
        if (rows_all[i].chartId == _chartId) return i;
    }
    return -1;
};

// Rebuild the filtered display rows from rows_all.
// Filter 2 "Downloaded" = charts WE downloaded (tracked); an untracked local
// chart with the same id stays out of it (it shows as "L" under All).
self.apply_filter = function()
{
    var arr = [];
    var n = array_length(rows_all);
    for (var i = 0; i < n; i++)
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
    }
    rows = arr;
    if (sel >= array_length(rows)) sel = array_length(rows) - 1;
    if (sel < 0) sel = 0;
};

self.selected_refresh = function()
{
    if (array_length(rows) == 0)
    {
        set_status(view == 0 ? "No charts match the current filter/page." : "No local charts in Custom Songs/.");
        return;
    }
    var r = rows[sel];
    set_status(vs_dlmgr_row_status(r));
    if (view == 0 && r.downloaded && !r.checked)
    {
        var ai = row_all_index(r.chartId);
        if (ai >= 0) check_row_index(ai);
    }
};

// Fetch the current view (server page or local list).
self.fetch_page = function()
{
    if (view == 1)
    {
        reload_local();
        return;
    }
    loading = true;
    if (!vs_online_is_custom())
    {
        loading = false;
        rows_all = [];
        apply_filter();
        set_status("Custom Server is off - enable it in Settings, or press V for Local charts.");
        return;
    }
    // Guests / not-logged-in: web catalog, downloads and update checks are
    // disabled — only locally-downloaded charts can be played (Local tab).
    if (!vs_online_is_account())
    {
        loading = false;
        rows_all = [];
        total = 0;
        maxpage = 1;
        apply_filter();
        set_status("Guest / not logged in - online catalog disabled. Play downloaded charts (V -> Local) or log in: Settings -> VS Online -> Log In.");
        return;
    }
    set_status(query == "" ? "Loading charts..." : "Search: \"" + query + "\" ...");
    vs_dlmgr_list(query, page, method(self, function(_ok, _data)
    {
        loading = false;
        if (_ok && _data != undefined)
        {
            var arr = [];
            var songs = _data.songs;
            total = floor(_data.total);
            maxpage = max(1, ceil(total / 100));
            for (var i = 0; i < array_length(songs); i++)
            {
                array_push(arr, build_row(songs[i]));
            }
            rows_all = arr;
        }
        else
        {
            total = 0;
            maxpage = 1;
            rows_all = [];
        }
        apply_filter();
        selected_refresh();
    }));
};

// --- sha1 check -----------------------------------------------------------
// Check rows_all[ai]; marks checked and stores the need count.
//   tracked download  -> need = number of files to update
//   untracked folder  -> if content matches the server, adopt it (record it);
//                        otherwise PROTECT it (a local chart that happens to
//                        share the id — never overwritten).
self.check_row_index = function(_ai)
{
    if (_ai < 0 || _ai >= array_length(rows_all)) return;
    var r = rows_all[_ai];
    if (!r.downloaded || r.checked) return;
    r.checked = true;
    checking = true;
    check_chart = r.chartId;
    set_status("Checking " + r.chartId + " ...");
    vs_dlmgr_check(r.id, r.chartId, method(self, function(_ok, _need)
    {
        checking = false;
        var n = array_length(rows_all);
        for (var i = 0; i < n; i++)
        {
            if (rows_all[i].chartId == check_chart)
            {
                var rr = rows_all[i];
                var cnt = _ok ? array_length(_need) : -2; // -2 = server error
                if (rr.tracked)
                {
                    rr.need = cnt;
                }
                else if (cnt == 0 && _ok)
                {
                    // server content identical -> it IS a prior download:
                    // adopt it (record it) so it's tracked from now on.
                    vs_dlmgr_write_meta(rr.chartId, rr.id, rr.name);
                    rr.tracked = true;
                    rr.need = 0;
                    set_status(rr.chartId + " recognized as downloaded (content matches server) - recorded.");
                }
                else
                {
                    rr.need = -3; // protected: local chart, differs from server
                    set_status(rr.chartId + " is a local chart without a download record - protected, not overwritten.");
                }
                break;
            }
        }
        if (check_all)
        {
            check_next();
        }
        else
        {
            apply_filter();
            selected_refresh();
        }
    }));
};

// Page-wide check driver: serially checks every downloaded, unchecked row.
self.check_next = function()
{
    var n = array_length(rows_all);
    while (check_idx < n)
    {
        var r = rows_all[check_idx];
        if (r.downloaded && !r.checked)
        {
            check_idx++;
            check_row_index(check_idx - 1);
            return;
        }
        check_idx++;
    }
    check_all = false;
    apply_filter();
    selected_refresh();
    set_status("Checked " + string(n) + " chart(s) on this page.");
};

self.check_all_rows = function()
{
    if (view == 1) return;
    if (checking || updating) return;
    check_all = true;
    check_idx = 0;
    set_status("Checking whole page for updates...");
    check_next();
};

// --- download / update ----------------------------------------------------
// Uses vs_dlmgr_download (detail -> diff -> serial download) which leaves CSM's
// in-memory song list untouched; we rebuild it cleanly via vs_localcharts_refresh
// so CSM never sees duplicates. (The old vs_songstore_download called
// CustomSongReader() per download, which APPENDED every custom song again —
// that duplicated entries in the song select.)
self.finalize_install = function()
{
    vs_localcharts_refresh(); // CSM-guarded: rebuilds song_list + packs once
    fetch_page();             // refresh local state + UI
};

self.start_download = function(_r)
{
    if (updating) return;
    updating = true;
    cur_id = _r.id;
    cur_chart = _r.chartId;
    set_status("Downloading " + _r.name + " ...");
    vs_dlmgr_download(_r.id, _r.chartId, method(self, function(_ok)
    {
        updating = false;
        if (_ok)
        {
            set_status("Done - " + cur_chart + " (rescanning custom songs...)");
            finalize_install();
        }
        else
        {
            set_status("Failed - " + cur_chart);
            fetch_page();
        }
    }));
};

// Enter on the Web tab.
self.do_selected_action = function()
{
    if (array_length(rows) == 0) return;
    if (updating) return;
    var r = rows[sel];
    if (!r.downloaded)
    {
        start_download(r);
        return;
    }
    var ai = row_all_index(r.chartId);
    if (ai < 0) return;
    var rr = rows_all[ai];
    if (rr.tracked)
    {
        if (!rr.checked)
        {
            check_row_index(ai);
            set_status("Checking " + r.chartId + " - press Enter again to update.");
            return;
        }
        if (rr.need > 0)
        {
            start_download(rr);
        }
        else
        {
            set_status(r.chartId + " is up to date.");
        }
    }
    else
    {
        // An untracked local chart with this id exists — never overwrite it.
        if (!rr.checked) { check_row_index(ai); }
        set_status(r.chartId + " is a local chart without a download record - won't be overwritten (press K to classify it).");
    }
};

// G: update every outdated chart on the current page (serial).
// Only tracked downloads are updated — untracked local charts are never touched.
self.batch_update = function()
{
    if (view == 1 || updating || checking) return;
    var q = [];
    var n = array_length(rows_all);
    for (var i = 0; i < n; i++)
    {
        var r = rows_all[i];
        if (r.tracked && r.checked && r.need > 0) array_push(q, i);
    }
    if (array_length(q) == 0)
    {
        set_status("No tracked updates on this page. Press K to check the page first.");
        return;
    }
    update_queue = q;
    update_qidx = 0;
    updating = true;
    set_status("Updating " + string(array_length(q)) + " chart(s) on this page...");
    batch_next();
};

self.batch_next = function()
{
    if (update_qidx >= array_length(update_queue))
    {
        updating = false;
        update_queue = [];
        set_status("Page updates done - rescanning custom songs ...");
        finalize_install();
        return;
    }
    var ri = update_queue[update_qidx];
    var r = rows_all[ri];
    batch_name = r.name;
    vs_dlmgr_download(r.id, r.chartId, method(self, function(_ok)
    {
        update_qidx++;
        set_status("Updating " + batch_name + " (" + string(update_qidx) + "/" + string(array_length(update_queue)) + ") ...");
        batch_next();
    }));
};

// --- search / filter / view ------------------------------------------------
self.cycle_filter = function()
{
    if (view == 1) return;
    filter = (filter + 1) % 4;
    set_status("Filter: " + vs_dlmgr_filter_name(filter));
    if (filter == 3)
    {
        check_all_rows();
        return;
    }
    apply_filter();
    selected_refresh();
};

self.toggle_view = function()
{
    view = (view == 0) ? 1 : 0;
    page = 1;
    sel = 0;
    fetch_page();
};

// --- local -----------------------------------------------------------------
self.apply_local_filter = function()
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
};

self.reload_local = function()
{
    local_all = vs_localcharts_scan();
    apply_local_filter();
    set_status((array_length(local_rows) > 0)
        ? ("Local charts: " + string(array_length(local_rows)) + "/" + string(array_length(local_all)) + "  (Enter: jump, Tab: search, R: reload)")
        : (query == "" ? "No local charts in Custom Songs/." : "No local charts match \"" + query + "\"."));
};

self.jump_from_local = function()
{
    if (array_length(local_rows) == 0) return;
    var lr = local_rows[sel];
    if (vs_localcharts_jump(lr.chart_id))
    {
        return; // leaving the room
    }
    set_status(lr.name + " is not in the song list - enable the Custom Songs Mod and reload (R).");
};

self.reload_data = function()
{
    fetch_page();
};

fetch_page();
