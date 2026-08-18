if (array_length(o_st_handle.suggestQueue) > 0)
{
    if (input_check_pressed(4))
    {
        play_se(sfx_songsel_beginsong);
        send_packet(AddSongPacket, o_st_handle.suggestQueue[0]);
        array_delete(o_st_handle.suggestQueue, 0, 1);
    }

    if (input_check_pressed(5))
    {
        play_se(sfx_songsel_select);
        array_delete(o_st_handle.suggestQueue, 0, 1);
    }
}
else if (!stickersActive)
