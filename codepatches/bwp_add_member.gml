addMember = function(arg0)
{
    var name = steam_get_user_persona_name_sync(arg0);
    member =
    {
        id: arg0,
        name: name,
        ready: 0,
        avatar: getAvatarData(arg0),
        reportedScore: true,
        host: arg0 == steam_lobby_get_owner_id(),
        npc: false,
        rate: 0,
        class: 0,
        has_bwp: false,
        sticker_scale: 0,
        sticker_alpha: 0,
        sticker_id: 0,
        sticker_timer: 0,
        is_winner: false,
        order: array_length(lobbyMembers),

        remove_sticker: function()
        {
            TweenFire(o_st_handle.getMember(userId), EaseOutBack, 0, true, 0, 0.5, "sticker_scale", 0, 1);
            TweenFire(o_st_handle.getMember(userId), EaseOutExpo, 0, true, 0, 0.5, "sticker_alpha", 0, 1);
        }
    };
    vs_member_set_score(member, 0);
    vs_member_set_flag(member, UnknownEnum.Value_1);
    array_push(lobbyMembers, member);
};
addMember_deprecated = function(arg0)
