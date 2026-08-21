// Custom-server matchmaking landing (replaces Host Lobby buttons when
// Legacy Worldcross Lobby is off). In-room UI is unchanged.

function vs_lobby_legacy_enabled()
{
    if (variable_global_exists("op_vs_legacy_lobby"))
        return global.op_vs_legacy_lobby == 1;
    // Options screen may not have run yet - read the saved preference.
    return vs_online_opt_read_legacy_lobby() == 1;
}

function vs_lobby_browser_active()
{
    return vs_online_is_custom() && !vs_lobby_legacy_enabled();
}

function vs_lobby_browser_st()
{
    if (!variable_global_exists("vs_lobby_br") || !is_struct(global.vs_lobby_br))
    {
        global.vs_lobby_br = {
            loading: false,
            inflight: 0,
            raw: [],
            filter: 0,
            page: 0,
            focus: 0,
            top_i: 0,
            list_i: 0,
            page_size: 5
        };
    }
    var st = global.vs_lobby_br;
    if (!variable_struct_exists(st, "raw") || !is_array(st.raw)) st.raw = [];
    if (!variable_struct_exists(st, "filter")) st.filter = 0;
    if (!variable_struct_exists(st, "page")) st.page = 0;
    if (!variable_struct_exists(st, "focus")) st.focus = 0;
    if (!variable_struct_exists(st, "top_i")) st.top_i = 0;
    if (!variable_struct_exists(st, "list_i")) st.list_i = 0;
    if (!variable_struct_exists(st, "page_size")) st.page_size = 5;
    if (!variable_struct_exists(st, "loading")) st.loading = false;
    if (!variable_struct_exists(st, "inflight")) st.inflight = 0;
    return st;
}

function vs_lobby_browser_boot()
{
    if (!vs_lobby_browser_active()) return;
    var st = vs_lobby_browser_st();
    st.focus = 0;
    st.top_i = 0;
    st.list_i = 0;
    st.page = 0;
    vs_lobby_browser_refresh(true);
}

function vs_lobby_browser_labels()
{
    return ["Quick", "Host", "Join", "Refresh"];
}

function vs_lobby_browser_filter_name(_f)
{
    if (_f == 1) return "Joinable";
    if (_f == 2) return "Unjoinable";
    return "Default";
}

function vs_lobby_browser_row_joinable(_row)
{
    if (_row == undefined || !is_struct(_row)) return false;
    var started = variable_struct_exists(_row, "started") && _row.started;
    var cur = variable_struct_exists(_row, "memberCount") ? floor(_row.memberCount) : 0;
    var mx = variable_struct_exists(_row, "maxMembers") ? floor(_row.maxMembers) : 0;
    if (mx <= 0) mx = 8;
    return (!started) && (cur < mx);
}

function vs_lobby_browser_filtered()
{
    var st = vs_lobby_browser_st();
    var out = [];
    var i = 0;
    repeat (array_length(st.raw))
    {
        var row = st.raw[i];
        var ok = vs_lobby_browser_row_joinable(row);
        if (st.filter == 1)
        {
            if (ok) array_push(out, row);
        }
        else if (st.filter == 2)
        {
            if (!ok) array_push(out, row);
        }
        else array_push(out, row);
        i++;
    }
    return out;
}

function vs_lobby_browser_page_count(_n)
{
    var st = vs_lobby_browser_st();
    var ps = max(1, st.page_size);
    return max(1, ceil(_n / ps));
}

function vs_lobby_browser_clamp()
{
    var st = vs_lobby_browser_st();
    var rows = vs_lobby_browser_filtered();
    var n = array_length(rows);
    var pages = vs_lobby_browser_page_count(n);
    if (st.page < 0) st.page = 0;
    if (st.page >= pages) st.page = pages - 1;
    var ps = st.page_size;
    var start = st.page * ps;
    var on_page = clamp(n - start, 0, ps);
    if (on_page <= 0)
    {
        st.list_i = 0;
        if (st.focus == 1) st.focus = 0;
    }
    else if (st.list_i >= on_page)
    {
        st.list_i = on_page - 1;
    }
    if (st.list_i < 0) st.list_i = 0;
    var labels = vs_lobby_browser_labels();
    if (st.top_i < 0) st.top_i = 0;
    if (st.top_i >= array_length(labels)) st.top_i = array_length(labels) - 1;
}

