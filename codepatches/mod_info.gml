if(!variable_global_exists("vml_mods")) global.vml_mods = {};
global.vml_mods.vs_online_mod = {
    name: "VS Online Mod",
    description: "Custom server backend + Custom Songs for vivid/stasis",
    version: 100
};
if (vs_online_conflict_halt()) exit;
vs_online_init();
