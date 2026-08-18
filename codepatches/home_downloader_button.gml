// VS Online: Chart Downloader — home-menu entry
instance_create_depth(0, 0, -2000, o_newbanner);
createButton(
{
    icon_sprite: sp_icon_vs_local,
    button_text: "Chart Downloader",
    alpha_obfuscate: 1,
    activate: vs_dlbr_open_from_menu
});
