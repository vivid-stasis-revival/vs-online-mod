var statName = baseName + ".stats";
var baseCustomName = vs_csm_stat_dir(arg0) + arg1;
var customChartName = vs_csm_load_dir_from_id(arg0) + arg1 + ".vsc";
var customModName=vs_csm_load_dir_from_id(arg0) + arg1 + ".vsm";
var customStatName = baseCustomName + ".stats_custom";
var finalstatName = "";
var is_custom_chart = false;
