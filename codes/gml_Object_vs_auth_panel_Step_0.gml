// VS Online account panel — Step
// Device flow: poll /oauth2/token every `interval` seconds while waiting for
// the player to approve the user_code in a browser. Esc closes; Enter restarts
// the flow after a terminal failure. Signed-in view: [Sign Out] [Close].

if (signed_in)
{
    var btn_count = 2;
    if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_left))
    {
        sel = (sel + btn_count - 1) % btn_count;
        play_se(sfx_songsel_cursor);
    }
    else if (keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_right))
    {
        sel = (sel + 1) % btn_count;
        play_se(sfx_songsel_cursor);
    }
    else if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space))
    {
        play_se(sfx_songsel_select);
        if (sel == 0)
        {
            do_signout();
        }
        else
        {
            instance_destroy();
        }
    }
    else if (keyboard_check_pressed(vk_escape))
    {
        instance_destroy();
    }
    exit;
}

// --- device-flow view ---
if (busy)
{
    exit; // ignore input while a request is in flight
}

// periodic polling while waiting for approval
if (stage == 1 && current_time >= poll_at)
{
    // user_code expired?
    if (current_time / 1000 > expires_at)
    {
        stage = 0;
        message = "Code expired - press Enter to restart.";
    }
    else
    {
        busy = true;
        vs_online_oauth_poll(device_code, method(self, function(_ok, _data, _status)
        {
            busy = false;
            flow_polled(_ok, _data, _status);
        }));
    }
    exit;
}

if (keyboard_check_pressed(vk_escape))
{
    instance_destroy();
}
else if (keyboard_check_pressed(vk_enter) && stage == 0)
{
    start_flow();
}
