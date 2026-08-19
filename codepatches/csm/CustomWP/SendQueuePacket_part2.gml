for (var i = 0; i < items; i++){
    try{
        obj[i].chart_id = buffer_read(arg0, buffer_string);
        obj[i].songId = vs_online_song_id_from_chart(obj[i].chart_id);
    }
    catch (ex){}
}

if (previous_song_exists)
    try{
        o_st_handle.previousSong.chart_id = buffer_read(arg0, buffer_string);
        o_st_handle.previousSong.songId = vs_online_song_id_from_chart(o_st_handle.previousSong.chart_id);
    }
    catch (ex){}

buffer_delete(arg0);