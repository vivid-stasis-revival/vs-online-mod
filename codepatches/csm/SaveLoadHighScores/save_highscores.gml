ini_open(working_directory + "custom_highscore");

for (var i = 0; i < array_length(global.highscores.normal); i++)
{
    if (i >= array_length(global.song_list) || !struct_exists(global.song_list[i], "is_custom"))
        continue;

    var diff_names = ["OPENING", "MIDDLE", "FINALE", "ENCORE", "PRELUDE"];

    for (var d = 0; d < 5; d++)
    {
        var props = [["score", ""], ["game_score", "_GAME"], ["max_combo", "_MAXCOMBO"], ["lamp", "_COMBO"], ["game_perc", "_GAMEPERC"]];

        for (var p = 0; p < array_length(props); p++)
        {
            var prop = props[p];
            var value = variable_struct_get(array_get(array_get(global.highscores.normal, i), d), array_get(prop, 0));

            if (value != variable_struct_get(array_get(array_get(global.highscores_at_load.normal, i), d), array_get(prop, 0)))
            {
                ini_write_real(global.song_list[i].chart_id, diff_names[d] + prop[1], value);
                variable_struct_set(array_get(array_get(global.highscores_at_load.normal, i), d), array_get(prop, 0), value);
            }
        }
    }
}

for (var i = 0; i < array_length(global.highscores.shatter); i++)
{
    if (i >= array_length(global.shatter_list) || !struct_exists(global.shatter_list[i], "is_custom"))
        continue;

    var props = [["score", ""], ["game_score", "_GAME"], ["max_combo", "_MAXCOMBO"], ["lamp", "_COMBO"], ["game_perc", "_GAMEPERC"]];

    for (var p = 0; p < array_length(props); p++)
    {
        var prop = props[p];
        var value = variable_struct_get(array_get(global.highscores.shatter, i), array_get(prop, 0));

        if (value != variable_struct_get(array_get(global.highscores_at_load.shatter, i), array_get(prop, 0)))
        {
            ini_write_real(vs_csm_shatter_hs_section(global.shatter_list[i]), global.shatter_list[i].difficulty_name + prop[1], value);
            variable_struct_set(array_get(global.highscores_at_load.shatter, i), array_get(prop, 0), value);
        }
    }
}

ini_close();
ini_open(global.highscore_file);
