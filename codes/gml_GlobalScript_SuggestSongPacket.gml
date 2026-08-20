function SuggestSongPacket(arg0) : BasePacket(arg0, false, 3, 1) constructor
{
    static write = function(arg0)
    {
        var buffer = self.getBuffer();
        buffer_write(buffer, buffer_s8, arg0.difficulty);
        buffer_write(buffer, buffer_string, vs_online_queue_chart_id(arg0));
        return buffer;
    };

    static read = function(arg0)
    {
        var obj = {};
        obj.difficulty = buffer_read(arg0, buffer_s8);
        obj.chart_id = buffer_read(arg0, buffer_string);
        obj.songId = vs_online_song_id_from_chart(obj.chart_id);
        buffer_delete(arg0);
        return obj;
    };

    static receive = function(arg0, arg1)
    {
        if (vs_lobby_is_owner()) vs_lobby_suggest_push(arg0, arg1);
    };
}
