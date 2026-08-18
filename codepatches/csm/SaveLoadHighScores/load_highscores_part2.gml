            if (struct_exists(global.song_list[i], "is_custom"))
                scores[d] = load_score(global.song_list[i].chart_id, diff_names[d], true);
            else
                scores[d] = load_score(string(i), diff_names[d]);