function vs_lobby_browser_refresh_left()
{
    var st = vs_lobby_count_st();
    if (!variable_struct_exists(st, "next_at") || st.next_at <= 0) return 0;
    return max(0, ceil((st.next_at - current_time) / 1000));
}

function vs_lobby_browser_refresh(_spin)
{
    if (!vs_lobby_browser_active()) return;
    if (!instance_exists(obj_multiplayer_lobby)) return;
    if (vs_lobby_lobby_id() > 0) return;
    var st = vs_lobby_browser_st();
    var spin = (_spin == true) || (array_length(st.raw) == 0);
    if (spin) st.loading = true;
    // Named HTTP callback — injected anons cannot capture enclosing locals.
    st.inflight += 1;
    vs_online_get_json("/api/v1/lobbies", false, vs_lobby_browser_list_done);
}

function vs_lobby_browser_list_done(_ok, _data, _status)
{
    var st = vs_lobby_browser_st();
    st.inflight = max(0, st.inflight - 1);
    // Drop late responses after leaving the landing (entered a room / closed UI).
    if (!instance_exists(obj_multiplayer_lobby) || vs_lobby_lobby_id() > 0 || !vs_lobby_browser_active())
    {
        st.loading = st.inflight > 0;
        return;
    }
    var rows = [];
    if (_ok && _data != undefined && variable_struct_exists(_data, "lobbies") && is_array(_data.lobbies))
        rows = _data.lobbies;
    // HTTP is serialized; each response is applied. Last response wins.
    st.raw = rows;
    st.loading = st.inflight > 0;
    obj_multiplayer_lobby.lobbyCount = array_length(rows);
    vs_lobby_browser_clamp();
    vs_lobby_count_schedule();
}

function vs_lobby_browser_enter_fx()
{
    if (!instance_exists(obj_multiplayer_lobby)) return;
    with (obj_multiplayer_lobby)
    {
        global.winner = "";
        member_y_offset = 0;
        cursor_pos = 0;
        audio_sound_gain(muted_bgm, 0, 500);
        audio_sound_gain(real_bgm, global.op_bgm_volume, 500);
    }
}

function vs_lobby_browser_after_enter(_ok, _data)
{
    if (_ok) vs_lobby_browser_enter_fx();
}

function vs_lobby_browser_do_top()
{
    var st = vs_lobby_browser_st();
    switch (st.top_i)
    {
        case 0:
            vs_lobby_log("ui browser matchmake");
            vs_lobby_matchmake(vs_lobby_browser_after_enter);
            break;
        case 1:
            // Shift+Host = private (same as legacy hostlobby patch).
            if (instance_exists(obj_multiplayer_lobby))
                obj_multiplayer_lobby.do_multiplayer_lobby_button("hostlobby");
            break;
        case 2:
            if (instance_exists(obj_multiplayer_lobby))
                obj_multiplayer_lobby.do_multiplayer_lobby_button("joinlobby");
            break;
        case 3:
            vs_lobby_browser_refresh(true);
            break;
    }
}

function vs_lobby_browser_do_list()
{
    var st = vs_lobby_browser_st();
    if (st.loading) return;
    var rows = vs_lobby_browser_filtered();
    var idx = st.page * st.page_size + st.list_i;
    if (idx < 0 || idx >= array_length(rows)) return;
    var row = rows[idx];
    if (!vs_lobby_browser_row_joinable(row)) return;
    // Avoid local name `code` — vsml has rewritten JSON keys from enclosing locals.
    var invite = "";
    if (variable_struct_exists(row, "code")) invite = string(variable_struct_get(row, "code"));
    if (invite == "") return;
    vs_lobby_log("ui browser join code=" + invite);
    vs_lobby_join(invite, vs_lobby_browser_after_enter);
}

