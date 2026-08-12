if (vs_online_is_custom()) { vs_online_send_packet(arg0, buffer); } else { steam_lobby_send_chat_message_buffer(buffer, buffer_get_size(buffer)); }
