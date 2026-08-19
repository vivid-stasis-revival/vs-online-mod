var filePath = working_directory + "Charts/" + arg0 + "/" + arg1 + ".vsb";
var chart = undefined;
var chartPath = "";
vs_csm_play_log("LoadSong chart=" + string(arg0) + " diff=" + string(arg1) + " vsb=" + string(file_exists(filePath)));

if (file_exists(filePath))
{
    chart = read_binary_chart(filePath);
}
else
{
    chartPath = get_chart_path_from_chart(arg0);
    vs_csm_play_log("custom path=" + string(chartPath));
    chart = load_text_chart(chartPath, arg1);
}

if (!is_struct(chart) || !variable_struct_exists(chart, "notes") || !is_array(chart.notes))
{
    vs_csm_play_log("chart invalid " + string(chart));
    chart = vs_csm_empty_chart();
}

if (is_struct(chart) && variable_struct_exists(chart, "mods") && chart.mods != undefined)
{
    try { modOutputer(chart.mods, global.songname, arg1, arg0); }
    catch (_mo) { vs_csm_play_log("modOutputer " + string(_mo)); }
}
