createButton(
{
    icon_sprite: sp_icon_vs_local,
    button_text: "Chart Downloader",
    alpha_obfuscate: 1,
    activate: function()
    {
        play_se(select);
        is_active = false;
        global.vs_dlbr_open();
    }
});
createButton(
{
    icon_sprite: sp_icon_song_shop,
    button_text: "Song Shop",
    alpha_obfuscate: 1,
    
    activate: function()
    {
        if (get_story_progress() >= 3 || global.op_access_unlockallmodes)
        {
            transitionToScene(scene_newstore, true, 3);
        }
        else
        {
            play_se(buzzer);
        }
    },
    
    unlock_text: "Complete Chapter 1",
    unlock_check: 3
});
