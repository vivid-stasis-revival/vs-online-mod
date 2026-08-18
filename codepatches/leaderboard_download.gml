downloadScores = function()
{
    data = [];
    if (vs_online_is_custom())
    {
        vs_online_lb_download(id, false);
        canExtend = false;
        return;
    }
    lbId = steam_download_scores(name, 1, maxScores);
    canExtend = true;
};
