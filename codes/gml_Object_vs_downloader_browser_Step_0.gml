// ============================================================================
// Chart Downloader — Step
// ============================================================================

// While the custom-server error dialog is up, don't take input.
if (instance_exists(vs_online_error)) exit;

started++;
if (started < 8) exit;   // debounce the keys that opened the overlay

// search input mode (Web tab) — Esc here exits search, not the overlay
if (searching)
{
    query = keyboard_string;
    if (keyboard_check_pressed(vk_enter))
    {
        searching = false;
        if (view == 1)
        {
            apply_local_filter();
            set_status((array_length(local_rows) > 0)
                ? ("Local search: " + string(array_length(local_rows)) + "/" + string(array_length(local_all)))
                : ("No local charts match \"" + query + "\"."));
        }
        else
        {
            page = 1;
            fetch_page();
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

// only Esc while a network op is running
if (loading || checking || updating) exit;

if (view == 0)
{
    var n = array_length(rows);

    if (n == 0)
    {
        if (keyboard_check_pressed(ord("R"))) reload_data();
        else if (keyboard_check_pressed(ord("V"))) toggle_view();
        else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
        exit;
    }

    if (keyboard_check_pressed(vk_up))
    {
        sel = (sel + n - 1) % n;
        selected_refresh();
    }
    else if (keyboard_check_pressed(vk_down))
    {
        sel = (sel + 1) % n;
        selected_refresh();
    }
    else if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_pageup))
    {
        if (page > 1) { page--; fetch_page(); }
    }
    else if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_pagedown))
    {
        if (page < maxpage) { page++; fetch_page(); }
    }
    else if (keyboard_check_pressed(vk_tab))
    {
        searching = true;
        keyboard_string = query;
    }
    else if (keyboard_check_pressed(ord("F")))
    {
        cycle_filter();
    }
    else if (keyboard_check_pressed(ord("K")))
    {
        check_all_rows();
    }
    else if (keyboard_check_pressed(ord("G")))
    {
        batch_update();
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        do_selected_action();
    }
    else if (keyboard_check_pressed(ord("V")))
    {
        toggle_view();
    }
    else if (keyboard_check_pressed(ord("R")))
    {
        reload_data();
    }
}
else // view == 1 (Local)
{
    var ln = array_length(local_rows);

    if (ln == 0)
    {
        if (keyboard_check_pressed(ord("R"))) reload_local();
        else if (keyboard_check_pressed(ord("V"))) toggle_view();
        else if (keyboard_check_pressed(vk_tab)) { searching = true; keyboard_string = query; }
        exit;
    }

    if (keyboard_check_pressed(vk_up))
    {
        sel = (sel + ln - 1) % ln;
        set_status(local_rows[sel].pack + "  " + local_rows[sel].name);
    }
    else if (keyboard_check_pressed(vk_down))
    {
        sel = (sel + 1) % ln;
        set_status(local_rows[sel].pack + "  " + local_rows[sel].name);
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        jump_from_local();
    }
    else if (keyboard_check_pressed(ord("V")))
    {
        toggle_view();
    }
    else if (keyboard_check_pressed(ord("R")))
    {
        reload_local();
    }
    else if (keyboard_check_pressed(vk_tab))
    {
        searching = true;
        keyboard_string = query;
    }
}
