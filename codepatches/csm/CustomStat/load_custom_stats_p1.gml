var weight=0;
    var vmvFile=vs_csm_stat_dir(arg0) + arg1 + ".vmv"
    if (!file_exists(vmvFile))
        vmvFile = vs_csm_load_dir_from_id(arg0) + arg1 + ".vmv";
    if (file_exists(vmvFile))
    {
        ini_open(vmvFile);
        weight = ini_read_real("mods", "weight", 0);
        ini_close();
    }
