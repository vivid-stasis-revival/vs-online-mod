// Custom-server connection error dialog — Create
// A recoverable modal shown when the custom server can't be reached. The
// player can Retry (re-probe) or disable the custom server and fall back to
// Steam. `on_retry` is set by vs_online_show_error() and re-runs the action
// that originally triggered the dialog.
depth = -10000;
title = "Cannot Connect to Server";
server_url = vs_online_server_url();
message = "The custom server could not be reached.\n\n" +
          "Address: " + server_url + "\n\n" +
          "Check that vs-server-go is running, then retry.\n" +
          "Or switch back to Steam.";
buttons = ["Retry", "Disable Custom Server"];
selected = 0;
on_retry = undefined;
retrying = false;
