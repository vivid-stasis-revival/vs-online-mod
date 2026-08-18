// Custom-server connection error dialog — Draw GUI
var cw = display_get_gui_width();
var ch = display_get_gui_height();
var bw = 280;
var bh = 130;
var bx = (cw - bw) / 2;
var by = (ch - bh) / 2;

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

// title
draw_set_font(fnt_monacovs);
draw_set_halign(fa_center);
draw_set_valign(fa_top);
draw_set_color(c_red);
draw_text(bx + bw / 2, by + 5, title);

// message
draw_set_font(global.default_font);
draw_set_color(c_white);
draw_text_ext(bx + 10, by + 22, message, 11, bw - 20);

// buttons
var btn_w = 126;
var btn_h = 18;
var yb = by + bh - btn_h - 8;
var i = 0;
repeat (array_length(buttons))
{
    var xb = bx + 8 + i * (btn_w + 8);
    var isSel = (i == selected);
    draw_set_color(isSel ? c_yellow : c_gray);
    draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, isSel);
    draw_set_color(isSel ? c_black : c_white);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text(xb + btn_w / 2, yb + btn_h / 2, buttons[i]);
    i++;
}

draw_set_halign(fa_left);
draw_set_valign(fa_top);
