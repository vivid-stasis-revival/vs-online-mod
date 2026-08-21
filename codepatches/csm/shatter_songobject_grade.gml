var grade = 13;
var fc_lamp = 0;
var row = vs_csm_shatter_hs_row(song_id);
if (row != undefined)
{
    grade = get_score_grade(row.score);
    fc_lamp = row.lamp;
}
if (grade < UnknownEnum.Value_13)
{
    var grades = ["VS", "V+", "V", "SS+", "SS", "S+", "S", "AA", "A", "B", "C", "D", "E"];
    draw_text_grade_colour(185, 2, grades[grade], grade);
}
draw_sprite(sp_songobject_lamp, fc_lamp, 171, 12);
draw_set_color((o_songselect_shatter.cursor_pos == position) ? c_black : c_white);
if (song_id >= 0 && song_id < array_length(global.shatter_list))
    draw_text(88, 2, global.shatter_list[song_id].name);
draw_set_color(c_white);
if (song_id >= 0 && song_id < array_length(global.shatter_list))
    draw_text(88, 12, string(diff_name) + " " + string(global.shatter_list[song_id].difficulty_number));
