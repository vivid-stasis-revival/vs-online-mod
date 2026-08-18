    var load_score = function(arg0, arg1, arg2 = false)
    {
        if (arg2)
            ini_open(working_directory + "custom_highscore");
        else
            ini_open(global.highscore_file);

        var retval = {};
        variable_struct_set(retval, "score", ini_read_real(arg0, arg1, 0));
        variable_struct_set(retval, "game_score", ini_read_real(arg0, string("{0}_GAME", arg1), 0));
        variable_struct_set(retval, "max_combo", ini_read_real(arg0, string("{0}_MAXCOMBO", arg1), 0));
        variable_struct_set(retval, "lamp", ini_read_real(arg0, string("{0}_COMBO", arg1), UnknownEnum.Value_0));
        variable_struct_set(retval, "game_perc", ini_read_real(arg0, string("{0}_GAMEPERC", arg1), 0));
        ini_close();
        return retval;
    };
