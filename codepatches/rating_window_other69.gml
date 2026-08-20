// Custom servers fill dataTop100 / dataFriends over HTTP in Create.
// Steam async (id -1) must not parse or paginate this window.
if (vs_online_is_custom()) exit;
