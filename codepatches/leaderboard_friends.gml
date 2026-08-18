downloadScoresFriends = function()
{
    data = [];
    if (vs_online_is_custom())
    {
        vs_online_lb_download(id, true);
        canExtend = false;
        return;
    }
    lbId = steam_download_friends_scores(name);
    canExtend = false;
};
