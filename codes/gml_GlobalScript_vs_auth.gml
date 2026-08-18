// ============================================================================
// vs_auth.gml — vs_auth_panel actions as named scripts.
// ============================================================================

function vs_auth_flow_started(_ok, _data)
{
    busy = false;
    if (_ok && _data != undefined)
    {
        stage = 1;
        device_code = _data.device_code;
        user_code = _data.user_code;
        verification_uri = vs_online_device_page_url("");
        expires_at = current_time / 1000 + (variable_struct_exists(_data, "expires_in") ? _data.expires_in : 600);
        interval = variable_struct_exists(_data, "interval") ? max(_data.interval, 5) : 5;
        poll_at = current_time + interval * 1000;
        message = "Waiting for approval...";
        play_se(sfx_songsel_select);
        vs_auth_open_device_page();
    }
    else
    {
        stage = 0;
        message = "Could not start device flow. Is the server reachable?";
    }
}

function vs_auth_on_me(_ok2, _data2)
{
    play_se(sfx_songsel_select);
    instance_destroy();
}

function vs_auth_flow_polled(_ok, _data, _status)
{
    if (_ok && _data != undefined && variable_struct_exists(_data, "access_token"))
    {
        stage = 2;
        message = "Signed in!";
        vs_online_apply_oauth_tokens(_data);
        vs_online_refresh_me(method(self, vs_auth_on_me));
        return;
    }
    var err = "";
    if (_data != undefined && variable_struct_exists(_data, "error"))
    {
        err = string(_data.error);
    }
    if (err == "authorization_pending")
    {
        poll_at = current_time + interval * 1000;
        message = "Waiting for approval...";
        return;
    }
    if (err == "slow_down")
    {
        interval += 5;
        poll_at = current_time + interval * 1000;
        message = "Slow down - retrying...";
        return;
    }
    stage = 0;
    message = "Device flow failed (" + err + ") - press Enter to restart.";
}

function vs_auth_on_poll(_ok, _data, _status)
{
    busy = false;
    vs_auth_flow_polled(_ok, _data, _status);
}

function vs_auth_close()
{
    if (variable_global_exists("vs_oauth_start_q"))
    {
        global.vs_oauth_start_q = [];
    }
    instance_destroy();
}

function vs_auth_pressed_close()
{
    if (keyboard_check_pressed(vk_escape)) return true;
    if (variable_global_exists("menu_cancel") && keyboard_check_pressed(global.menu_cancel)) return true;
    return false;
}

function vs_auth_open_device_page()
{
    var page = vs_online_device_page_url(user_code);
    verification_uri = vs_online_device_page_url("");
    if (page != "")
    {
        url_open(page);
        message = "Opened device page - enter the code if asked.";
    }
}

function vs_auth_start_flow()
{
    if (busy) return;
    busy = true;
    stage = 1;
    message = "Requesting device code...";
    vs_online_oauth_start(method(self, vs_auth_flow_started));
}

function vs_auth_after_signout(_ok2, _data2)
{
    instance_destroy();
}

function vs_auth_auth_done(_ok, _data)
{
    busy = false;
    if (_ok)
    {
        play_se(sfx_songsel_select);
        instance_destroy();
    }
    else
    {
        message = "Sign-out failed (server unreachable?) - local session cleared anyway.";
        vs_online_drop_identity();
        vs_online_ensure_identity(method(self, vs_auth_after_signout));
    }
}

function vs_auth_do_signout()
{
    if (busy) return;
    busy = true;
    message = "Signing out...";
    vs_online_auth_logout(method(self, vs_auth_auth_done));
}

function vs_auth_setup()
{
    cfg = vs_online_get_config();
    signed_in = (variable_struct_exists(cfg, "refresh_token") && cfg.refresh_token != "")
             || (variable_struct_exists(cfg, "email") && cfg.email != "");
    stage = 0;
    device_code = "";
    user_code = "";
    verification_uri = "";
    expires_at = 0;
    poll_at = 0;
    interval = 5;
    message = "";
    busy = false;
    sel = 0;
    if (!signed_in)
    {
        vs_auth_start_flow();
    }
}

