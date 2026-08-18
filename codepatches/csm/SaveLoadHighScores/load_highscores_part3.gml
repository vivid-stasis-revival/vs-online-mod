        if (struct_exists(song, "is_custom"))
            global.highscores.shatter[i] = load_score(song.chart_id, song.difficulty_name, true);
        else
            global.highscores.shatter[i] = load_score(string(i), song.difficulty_name);