// VS Online <-> betterWP conflict check.
// Runs at o_st_handle Create (after all mods' initiategame mod_info blocks have
// registered into global.vml_mods), so it is order-independent.
// betterWP patches the same WP code entries as this mod; installing both makes
// the result depend on patch order. Hard-stop at startup.
if (variable_global_exists("vml_mods"))
{
    var _vm = variable_global_get("vml_mods");
    if (variable_struct_exists(_vm, "betterWP_mod"))
    {
        show_message("VS Online 与 betterWP 不兼容，请移除其一后重试。\n\nVS Online is incompatible with betterWP — please remove one of them and restart.");
    }
}
