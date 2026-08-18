// Custom-server connection error dialog — Step
if (retrying)
{
    exit;
}

if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_tab))
{
    selected = (selected + 1) % array_length(buttons);
    play_se(sfx_songsel_cursor);
}
else if (keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_right))
{
    selected = (selected + array_length(buttons) - 1) % array_length(buttons);
    play_se(sfx_songsel_cursor);
}
else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
{
    play_se(sfx_songsel_select);
    if (selected == 0)
    {
        // Retry: re-probe, then resume the pending action on success.
        retrying = true;
        message = "Retrying...";
        // The callback uses `self` directly (bound to this dialog) instead of
        // a captured `var` local, which injected scripts can't capture.
        vs_online_probe(function(_ok)
        {
            if (!instance_exists(self)) { return; }
            if (_ok)
            {
                instance_destroy();
                if (is_method(self.on_retry)) { self.on_retry(); }
            }
            else
            {
                self.retrying = false;
                self.message = "Still unreachable. Is vs-server-go running?";
            }
        });
    }
    else
    {
        // Disable Custom Server: fall back to Steam.
        vs_online_disable_custom();
        instance_destroy();
    }
}
else if (keyboard_check_pressed(vk_escape))
{
    instance_destroy();
}
