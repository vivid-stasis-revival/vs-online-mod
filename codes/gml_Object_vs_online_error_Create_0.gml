// Error dialog — Create. No vs_* names. vs_online_error_setup() runs after create.
depth = -10000;
title = "Cannot Connect to Server";
server_url = "";
message = "";
buttons = ["Retry", "Disable Custom Server"];
selected = 0;
on_retry = undefined;
retrying = false;
