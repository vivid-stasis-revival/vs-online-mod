// Chart Downloader — Step
if (instance_exists(vs_online_error)) exit;

started++;
if (started < 8) exit;

if (searching)
{
    query = keyboard_string;
    if (keyboard_check_pressed(vk_enter))
    {
        searching = false;
        if (view == 1)
        {
            vs_dlbr_apply_local_filter();
            vs_dlbr_set_status((array_length(local_rows) > 0)
                ? ("Local search: " + string(array_length(local_rows)) + "/" + string(array_length(local_all)))
                : ("No local charts match \"" + query + "\"."));
        }
        else
        {
            page = 1;
            vs_dlbr_fetch_page();
        }
    }
    else if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_tab))
    {
        searching = false;
        keyboard_string = query;
    }
    exit;
}

if (keyboard_check_pressed(vk_escape))
{
    instance_destroy();
    exit;
}

if (loading || checking || updating) exit;

if (view == 0)
{
    var n = array_length(rows);

    if (n == 0)
    {
        if (keyboard_check_pressed(ord("R"))) vs_dlbr_reload_data();
        else if (keyboard_check_pressed(ord("V"))) vs_dlbr_toggle_view();
        else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
        exit;
    }

    if (keyboard_check_pressed(vk_up))
    {
        sel = (sel + n - 1) % n;
        vs_dlbr_selected_refresh();
    }
    else if (keyboard_check_pressed(vk_down))
    {
        sel = (sel + 1) % n;
        vs_dlbr_selected_refresh();
    }
    else if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_pageup))
    {
        if (page > 1) { page--; vs_dlbr_fetch_page(); }
    }
    else if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_pagedown))
    {
        if (page < maxpage) { page++; vs_dlbr_fetch_page(); }
    }
    else if (keyboard_check_pressed(vk_tab))
    {
        searching = true;
        keyboard_string = query;
    }
    else if (keyboard_check_pressed(ord("F")))
    {
        vs_dlbr_cycle_filter();
    }
    else if (keyboard_check_pressed(ord("K")))
    {
        vs_dlbr_check_all_rows();
    }
    else if (keyboard_check_pressed(ord("G")))
    {
        vs_dlbr_batch_update();
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        vs_dlbr_do_selected_action();
    }
    else if (keyboard_check_pressed(ord("V")))
    {
        vs_dlbr_toggle_view();
    }
    else if (keyboard_check_pressed(ord("R")))
    {
        vs_dlbr_reload_data();
    }
}
else
{
    var ln = array_length(local_rows);

    if (ln == 0)
    {
        if (keyboard_check_pressed(ord("R"))) vs_dlbr_reload_local();
        else if (keyboard_check_pressed(ord("V"))) vs_dlbr_toggle_view();
        else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
        exit;
    }

    if (keyboard_check_pressed(vk_up))
    {
        sel = (sel + ln - 1) % ln;
        vs_dlbr_set_status(local_rows[sel].pack + "  " + local_rows[sel].name);
    }
    else if (keyboard_check_pressed(vk_down))
    {
        sel = (sel + 1) % ln;
        vs_dlbr_set_status(local_rows[sel].pack + "  " + local_rows[sel].name);
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        vs_dlbr_jump_from_local();
    }
    else if (keyboard_check_pressed(ord("V")))
    {
        vs_dlbr_toggle_view();
    }
    else if (keyboard_check_pressed(ord("R")))
    {
        vs_dlbr_reload_local();
    }
    else if (keyboard_check_pressed(vk_tab))
    {
        searching = true;
        keyboard_string = query;
    }
}
