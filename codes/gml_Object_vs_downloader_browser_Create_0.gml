// Chart Downloader — Create. No vs_* names (old vsml compiles those as instance vars).
depth = -10000;
do_step = function() { };
do_draw = function() { };

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
enter_act = false;
