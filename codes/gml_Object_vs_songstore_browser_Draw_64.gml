// Web Charts browser — Draw GUI
var x0 = 8;
var y0 = 10;
var w = 304;
var rowh = 14;

draw_set_alpha(0.85);
draw_set_color(c_black);
draw_rectangle(x0 - 2, y0 - 2, x0 + w + 2, 174, true);
draw_set_alpha(1);

draw_set_font(fnt_monacovs);
draw_set_halign(fa_left);
draw_set_valign(fa_top);

// header
draw_set_color(c_white);
draw_text(x0 + 2, y0 + 1, "Web Charts — page " + string(page) + "/" + string(maxpage) + " (" + string(total) + " songs)");
if (failed)
{
    draw_set_color(c_red);
    draw_text(x0 + 2, y0 + 13, "Failed to reach the server.");
}
else if (searching)
{
    draw_set_color(c_lime);
    draw_text(x0 + 2, y0 + 13, "Search: " + query + "_");
}

// list
var ty = y0 + 28;
for (var i = 0; i < array_length(songs); i++)
{
    var s = songs[i];
    var isSel = (i == selected);
    draw_set_color(isSel ? c_yellow : c_white);
    var line = (isSel ? "> " : "  ") + s.name + "  -  " + s.artist;
    if (variable_struct_exists(s, "chartCount"))
    {
        line += "  [" + string(s.chartCount) + " diff";
        if (variable_struct_exists(s, "scoreCount"))
        {
            line += ", " + string(s.scoreCount) + " plays";
        }
        line += "]";
    }
    draw_text(x0 + 2, ty + (i * rowh), line);
    if (isSel)
    {
        var st = downloading ? "downloading..." : (selected_dl ? (selected_update ? "UPDATE AVAILABLE" : "downloaded") : "not downloaded");
        draw_set_color(selected_update ? c_aqua : c_lime);
        draw_text(x0 + 2, ty + (i * rowh) + 15, st);
        if (variable_struct_exists(s, "topScore") && s.topScore > 0)
        {
            draw_set_color(c_gray);
            draw_text(x0 + 2, ty + (i * rowh) + 27, "top score: " + string(s.topScore));
        }
    }
}

// footer
draw_set_color(c_gray);
draw_text(x0 + 2, 158, "Up/Down: select   Enter: download   Tab: search   <-/->: page   Esc: back");
