for (var i = 0; i < items; i++){
    try{
        obj[i].songId = vs_online_song_id_from_chart(buffer_read(arg0, buffer_string));
    }
    catch (ex){}
}

if (previous_song_exists)
    try{
        o_st_handle.previousSong.songId = vs_online_song_id_from_chart(buffer_read(arg0, buffer_string));
    }
    catch (ex){}

buffer_delete(arg0);