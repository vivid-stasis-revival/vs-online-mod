function GetRuntime(){
    if (!variable_global_exists("runtime"))
        global.runtime=get_timer();
    return global.runtime;
}

function WriteInLogFree(content){
    var runtime=GetRuntime();
    var logFile=file_text_open_append(string("{0}-{1}-{2}_{3}.log",current_year,current_month,current_day,runtime));
    file_text_write_string(logFile,content+"\n");
    file_text_close(logFile);
}

function WriteInLogWithTag(tag,content){
    var runtime=GetRuntime();
    var logFile=file_text_open_append(string("{0}-{1}-{2}_{3}.log",current_year,current_month,current_day,runtime));
    var text=string("[{0}] {1}\n",tag,content);
    file_text_write_string(logFile,text);
    file_text_close(logFile);
}

function WriteInLogWithTime(content){
    var runtime=GetRuntime();
    var logFile=file_text_open_append(string("{0}-{1}-{2}_{3}.log",current_year,current_month,current_day,runtime));
    var text=string("[{0}:{1}:{2}] {3}\n",current_hour,current_minute,current_second,content);
    file_text_write_string(logFile,text);
    file_text_close(logFile);
}

function WriteInLogWithTimeAndTag(tag,content){
    var runtime=GetRuntime();
    var logFile=file_text_open_append(string("{0}-{1}-{2}_{3}.log",current_year,current_month,current_day,runtime));
    var text=string("[{0}:{1}:{2}][{3}] {4}\n",current_hour,current_minute,current_second,tag,content);
    file_text_write_string(logFile,text);
    file_text_close(logFile);
}

function structcpy(cpySrc,cpyDest){
    var kys=struct_get_names(cpySrc);
    for (var i=0; i<array_length(kys); i++){
        var _name=kys[i];
        struct_set(cpyDest,_name,struct_get(cpySrc,_name));
    }
}

