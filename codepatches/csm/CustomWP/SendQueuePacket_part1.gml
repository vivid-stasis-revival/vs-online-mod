for (var i = 0; i < items; i++)
    buffer_write(buffer, buffer_string, vs_online_chart_id_of_song(queue[i].songId));

if (previous_song_exists)
    buffer_write(buffer, buffer_string, vs_online_chart_id_of_song(o_st_handle.previousSong.songId));

return buffer;