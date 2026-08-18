function load_text_mods(arg0)
{
    var ds_mods = [];
    var ds_mpf = [];
    var modsDefinition = 
    {
        data: 
        {
            proxies: 0,
            obj: "obj_base_gimmick"
        },
        mods: ds_mods,
        perFrame: ds_mpf,
        count_no_loop: 0,
        count_loop: 0
    };
    var fileName = arg0;
    
    if (!file_exists(fileName))
        return undefined;
    
    file = file_text_open_read(fileName);
    var mode = "mods";
    
    while (!file_text_eof(file))
    {
        var line = file_text_readln(file);
        line = string_trim(line);
        
        if (line == "")
            continue;

        if (line == "mpf")
        {
            mode = "mpf";
            continue;
        }
        
        if (string_starts_with(line, "!"))
        {
            var parts = string_split(string_copy(line, 2, string_length(line) - 1), ":");
            var key = string_trim(parts[0]);
            var value = string_trim(parts[1]);
            variable_struct_set(modsDefinition.data, key, value);
            continue;
        }
        
        if (mode == "mods")
        {
            var parts = string_split(line, ",");
            var dur = parts[1];
            var ease = parts[2];
            var from = parts[3];
            var to = parts[4];
            var modName = parts[5];
            var proxy = parts[6];
            modsDefinition.count_no_loop++;
            var beatParts = string_split(parts[0], ":");
            var beatStart = real(beatParts[0]);
            var beatEnd = beatStart;
            var beatInc = 1;
            
            if (array_length(beatParts) > 1)
                beatEnd = real(beatParts[1]);
            
            if (array_length(beatParts) > 2)
                beatInc = real(beatParts[2]);
            
            if (from == "_")
                from = "573613";
            
            if (to == "_")
                to = "573613";
            
            for (var i = beatStart; i <= beatEnd; i += beatInc)
            {
                modsDefinition.count_loop++;
                var ms = 
                {
                    b: i,
                    d: real(dur),
                    v1: real(from),
                    v2: real(to),
                    m: modName,
                    p: real(proxy)
                };
                ms.w = struct_get(global.mod_weight, ms.m);
                ms.e = struct_get(global.eases, ease);
                ms.ig = struct_exists(global.mods, ms.m)
                array_push(modsDefinition.mods, ms);
            }
        }
        else if (mode == "mpf" && instance_exists(cc))
        {
            var obj_ins = getModGimmickObj(modsDefinition.data.obj);
            var parts = string_split(line, ",");
            var m = 
            {
                b: real(parts[0]),
                e: real(parts[1])
            };
            m.f = variable_struct_get(obj_ins.obj.funcs, parts[2]);
            array_push(modsDefinition.perFrame, m);
        }
    }
    
    file_text_close(file);
    return modsDefinition;
}
