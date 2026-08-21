load_selected_song_info = function()
{
    var scr = global.highscores.shatter[selected_song.song_id];
    selected_song_score = scr.score;
    selected_song_combo_record = scr.max_combo;
    selected_song_notes = LoadSongDataNoteCount(selected_song.chart_id, selected_song.difficulty_name);
    vs_csm_shatter_stats_reload();
};