function vs_lobby_browser_step()
{
    if (!vs_lobby_browser_active()) return false;
    if (!instance_exists(obj_multiplayer_lobby)) return false;
    if (vs_lobby_lobby_id() > 0) return false;
    if (obj_multiplayer_lobby.entering_code) return false;

    var st = vs_lobby_browser_st();
    vs_lobby_browser_clamp();

    // Cycle Default → Joinable → Unjoinable (secondary bind or F).
    if (input_check_pressed(10) || keyboard_check_pressed(ord("F")))
    {
        st.filter = (st.filter + 1) % 3;
        st.page = 0;
        st.list_i = 0;
        vs_lobby_browser_clamp();
        play_se(sfx_songsel_cursor);
    }

    var left = input_check_pressed(11);
    var right = input_check_pressed(12);
    var up = input_check_pressed(13);
    var down = input_check_pressed(14);

    if (st.focus == 0)
    {
        if (left || right)
        {
            var n = array_length(vs_lobby_browser_labels());
            st.top_i = (n + st.top_i + (right ? 1 : -1)) % n;
            play_se(sfx_songsel_cursor);
        }
        if (down)
        {
            // Only enter list focus when there is something to select.
            var rowsDown = vs_lobby_browser_filtered();
            if (array_length(rowsDown) > 0 && !st.loading)
            {
                st.focus = 1;
                play_se(sfx_songsel_cursor);
            }
        }
        if (input_check_pressed(4))
        {
            play_se(sfx_songsel_select);
            vs_lobby_browser_do_top();
        }
    }
    else
    {
        var rows = vs_lobby_browser_filtered();
        var n = array_length(rows);
        var pages = vs_lobby_browser_page_count(n);
        var ps = st.page_size;
        var start = st.page * ps;
        var on_page = clamp(n - start, 0, ps);

        if (left || right)
        {
            if (pages > 1)
            {
                st.page = (pages + st.page + (right ? 1 : -1)) % pages;
                st.list_i = 0;
                vs_lobby_browser_clamp();
                play_se(sfx_songsel_cursor);
            }
        }
        if (up)
        {
            if (st.list_i > 0)
            {
                st.list_i -= 1;
                play_se(sfx_songsel_cursor);
            }
            else
            {
                st.focus = 0;
                play_se(sfx_songsel_cursor);
            }
        }
        if (down)
        {
            if (on_page > 0 && st.list_i < on_page - 1)
            {
                st.list_i += 1;
                play_se(sfx_songsel_cursor);
            }
        }
        if (input_check_pressed(4))
        {
            play_se(sfx_songsel_select);
            vs_lobby_browser_do_list();
        }
    }
    return true;
}

