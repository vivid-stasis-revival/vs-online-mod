// Chart Downloader — Create
// Object events must not name any vs_* script (Underanalyzer → instance var).
// Fetch starts from vs_dlbr_open_from_menu after this instance exists.
depth = -10000;

view = 0;
page = 1;
maxpage = 1;
total = 0;
query = "";
searching = false;
filter = 0;

rows_all = [];
rows = [];
local_all = [];
local_rows = [];

sel = 0;
started = 0;

loading = false;
checking = false;
updating = false;
check_all = false;
check_idx = 0;
update_queue = [];
update_qidx = 0;

check_chart = "";
batch_name = "";
cur_id = "";
cur_chart = "";

status = "Chart Downloader - loading...";
