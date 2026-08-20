// Backup if initiategame prepend did not halt (should be unreachable
// when a conflicting mod is present: CreateSongDictionary would already
// have crashed). Fingerprints, not vml_mods — see vs_online_conflict_why.
if (vs_online_conflict_halt()) exit;