function vs_auth_step()
{
    if (vs_auth_pressed_close())
    {
        vs_auth_close();
        return;
    }

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
                vs_auth_do_signout();
            }
            else
            {
                vs_auth_close();
            }
        }
        return;
    }

    if (!signed_in && user_code != "" && (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space)))
    {
        vs_auth_open_device_page();
    }

    if (busy)
    {
        return;
    }

    if (stage == 1 && current_time >= poll_at)
    {
        if (current_time / 1000 > expires_at)
        {
            stage = 0;
            message = "Code expired - press Enter to restart.";
        }
        else
        {
            busy = true;
            vs_online_oauth_poll(device_code, method(self, vs_auth_on_poll));
        }
        return;
    }

    if (keyboard_check_pressed(vk_enter) && stage == 0)
    {
        vs_auth_start_flow();
    }
}

function vs_auth_draw()
{
    var cw = display_get_gui_width();
    var ch = display_get_gui_height();
    var bw = 280;
    var bh = signed_in ? 120 : 150;
    var bx = (cw - bw) / 2;
    var by = (ch - bh) / 2;

    draw_set_alpha(0.7);
    draw_set_color(c_black);
    draw_rectangle(0, 0, cw, ch, false);
    draw_set_alpha(1);

    draw_set_color(c_black);
    draw_rectangle(bx - 2, by - 2, bx + bw + 2, by + bh + 2, false);
    draw_set_color(c_white);
    draw_rectangle(bx, by, bx + bw, by + bh, true);

    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_center);
    draw_set_valign(fa_top);
    draw_set_color(c_aqua);
    draw_text(bx + bw / 2, by + 5, "VS Online Account");

    draw_set_font(global.default_font);

    if (signed_in)
    {
        var acfg = vs_online_get_config();
        var nm = (variable_struct_exists(acfg, "name") && acfg.name != "") ? acfg.name : "Player";
        var em = (variable_struct_exists(acfg, "email") && acfg.email != "") ? acfg.email : "device flow";
        var pid = (variable_struct_exists(acfg, "playerId") && acfg.playerId != "") ? acfg.playerId : "";
        if (string_length(pid) > 12) { pid = string_copy(pid, 1, 12) + "..."; }

        draw_set_halign(fa_left);
        draw_set_color(c_white);
        draw_text(bx + 12, by + 24, "Name: " + nm);
        draw_text(bx + 12, by + 38, "Account: " + em);
        draw_text(bx + 12, by + 52, "Player ID: " + pid);

        var btn_w = 126;
        var btn_h = 18;
        var yb = by + bh - btn_h - 8;
        var i = 0;
        repeat (2)
        {
            var xb = bx + 8 + i * (btn_w + 8);
            var isSel = (i == sel);
            if (isSel)
            {
                draw_set_color(c_yellow);
                draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, false);
                draw_set_color(c_black);
            }
            else
            {
                draw_set_color(make_color_rgb(48, 48, 48));
                draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, false);
                draw_set_color(c_gray);
                draw_rectangle(xb, yb, xb + btn_w, yb + btn_h, true);
                draw_set_color(c_white);
            }
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text(xb + btn_w / 2, yb + btn_h / 2, i == 0 ? "Sign Out" : "Close");
            i++;
        }

        if (message != "")
        {
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            draw_set_color(c_yellow);
            draw_text(bx + 12, by + 70, message);
        }
    }
    else
    {
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        draw_set_color(c_white);

        if (stage == 1 || busy)
        {
            var remain = max(0, expires_at - current_time / 1000);
            draw_set_font(fnt_monacovs);
            draw_set_color(c_yellow);
            draw_set_halign(fa_center);
            draw_text(bx + bw / 2, by + 26, user_code == "" ? "..." : user_code);
            draw_set_font(global.default_font);
            draw_set_halign(fa_left);

            draw_set_color(c_white);
            draw_text_ext(bx + 12, by + 44, "Enter opens the device page. Sign in and enter the code:", 10, bw - 24);
            draw_set_color(c_lime);
            draw_text_ext(bx + 12, by + 66, verification_uri, 10, bw - 24);
            draw_set_color(c_gray);
            draw_text(bx + 12, by + 92, "Code expires in " + string(ceil(remain)) + "s");
            draw_set_color(c_yellow);
            draw_text(bx + 12, by + 106, message);
            draw_set_color(c_gray);
            draw_text(bx + 12, by + 118, "Enter: open page   Esc: close");
        }
        else
        {
            draw_set_color(c_white);
            draw_text_ext(bx + 12, by + 26, "Sign in with your account via device flow.", 10, bw - 24);
            draw_set_color(c_yellow);
            draw_text_ext(bx + 12, by + 44, message, 10, bw - 24);
            draw_set_color(c_gray);
            draw_text_ext(bx + 12, by + 88, "Enter: start   Esc: close", 10, bw - 24);
        }
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
