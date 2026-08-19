function parse_custom_extra_value(arg0)
{
    var aliasMaps =
    {
        t: 0,
        b: 1,
        v: 2,
        s: 3
    };

    if (arg0 == "")
        return 404;

    var d = {};
    var extraList = string_split(arg0, "|");

    for (var i = 0; i < array_length(extraList); i++)
    {
        var extraData = extraList[i];
        var arrKeyVal = string_split(extraData, ":");
        if (array_length(arrKeyVal) < 2) continue;
        var key = variable_struct_get(aliasMaps, arrKeyVal[0]);
        var val = (arrKeyVal[1] == "undefined") ? undefined : real(arrKeyVal[1]);
        variable_struct_set(d, key, val);
    }

    return d;
}

function load_text_chart(path, diff)
{
    if (path == undefined) path = "";
    path = vs_csm_norm_dir(path);
    var picked = vs_csm_pick_diff_file(path, diff);
    if (picked == undefined)
    {
        vs_csm_play_log("no .vsc in " + path + " want=" + string(diff));
        return vs_csm_empty_chart();
    }
    if (picked.diff != string(diff))
        vs_csm_play_log("want " + string(diff) + " missing, using " + picked.diff);

    var filePath = picked.path;
    var modDefinition = undefined;
    try { modDefinition = load_text_mods(path + picked.diff + ".vsm"); }
    catch (_m) { vs_csm_play_log("vsm fail " + path + picked.diff + " " + string(_m)); }

    var map = file_text_open_read(filePath);
    if (map == -1)
    {
        vs_csm_play_log("open fail " + filePath);
        return vs_csm_empty_chart();
    }

    var lines = [];
    while (!file_text_eof(map))
    {
        array_push(lines, file_text_read_string(map));
        file_text_readln(map);
    }
    file_text_close(map);

    var notes = [];
    var skipped = 0;
    for (var i = 0; i < array_length(lines); i++)
    {
        var parts = split_string(",", lines[i], false);
        if (array_length(parts) < 3)
            continue;
        var time = vs_csm_safe_real(parts[0], undefined);
        var type = vs_csm_safe_real(parts[1], undefined);
        var lane = vs_csm_safe_real(parts[2], undefined);
        if (time == undefined || type == undefined || lane == undefined)
        {
            skipped += 1;
            continue;
        }
        var extra = {};
        if (array_length(parts) > 3)
        {
            if (type == 2)
            {
                variable_struct_set(extra, 1, vs_csm_safe_real(parts[3], time));
            }
            else if (type == 3)
            {
                extra = parse_custom_extra_value(parts[3]);
                if (!is_struct(extra)) extra = {};
            }
            else
            {
                extra = parts[3];
            }
        }

        array_push(notes,
        {
            time: time,
            type: type,
            lane: lane,
            extra: extra
        });
    }

    array_sort(notes, function(a, b)
    {
        return a.time - b.time;
    });
    vs_csm_play_log("loaded " + filePath + " notes=" + string(array_length(notes)) + " skip=" + string(skipped));
    return
    {
        notes: notes,
        mods: modDefinition
    };
}
