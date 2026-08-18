createButton(
{
    icon_sprite: sp_icon_multiplayer,
    alpha_obfuscate: 1,
    button_text: "Worldcross Play",
    
    activate: function()
    {
        transitionToScene(scene_multiplayer_lobby, true, 1);
    }
});
createButton(
{
    icon_sprite: sp_icon_vs_local,
    button_text: "Chart Downloader",
    alpha_obfuscate: 1,
    activate: vs_dlbr_open_from_menu
});
