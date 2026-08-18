// ============================================================================
// Chart Downloader — Draw GUI
// ============================================================================
var cw = display_get_gui_width();
var ch = display_get_gui_height();
var bw = 312;
var bh = 168;
var bx = (cw - bw) / 2;
var by = (ch - bh) / 2;
var rowh = 13;

// full-screen dim
draw_set_alpha(0.7);
draw_set_color(c_black);
draw_rectangle(0, 0, cw, ch, false);
draw_set_alpha(1);

// panel
draw_set_color(c_black);
draw_rectangle(bx - 2, by - 2, bx + bw + 2, by + bh + 2, false);
draw_set_color(c_white);
draw_rectangle(bx, by, bx + bw, by + bh, true);

// header
draw_set_font(fnt_monacovs);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_color(c_aqua);
draw_text(bx + 6, by + 3, "Chart Downloader");
draw_set_font(global.default_font);

if (view == 0)
{
    // Web tab: page / total / search / filter
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

    // list window around the selection
    var vis = 8;
    var start_idx = max(0, sel - 3);
    var end_idx = min(array_length(rows), start_idx + vis);
    var ty = by + 27;
    for (var r = start_idx; r < end_idx; r++)
    {
        var s = rows[r];
        var isSel = (r == sel);
        // state marker:
        //   . = not downloaded, D = our download (tracked), U = update ready,
        //   L = local chart without a download record (same id, protected)
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
    // Local tab
    draw_set_color(c_white);
    draw_text(bx + 6, by + 15, "LOCAL  (" + string(array_length(local_rows)) + " charts)");

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
            for (var d = 0; d < array_length(s.diffs); d++)
            {
                if (d > 0) dstr += "/";
                dstr += s.diffs[d];
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

// status line
draw_set_color(c_lime);
draw_text(bx + 6, by + bh - 24, status);

// footer
draw_set_color(c_gray);
draw_text(bx + 6, by + bh - 11,
    view == 0
        ? "Enter: dl/update  Tab: search  F: filter  K: check page  G: update page  <-/->: page  V: local  R: reload  Esc: back"
        : "Enter: jump to chart  V: web  R: reload  Esc: back");

draw_set_halign(fa_left);
draw_set_valign(fa_top);
