// Web Charts browser — Create
// Paginated server-song catalog with search + per-song download.
page = 1;
maxpage = 1;
query = "";
searching = false;
songs = [];
total = 0;
selected = 0;
loading = true;
failed = false;
downloading = false;
selected_dl = false;
selected_update = false;

self.fetch_web_page = function()
{
    loading = true;
    failed = false;
    vs_songstore_list(query, page, method(self, function(_ok, _data)
    {
        loading = false;
        if (_ok && _data != undefined)
        {
            songs = _data.songs;
            total = _data.total;
            maxpage = max(1, ceil(total / 50));
        }
        else
        {
            songs = [];
            total = 0;
            failed = true;
        }
        if (selected >= array_length(songs)) { selected = array_length(songs) - 1; }
        if (selected < 0) { selected = 0; }
        selected_refresh();
    }));
};

self.selected_refresh = function()
{
    selected_dl = false;
    selected_update = false;
    if (array_length(songs) == 0) return;
    var s = songs[selected];
    selected_dl = vs_songstore_downloaded(s.chartId);
    if (selected_dl)
    {
        vs_songstore_detail(s.id, method(self, function(_ok, _song)
        {
            if (_ok && _song != undefined && array_length(vs_songstore_diff(_song.files, s.chartId)) > 0)
            {
                selected_update = true;
            }
        }));
    }
};

self.start_download = function()
{
    if (downloading || array_length(songs) == 0) return;
    var s = songs[selected];
    downloading = true;
    vs_songstore_download(s.id, s.chartId, method(self, function(_ok)
    {
        downloading = false;
        selected_dl = _ok;
        selected_update = false;
    }));
};

self.exit_browser = function()
{
    global.selected_pack = vs_songstore_allsongs_index();
    instance_destroy();
    if (instance_exists(o_songselect_main))
    {
        with (o_songselect_main) { refresh_song_objects(0); }
    }
};

fetch_web_page();
