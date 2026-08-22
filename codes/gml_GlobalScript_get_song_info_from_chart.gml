function get_chart_path_from_chart(chart)
{
    for (var i = 0; i < array_length(global.song_list); i++)
    {
        if (global.song_list[i].chart_id == chart)
            return struct_get_fallback(global.song_list[i], "chart_load_dir",
                struct_get_fallback(global.song_list[i], "chart_path", "Charts/" + chart + "/"));
    }

    if (variable_global_exists("shatter_list"))
    {
        for (var j = 0; j < array_length(global.shatter_list); j++)
        {
            if (global.shatter_list[j].chart_id == chart)
                return struct_get_fallback(global.shatter_list[j], "chart_load_dir",
                    struct_get_fallback(global.shatter_list[j], "chart_path", "Charts/" + chart + "/"));
        }
    }

    var found = vs_csm_search_load_dir(chart);
    if (found != "") return found;
    var off = vs_csm_official_chart_dir(chart);
    if (off != "") return off;
    return "Charts/" + chart + "/";
}
