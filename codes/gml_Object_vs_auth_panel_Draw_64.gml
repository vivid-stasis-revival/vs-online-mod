// VS Online account panel — Draw GUI
var cw = display_get_gui_width();
var ch = display_get_gui_height();
var bw = 280;
var bh = signed_in ? 120 : 150;
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
draw_set_color(c_aqua);
draw_text(bx + bw / 2, by + 5, "VS Online Account");

draw_set_font(global.default_font);

if (signed_in)
{
    // --- account summary ---
    var cfg = vs_online_get_config();
    var nm = (variable_struct_exists(cfg, "name") && cfg.name != "") ? cfg.name : "Player";
    var em = (variable_struct_exists(cfg, "email") && cfg.email != "") ? cfg.email : "device flow";
    var pid = (variable_struct_exists(cfg, "playerId") && cfg.playerId != "") ? cfg.playerId : "";
    if (string_length(pid) > 12) { pid = string_copy(pid, 1, 12) + "..."; }

    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text(bx + 12, by + 24, "Name: " + nm);
    draw_text(bx + 12, by + 38, "Account: " + em);
    draw_text(bx + 12, by + 52, "Player ID: " + pid);

    var btn_w = 126;
    var btn_h = 18;
    var yb = by + bh - btn_h - 8;
    var i = 0;
    repeat (2)
    {
        var xb = bx + 8 + i * (btn_w + 8);
        var isSel = (i == sel);
        draw_set_color(isSel ? c_yellow : c_gray);
        draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, isSel);
        draw_set_color(isSel ? c_black : c_white);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(xb + btn_w / 2, yb + btn_h / 2, i == 0 ? "Sign Out" : "Close");
        i++;
    }

    if (message != "")
    {
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        draw_set_color(c_yellow);
        draw_text(bx + 12, by + 70, message);
    }
}
else
{
    // --- device-flow view ---
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_white);

    if (stage == 1 || busy)
    {
        var remain = max(0, expires_at - current_time / 1000);
        // user code, big
        draw_set_font(fnt_monacovs);
        draw_set_color(c_yellow);
        draw_set_halign(fa_center);
        draw_text(bx + bw / 2, by + 26, user_code == "" ? "..." : user_code);
        draw_set_font(global.default_font);
        draw_set_halign(fa_left);

        draw_set_color(c_white);
        draw_text_ext(bx + 12, by + 44, "Open this page in your browser and enter the code:", 10, bw - 24);
        draw_set_color(c_lime);
        draw_text_ext(bx + 12, by + 66, verification_uri, 10, bw - 24);
        draw_set_color(c_gray);
        draw_text(bx + 12, by + 92, "Code expires in " + string(ceil(remain)) + "s");
        draw_set_color(c_yellow);
        draw_text(bx + 12, by + 106, message);
    }
    else
    {
        // idle / failed: restart prompt
        draw_set_color(c_white);
        draw_text_ext(bx + 12, by + 26, "Sign in with your account via device flow.", 10, bw - 24);
        draw_set_color(c_yellow);
        draw_text_ext(bx + 12, by + 44, message, 10, bw - 24);
        draw_set_color(c_gray);
        draw_text_ext(bx + 12, by + 88, "Enter: start   Esc: close", 10, bw - 24);
    }
}

draw_set_halign(fa_left);
draw_set_valign(fa_top);
