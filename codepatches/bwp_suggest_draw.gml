if (vs_lobby_lobby_id() > 0 && vs_lobby_is_owner())
{
    var _sq = vs_lobby_suggest_q();
    if (array_length(_sq) > 0)
    {
        suggestSong = _sq[0];
        var song = global.song_list[suggestSong.songId];
        var member = o_st_handle.getMember(suggestSong.member);
        var member_name = (member != undefined) ? member.name : "N/A";
        var grad1, grad2;

        switch (suggestSong.difficulty)
        {
            case 0:
                grad1 = 2227968;
                grad2 = 16776960;
                break;
            case 1:
                grad1 = 16776960;
                grad2 = 16721408;
                break;
            case 2:
                grad1 = 27391;
                grad2 = 255;
                break;
            case 3:
                if (struct_exists(song, "enc_data") && struct_get_fallback(song.enc_data, "hide_backstage", false) == false)
                {
                    grad1 = 8355839;
                    grad2 = 7209215;
                }
                else
                {
                    grad1 = 16711858;
                    grad2 = 16721408;
                }
                break;
        }

        draw_set_color(c_black);
        draw_set_alpha(0.7);
        draw_rectangle(80, 60, 240, 120, false);
        draw_set_alpha(1);
        draw_rectangle(80, 60, 240, 120, true);
        draw_set_halign(fa_center);
        draw_set_color(c_white);
        var _ft = vs_font_begin(string(member_name) + string(song_get_info(song, "name", suggestSong.difficulty)));
        draw_text(160, 60, @@string@@("{0} suggested", member_name), 65535, 0);
        draw_text_ext_color(160, 75, @@string@@("{0}", song_get_info(song, "name", suggestSong.difficulty)), 9, 125, grad1, grad1, grad2, grad2, draw_get_alpha());
        draw_text(160, 110, "CONFIRM:ACCEPT / ESCAPE:IGNORE");
        vs_font_end(_ft);
    }
}
vs_lobby_dl_draw();
