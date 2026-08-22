create_shatter_list();
refresh_song_objects(0, true);
var want = -1;
if (variable_global_exists("force_song_select") && global.force_song_select >= 0)
{
    want = global.force_song_select;
}
else if (variable_global_exists("last_boundaryshatter_song"))
{
    want = global.last_boundaryshatter_song;
}
if (want >= 0)
{
    for (var i = 0; i < array_length(songs); i++)
    {
        var idx = songs[i][0];
        if (idx < 0 || idx >= array_length(song_list)) continue;
        var sh = song_list[idx];
        if (idx == want || (sh != undefined && sh.song_id == want))
        {
            cursor_pos = i;
            break;
        }
    }
    if (array_length(songs) > 0)
    {
        if (cursor_pos < 0 || cursor_pos >= array_length(songs)) cursor_pos = 0;
        var selIdx = songs[cursor_pos][0];
        if (selIdx >= 0 && selIdx < array_length(song_list))
        {
            selected_song = song_list[selIdx];
            play_preview(selected_song.preview_id);
        }
    }
}
global.force_song_select = -1;
