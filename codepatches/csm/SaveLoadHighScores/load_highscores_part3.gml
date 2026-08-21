        if (struct_exists(song, "is_custom"))
        {
            // Prefer folder-unique section; fall back to legacy chart_id key only
            // when this folder is the canonical chart_id name (avoids cloning a
            // sibling folder's PB onto a duplicate chart_id entry).
            var sec = vs_csm_shatter_hs_section(song);
            var row = load_score(sec, song.difficulty_name, true);
            if (row.score == 0 && row.game_score == 0 && row.max_combo == 0
                && vs_csm_shatter_folder_name(song) == string(song.chart_id))
            {
                row = load_score(song.chart_id, song.difficulty_name, true);
            }
            global.highscores.shatter[i] = row;
        }
        else
            global.highscores.shatter[i] = load_score(string(i), song.difficulty_name);
