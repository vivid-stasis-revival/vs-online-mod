if(!variable_global_exists("vml_mods")) global.vml_mods = {};
global.vml_mods.vs_online_mod = {
    name: "VS Online Mod",
    description: "Custom server backend for vivid/stasis (vs-server-go)",
    version: 100
};
vs_online_init();
