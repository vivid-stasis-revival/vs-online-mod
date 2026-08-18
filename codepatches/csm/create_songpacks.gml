
if (!string_starts_with(global.song_packs[0].name, "FCP2")&&struct_exists(global, "custom_song_packs")){
    
    // var log = file_text_open_append(working_directory + "CustomSongMod_log.txt");
    
    for(var i = 0; i < array_length(global.custom_song_packs); i++){
        array_push(global.song_packs, global.custom_song_packs[i]);
            // file_text_write_string(log, "\n\nPushing custom pack: \n");
            // file_text_write_string(log, json_stringify(global.custom_song_packs[i]));
        
    }
    
    // file_text_close(log);

}