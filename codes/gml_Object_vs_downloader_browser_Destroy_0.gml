// ============================================================================
// Chart Downloader — Destroy
// The home-menu button sets is_active = false when it opens this overlay (the
// menu's Step is gated on is_active); restore it when the overlay closes so
// the home menu is interactive again.
// ============================================================================
if (variable_instance_exists(id, "do_destroy") && do_destroy != undefined)
{
    do_destroy();
}
if (instance_exists(o_newmenu_main))
    o_newmenu_main.is_active = true;
