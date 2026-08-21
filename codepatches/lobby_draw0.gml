draw_set_default();

if (vs_lobby_lobby_id() <= 0)
{
    if (vs_lobby_browser_active())
    {
        vs_lobby_browser_draw();
    }
    else
    {
        var height = 19;
        var width = 110;
        var gap = 11;
        var itemCount = array_length(menu_actions_landing);
        var totalHeight = (itemCount * (height + gap)) - gap;
        var startY = floor((180 - totalHeight) / 2);

        for (var i = 0; i < itemCount; i++)
        {
            var _x = 104;
            var _y = startY + (i * (height + gap));
            draw_set_color(c_black);
            draw_rectangle(_x + 1, _y + 1, _x + 1 + width, _y + 1 + height, true);
            draw_set_color(c_white);
            draw_rectangle(_x + 1, _y + 1, _x + 1 + width, _y + 1 + height, false);

            if (i != cursor_pos)
            {
                draw_set_color(c_black);
                draw_rectangle(_x + 2, _y + 2, _x + width, _y + height, false);
            }

            draw_set_color((i == cursor_pos) ? c_black : c_white);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text(_x + 1 + floor(width / 2), _y + 2 + floor(height / 2), menu_actions_landing[i].txt);
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
        }

        draw_set_color(c_white);
        draw_set_halign(fa_center);
        // Avoid string("{0}") format braces — vsml/UTMT can mis-parse them as code blocks.
        draw_text_o(160, startY + totalHeight + 7, "Total Lobbies: " + string(lobbyCount) + "\nHold Shift and Press \"Paste Code\" to join random lobby");

        if (entering_code)
        {
            draw_sprite(sp_multiplayer_entercode, 0, 135, startY + totalHeight + 6);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text_o(160, startY + totalHeight + 7, string_upper(keyboard_string));
        }
    }
}

draw_set_halign(fa_left);
draw_set_color(c_white);
if (vs_online_is_custom())
    draw_text(2, 170, "Server:");
else
    draw_text(2, 170, "Steamworks:");

if (vs_online_is_connected())
{
    draw_set_color(c_lime);
    draw_text(2 + string_width("Steamworks: "), 170, "Connected");
}
else
{
    draw_set_color(c_red);
    draw_text(2 + string_width("Steamworks: "), 170, "Disconnected");
}
