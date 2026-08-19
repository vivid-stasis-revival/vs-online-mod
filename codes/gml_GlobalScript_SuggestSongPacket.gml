function SuggestSongPacket(arg0) : BasePacket(arg0, false, 3, 1) constructor
{
    static write = function(arg0)
    {
        var buffer = self.getBuffer();
        buffer_write(buffer, buffer_s8, arg0.difficulty);
        buffer_write(buffer, buffer_string, global.song_list[arg0.songId].chart_id);
        return buffer;
    };

    static read = function(arg0)
    {
        var obj = {};
        obj.difficulty = buffer_read(arg0, buffer_s8);
        obj.songId = get_song_id_from_chart(buffer_read(arg0, buffer_string));
        buffer_delete(arg0);
        return obj;
    };

    static receive = function(arg0, arg1)
    {
        if (vs_lobby_is_owner())
        {
            vs_lobby_log("suggest recv songId=" + string(arg0.songId)
                + " diff=" + string(arg0.difficulty)
                + " from=" + string(arg1)
                + " q=" + string(array_length(o_st_handle.suggestQueue) + 1));
            array_push(o_st_handle.suggestQueue,
            {
                member: arg1,
                songId: arg0.songId,
                difficulty: arg0.difficulty
            });
        }
        else
        {
            vs_lobby_log("suggest recv skip not-owner songId=" + string(arg0.songId)
                + " diff=" + string(arg0.difficulty)
                + " from=" + string(arg1));
        }
    };
}
