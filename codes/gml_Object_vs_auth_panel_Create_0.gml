// Auth panel — Create. No vs_* names (old vsml compiles those as instance vars).
depth = -10000;
do_step = function() { };
do_draw = function() { };
cfg = undefined;
signed_in = false;
stage = 0;
device_code = "";
user_code = "";
verification_uri = "";
verification_uri_complete = "";
expires_at = 0;
poll_at = 0;
interval = 5;
message = "";
busy = false;
sel = 0;
conn_log = "";
