joining = 0;
lobbyCount = 0;
randomJoinOffset = 0;
if (vs_online_is_custom()) { vs_lobby_log("ui lobby init"); vs_lobby_refresh_count(); } else { steam_lobby_list_request(); }
