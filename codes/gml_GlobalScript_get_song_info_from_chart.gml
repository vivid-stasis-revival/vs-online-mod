function get_chart_path_from_chart(chart)
{
    if (variable_global_exists("song_list") && is_array(global.song_list))
    {
        for (var i = 0; i < array_length(global.song_list); i++)
        {
            var s = global.song_list[i];
            if (s == undefined || !variable_struct_exists(s, "chart_id")) continue;
            if (s.chart_id == chart)
                return struct_get_fallback(s, "chart_load_dir",
                    struct_get_fallback(s, "chart_path", "Charts/" + chart + "/"));
        }
    }

    if (variable_global_exists("shatter_list") && is_array(global.shatter_list))
    {
        for (var j = 0; j < array_length(global.shatter_list); j++)
        {
            var sh = global.shatter_list[j];
            if (sh == undefined || !variable_struct_exists(sh, "chart_id")) continue;
            if (sh.chart_id == chart)
                return struct_get_fallback(sh, "chart_load_dir",
                    struct_get_fallback(sh, "chart_path", "Charts/" + chart + "/"));
        }
    }

    var found = vs_csm_search_load_dir(chart);
    if (found != "") return found;
    var off = vs_csm_official_chart_dir(chart);
    if (off != "") return off;
    return "Charts/" + chart + "/";
}
