var _sq = vs_lobby_suggest_q();
if (array_length(_sq) > 0)
{
    if (input_check_pressed(4))
    {
        play_se(sfx_songsel_beginsong);
        send_packet(AddSongPacket, _sq[0]);
        array_delete(_sq, 0, 1);
    }

    if (input_check_pressed(5))
    {
        play_se(sfx_songsel_select);
        array_delete(_sq, 0, 1);
    }
}
else if (!stickersActive)
