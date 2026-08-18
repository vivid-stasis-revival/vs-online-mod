for (var i = 0; i < items; i++)
    buffer_write(buffer, buffer_string, global.song_list[queue[i].songId].chart_id);

if (previous_song_exists)
    buffer_write(buffer, buffer_string, global.song_list[o_st_handle.previousSong.songId].chart_id);

return buffer;