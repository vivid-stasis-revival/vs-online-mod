load_selected_song_info = function()
{
    var scr = vs_csm_shatter_hs_row(selected_song.song_id);
    selected_song_score = (scr != undefined) ? scr.score : 0;
    selected_song_combo_record = (scr != undefined) ? scr.max_combo : 0;
    selected_song_notes = LoadSongDataNoteCount(selected_song.chart_id, selected_song.difficulty_name);
    // Match freeplay: keep song_stat_page across song changes (only Create resets).
    vs_csm_shatter_stats_reload();
};
