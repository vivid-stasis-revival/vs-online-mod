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
    var filePath = path + diff + ".vsc";
    var modDefinition = load_text_mods(path + diff + ".vsm");
    var map = file_text_open_read(filePath);
    var i = 0;
    var lines = [];

    if (map == -1)
        return 404;

    while (!file_text_eof(map))
    {
        array_push(lines, file_text_read_string(map));
        file_text_readln(map);
    }

    file_text_close(map);
    var notes = [];

    for (i = 0; i < array_length(lines); i++)
    {
        var parts = split_string(",", lines[i], false);
        if (array_length(parts) < 3)
            continue;
        var time = real(parts[0]);
        var type = real(parts[1]);
        var lane = real(parts[2]);
        var extra = {};
        if (array_length(parts) > 3)
        {
            if (type == 2)
            {
                variable_struct_set(extra, 1, real(parts[3]));
            }
            else if (type == 3)
            {
                extra = parse_custom_extra_value(parts[3]);
            }
            else
            {
                extra = parts[3];
            }
        }

        var noteData =
        {
            time: time,
            type: type,
            lane: lane,
            extra: extra
        };
        array_push(notes, noteData);
    }

    array_sort(notes, function(a, b)
    {
        return a.time - b.time;
    });
    return
    {
        notes: notes,
        mods: modDefinition
    };
}