function vs_lobby_browser_draw()
{
    if (!vs_lobby_browser_active()) return;
    if (!instance_exists(obj_multiplayer_lobby)) return;

    var st = vs_lobby_browser_st();
    vs_lobby_browser_clamp();
    var labels = vs_lobby_browser_labels();
    var nbtn = array_length(labels);
    var bw = 70;
    var gap = 4;
    var total = nbtn * bw + (nbtn - 1) * gap;
    var bx0 = floor((320 - total) / 2);
    var by = 4;
    var bh = 16;

    var i = 0;
    repeat (nbtn)
    {
        var bx = bx0 + i * (bw + gap);
        var sel = (st.focus == 0 && st.top_i == i);
        draw_set_color(c_black);
        draw_rectangle(bx + 1, by + 1, bx + bw + 1, by + bh + 1, true);
        draw_set_color(c_white);
        draw_rectangle(bx + 1, by + 1, bx + bw + 1, by + bh + 1, false);
        if (!sel)
        {
            draw_set_color(c_black);
            draw_rectangle(bx + 2, by + 2, bx + bw, by + bh, false);
        }
        draw_set_color(sel ? c_black : c_white);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_font(global.default_font);
        draw_text(bx + 1 + floor(bw / 2), by + 2 + floor(bh / 2), labels[i]);
        i++;
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var mid_x = 160;
    var mid_top = 28;
    if (st.loading)
    {
        draw_set_halign(fa_center);
        draw_set_color(c_aqua);
        draw_set_font(fnt_monacovs);
        draw_text(mid_x, 70, "Loading rooms");
        var cx = mid_x;
        var cy = 100;
        var r = 10;
        var phase = (current_time / 80) % 8;
        var ti = 0;
        repeat (8)
        {
            var a = (ti / 8) * 2 * pi - pi / 2;
            var bright = ((ti - floor(phase) + 8) % 8) < 3;
            draw_set_color(bright ? c_white : make_color_rgb(80, 80, 80));
            draw_circle(cx + cos(a) * r, cy + sin(a) * r, bright ? 2.5 : 1.5, false);
            ti++;
        }
        draw_set_font(global.default_font);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(mid_x, 118, "Refreshing...");
        draw_set_halign(fa_left);
        draw_set_color(c_white);
    }
    else
    {
        var rows = vs_lobby_browser_filtered();
        var n = array_length(rows);
        var pages = vs_lobby_browser_page_count(n);
        var ps = st.page_size;
        var start = st.page * ps;
        var on_page = clamp(n - start, 0, ps);
        var row_h = 20;
        if (on_page <= 0)
        {
            draw_set_halign(fa_center);
            draw_set_color(c_gray);
            draw_set_font(global.default_font);
            var empty = "No rooms";
            if (st.filter == 1) empty = "No joinable rooms";
            else if (st.filter == 2) empty = "No unjoinable rooms";
            draw_text(mid_x, 80, empty);
            draw_set_halign(fa_left);
            draw_set_color(c_white);
        }
        else
        {
            var ri = 0;
            repeat (on_page)
            {
                var row = rows[start + ri];
                var ry = mid_top + ri * row_h;
                var sel = (st.focus == 1 && st.list_i == ri);
                var joinable = vs_lobby_browser_row_joinable(row);
                if (sel)
                {
                    draw_set_color(c_white);
                    draw_rectangle(12, ry, 308, ry + row_h - 2, false);
                    draw_set_color(c_black);
                }
                else
                {
                    draw_set_color(joinable ? c_white : c_gray);
                }
                draw_set_font(global.default_font);
                draw_set_halign(fa_left);
                var host = variable_struct_exists(row, "hostName") ? string(row.hostName) : "?";
                if (string_length(host) > 14) host = string_copy(host, 1, 13) + ".";
                var cur = variable_struct_exists(row, "memberCount") ? string(floor(row.memberCount)) : "0";
                var mx = variable_struct_exists(row, "maxMembers") ? string(floor(row.maxMembers)) : "?";
                // Prefer struct_get for "code" — same vsml footgun as join JSON keys.
                var invite = "";
                if (variable_struct_exists(row, "code")) invite = string(variable_struct_get(row, "code"));
                var mark = joinable ? "" : " [X]";
                draw_text(16, ry + 4, host + "  " + cur + "/" + mx + "  " + invite + mark);
                ri++;
            }
        }
        if (!obj_multiplayer_lobby.entering_code)
        {
            var left = vs_lobby_browser_refresh_left();
            draw_set_halign(fa_center);
            draw_set_color(c_white);
            draw_set_font(global.default_font);
            draw_text(mid_x, 136, "Page " + string(st.page + 1) + "/" + string(pages)
                + "  " + vs_lobby_browser_filter_name(st.filter)
                + "  " + string(n) + " rooms"
                + "  " + string(left) + "s");
            draw_set_color(c_gray);
            draw_text(mid_x, 148, "F: filter   Shift+Host: private");
            draw_set_halign(fa_left);
        }
    }

    // Join-code overlay (browser uses fixed position; legacy keeps original).
    if (obj_multiplayer_lobby.entering_code)
    {
        draw_sprite(sp_multiplayer_entercode, 0, 135, 140);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_o(160, 141, string_upper(keyboard_string));
        draw_set_halign(fa_left);
    }

    draw_set_halign(fa_left);
    draw_set_color(c_white);
}
