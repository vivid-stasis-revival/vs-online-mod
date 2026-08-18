function parseSongDataFromText(arg0, arg1, arg2 = false, arg3 = false, arg4)
{
    //WriteInLogFree(arg0 + "," + arg4);
    var chartPath = get_chart_path_from_chart(arg0);
    var chart = load_text_chart(chartPath, arg4);
    var songEntry = getSongEntry(arg1);
    var songLength = audio_sound_length(songEntry.audio_id);
    
    if (arg3)
        songLength = audio_sound_length(song_get_info(songEntry, "audio_id", 3));
    
    debug(songLength);
    var data = new SongData();
    var hitcount = array_length(chart.notes) - 1;
    var bpmChanges = [];
    
    for (var i = 0; i <= hitcount; i++)
    {
        var note = chart.notes[i];
        
        if (note.type == 3)
        {
            var newBpm = variable_struct_get(note.extra, UnknownEnum.Value_1);
            
            if (newBpm != undefined)
                array_push(bpmChanges, [note.time, newBpm]);
        }
    }
    
    var averageBpm = songEntry.bpm_display;
    
    if (averageBpm == "")
        averageBpm = 120;
    
    if (!is_real(averageBpm))
        averageBpm = real(averageBpm ?? "120");
    
    data.SetBucketLength(averageBpm, songLength);
    data.hasMods = chart.mods != undefined;
    
    for (var j = 0; j <= hitcount; j++)
    {
        var note = chart.notes[j];
        var notems = note.time;
        var noteType = note.type;
        var noteLane = note.lane;
        var noteExtra = note.extra;
        
        switch (noteType)
        {
            case UnknownEnum.Value_0:
            case UnknownEnum.Value_6:
                data.AddNote(noteLane, notems);
                break;
            
            case UnknownEnum.Value_1:
            case UnknownEnum.Value_7:
            case UnknownEnum.Value_8:
                data.AddBumper(noteLane, notems);
                break;
            
            case UnknownEnum.Value_2:
                var holdendms = variable_struct_get(noteExtra, UnknownEnum.Value_1);
                data.AddHoldNote(noteLane, notems, holdendms);
                break;
            
            case UnknownEnum.Value_3:
                var newBpm = variable_struct_get(noteExtra, UnknownEnum.Value_1);
                
                if (newBpm != undefined)
                    data.SetBPM(newBpm);
                
                break;
        }
    }
    
    if (data.hasMods)
    {
        //WriteInLogFree("[PCSD] have mod");
        data.mods = chart.mods;
    }
    
    data.CalculateJacks(data.allNotesNoHold);
    data.CalculateChains(data.allNotesNoHold);
    data.FinishDensityCalculation();
    return data;
}

enum UnknownEnum
{
    Value_0,
    Value_1,
    Value_2,
    Value_3,
    Value_6 = 6,
    Value_7,
    Value_8
}
