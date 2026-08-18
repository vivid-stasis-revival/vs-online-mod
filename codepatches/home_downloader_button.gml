// ============================================================================
// VS Online: Chart Downloader — home-menu entry
// Replaces the `o_newbanner` spawn line in o_newmenu_main_Create_0 so the
// button is created after event_inherited() (createButton must be defined).
// ============================================================================
instance_create_depth(0, 0, -2000, o_newbanner);
createButton(
{
    icon_sprite: sp_icon_vs_local,
    button_text: "Chart Downloader",
    alpha_obfuscate: 1,
    activate: function()
    {
        play_se(select);
        is_active = false;
        if (!instance_exists(vs_downloader_browser))
            instance_create_depth(0, 0, -10000, vs_downloader_browser);
    }
});
