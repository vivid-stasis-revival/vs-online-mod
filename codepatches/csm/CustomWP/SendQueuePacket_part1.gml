for (var i = 0; i < items; i++)
    buffer_write(buffer, buffer_string, vs_online_queue_chart_id(queue[i]));

if (previous_song_exists)
    buffer_write(buffer, buffer_string, vs_online_queue_chart_id(o_st_handle.previousSong));

return buffer;