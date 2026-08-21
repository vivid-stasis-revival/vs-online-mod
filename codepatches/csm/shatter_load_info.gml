load_selected_song_info = function()
{
    var scr = vs_csm_shatter_hs_row(selected_song.song_id);
    selected_song_score = (scr != undefined) ? scr.score : 0;
    selected_song_combo_record = (scr != undefined) ? scr.max_combo : 0;
    selected_song_notes = LoadSongDataNoteCount(selected_song.chart_id, selected_song.difficulty_name);
    song_stat_page = 0;
    song_stat_page_target = 0;
    vs_csm_shatter_stats_reload();
};
