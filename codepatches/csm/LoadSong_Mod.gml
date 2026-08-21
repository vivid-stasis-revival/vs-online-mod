var filePath = working_directory + "Charts/" + arg0 + "/" + arg1 + ".vsb";
var chart = undefined;
// Custom Gimmicks processLanes uses chartPath + diff + ".vsv" and later
// cc.chartPath. Leaving "" for official .vsb made SV cache / gimmick I/O blow
// up after prepare-menu Enter (keyboard softlock). Custom .vsc was fine
// because the else-branch set chartPath. Worldcross uses the same LoadSong.
var chartPath = get_chart_path_from_chart(arg0);
if (chartPath == undefined || chartPath == "")
    chartPath = "Charts/" + arg0 + "/";
// Prefer absolute paths so gimmick/SV I/O does not depend on cwd.
if (string_pos(":", chartPath) != 2 && string_char_at(chartPath, 1) != "/" && string_char_at(chartPath, 1) != "\\")
    chartPath = working_directory + chartPath;
if (string_char_at(chartPath, string_length(chartPath)) != "/" && string_char_at(chartPath, string_length(chartPath)) != "\\")
    chartPath += "/";
if (variable_global_exists("song_id_last") && variable_global_exists("song_list")
    && global.song_id_last >= 0 && global.song_id_last < array_length(global.song_list)
    && variable_struct_exists(global.song_list[global.song_id_last], "is_custom"))
    vs_csm_force_gm_audio();
vs_csm_play_log("LoadSong chart=" + string(arg0) + " diff=" + string(arg1) + " vsb=" + string(file_exists(filePath)) + " path=" + string(chartPath) + " gm=" + string(global.op_use_gamemaker_audio));

if (file_exists(filePath))
{
    chart = read_binary_chart(filePath);
}
else
{
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
vs_csm_play_log("LoadSong parsed notes=" + string(array_length(chart.notes)) + " mods=" + string(variable_struct_exists(chart, "mods") && chart.mods != undefined));
