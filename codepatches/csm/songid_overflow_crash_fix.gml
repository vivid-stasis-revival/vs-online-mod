global.last_freeplay_song = ini_read_real("profile", "last_freeplay_song", 0);

if (variable_global_exists("song_list") && is_array(global.song_list)
    && global.last_freeplay_song>=array_length(global.song_list)){
    global.last_freeplay_pack=1;
    global.last_freeplay_song=44;
}

if (variable_global_exists("song_packs") && is_array(global.song_packs)
    && global.last_freeplay_pack>=array_length(global.song_packs)){
    global.last_freeplay_pack=1;
    global.last_freeplay_song=44;
}
