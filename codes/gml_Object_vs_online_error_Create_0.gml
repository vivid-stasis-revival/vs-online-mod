// Error dialog — Create. No vs_* names (old vsml compiles those as instance vars).
depth = -10000;
do_step = function() { };
do_draw = function() { };
kind = "connect";
title = "Cannot Connect to Server";
server_url = "";
message = "";
buttons = ["Retry", "Disable Custom Server"];
selected = 0;
on_retry = undefined;
retrying = false;
