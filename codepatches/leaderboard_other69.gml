// Custom servers fill leaderboard data over HTTP in downloadScores*.
// Steam async must not parse or paginate this panel.
if (vs_online_is_custom()) exit;
