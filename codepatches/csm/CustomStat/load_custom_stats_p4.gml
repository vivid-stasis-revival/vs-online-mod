if (!is_custom_chart)
        {
            data = parseSongDataFromBinary(binName, arg0, arg3, arg1 == "ENCORE");
        }
        else
        {
            data = parseSongDataFromText(arg0, arg0, arg3, arg1 == "ENCORE", arg1);
            if (data.hasMods){
            var f=file_text_open_write(baseCustomName+".vmv");
            file_text_write_string(f,"[mods]\n")
            file_text_write_string(f,string("weight=\"{0}\"\n",CalcGimmickWeight(data.mods)));
            file_text_write_string(f,string("total=\"{0}\"\n",array_length(data.mods.mods)));
            file_text_write_string(f,string("list=\"{0}\"",data.mods.mods));
            file_text_close(f)
            }
        }