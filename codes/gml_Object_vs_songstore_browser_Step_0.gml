// Web Charts browser — Step
if (loading)
{
    exit;
}

if (searching)
{
    query = keyboard_string;
    if (keyboard_check_pressed(vk_enter))
    {
        fetch_web_page();
    }
    else if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_tab))
    {
        searching = false;
        keyboard_string = query;
    }
    exit;
}

if (keyboard_check_pressed(vk_up))
{
    selected = max(selected - 1, 0);
    selected_refresh();
}
else if (keyboard_check_pressed(vk_down))
{
    selected = min(selected + 1, array_length(songs) - 1);
    selected_refresh();
}
else if (keyboard_check_pressed(vk_left) && page > 1)
{
    page--;
    fetch_web_page();
}
else if (keyboard_check_pressed(vk_right) && page < maxpage)
{
    page++;
    fetch_web_page();
}
else if (keyboard_check_pressed(vk_tab))
{
    searching = true;
    keyboard_string = query;
}
else if (keyboard_check_pressed(vk_enter) && array_length(songs) > 0)
{
    start_download();
}
else if (keyboard_check_pressed(vk_escape))
{
    exit_browser();
}
