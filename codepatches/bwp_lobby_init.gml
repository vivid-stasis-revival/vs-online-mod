joining = 0;
lobbyCount = 0;
randomJoinOffset = 0;
opsMode = "";
opsCursor = 0;
if (vs_online_is_custom())
{
    vs_lobby_log("ui lobby init");
    array_insert(menu_actions_host, 2, {
        txt: "Kick",
        callback: "kick"
    });
    vs_lobby_refresh_count();
    if (vs_lobby_has_code())
    {
        vs_lobby_log("ui lobby return members=" + string(array_length(o_st_handle.lobbyMembers)));
        if (vs_lobby_is_owner()) vs_lobby_host_sync("lobby room");
    }
}
else
{
    steam_lobby_list_request();
}
