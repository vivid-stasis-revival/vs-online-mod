// Error dialog — Create. No vs_* names. Methods bound after create.
depth = -10000;
do_step = function() { };
title = "Cannot Connect to Server";
server_url = "";
message = "";
buttons = ["Retry", "Disable Custom Server"];
selected = 0;
on_retry = undefined;
retrying = false;
