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
            page_size: 5,
            busy: false,
            status: "",
            status_until: 0
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
    if (!variable_struct_exists(st, "busy")) st.busy = false;
    if (!variable_struct_exists(st, "status")) st.status = "";
    if (!variable_struct_exists(st, "status_until")) st.status_until = 0;
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
    st.busy = false;
    st.status = "";
    st.status_until = 0;
    vs_lobby_browser_refresh(true);
}

// Shift held: Host→Private, Join→Paste (same actions as Shift+confirm).
function vs_lobby_browser_labels()
{
    if (keyboard_check(vk_shift))
        return ["Match", "Private", "Paste"];
    return ["Match", "Host", "Join"];
}

function vs_lobby_browser_set_status(_msg)
{
    var st = vs_lobby_browser_st();
    st.status = string(_msg);
    st.status_until = current_time + 4000;
}

function vs_lobby_browser_need_account()
{
    if (vs_online_is_account()) return true;
    vs_online_show_account_required();
    return false;
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
    var cur = 0;
    if (variable_struct_exists(_row, "connectedMemberCount"))
        cur = floor(_row.connectedMemberCount);
    else if (variable_struct_exists(_row, "memberCount"))
        cur = floor(_row.memberCount);
    var mx = variable_struct_exists(_row, "maxMembers") ? floor(_row.maxMembers) : 0;
    if (mx <= 0) mx = 8;
    return (!started) && (cur < mx);
}

function vs_lobby_browser_row_member_count(_row)
{
    if (_row == undefined || !is_struct(_row)) return "0";
    if (variable_struct_exists(_row, "connectedMemberCount"))
        return string(floor(_row.connectedMemberCount));
    if (variable_struct_exists(_row, "memberCount"))
        return string(floor(_row.memberCount));
    return "0";
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
    var st = vs_lobby_browser_st();
    st.busy = false;
    if (_ok) vs_lobby_browser_enter_fx();
    else vs_lobby_browser_set_status("Could not join / match.  无法加入或匹配。");
}

function vs_lobby_browser_do_top()
{
    var st = vs_lobby_browser_st();
    // List refresh must not block Match/Host/Join.
    if (st.busy)
    {
        vs_lobby_browser_set_status("Busy...");
        return;
    }
    switch (st.top_i)
    {
        case 0:
            if (!vs_lobby_browser_need_account()) return;
            vs_lobby_log("ui browser matchmake");
            st.busy = true;
            vs_lobby_matchmake(vs_lobby_browser_after_enter);
            break;
        case 1:
            // Shift+Host = private (hostlobby patch reads vk_shift).
            if (!vs_lobby_browser_need_account()) return;
            if (instance_exists(obj_multiplayer_lobby))
                obj_multiplayer_lobby.do_multiplayer_lobby_button("hostlobby");
            break;
        case 2:
            if (keyboard_check(vk_shift))
            {
                if (!vs_lobby_browser_need_account()) return;
                var clip = string_upper(string_copy(clipboard_get_text(), 1, 6));
                if (string_length(clip) != 6)
                {
                    vs_lobby_browser_set_status("Clipboard needs a 6-char code.  剪贴板需6位房间码。");
                    return;
                }
                vs_lobby_log("ui browser paste join=" + clip);
                st.busy = true;
                vs_lobby_join(clip, vs_lobby_browser_after_enter);
            }
            else
            {
                if (instance_exists(obj_multiplayer_lobby))
                    obj_multiplayer_lobby.do_multiplayer_lobby_button("joinlobby");
            }
            break;
    }
}

function vs_lobby_browser_do_list()
{
    var st = vs_lobby_browser_st();
    if (st.loading || st.busy) return;
    if (!vs_lobby_browser_need_account()) return;
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
    st.busy = true;
    vs_lobby_join(invite, vs_lobby_browser_after_enter);
}

// Early-exit from lobby Step_0 (same chain as dl/ops). Handles browser
// landing input + back; returns true when this frame is consumed.
function vs_lobby_try_browser_step()
{
    if (!vs_lobby_browser_active()) return false;
    if (!instance_exists(obj_multiplayer_lobby)) return false;
    if (vs_lobby_lobby_id() > 0) return false;
    with (obj_multiplayer_lobby)
    {
        if (confirmMenu != undefined) return false;
        if (entering_code) return false;
    }
    vs_lobby_browser_step();
    if (input_check_pressed(5))
        vs_lobby_browser_leave_landing();
    return true;
}

function vs_lobby_browser_leave_landing()
{
    if (!instance_exists(obj_multiplayer_lobby)) return;
    with (obj_multiplayer_lobby)
    {
        global.multiplayerLobby = false;
        global.op_autoplay = global.hadAutoplay;
        global.hadAutoplay = undefined;
        audio_stop_all();
        play_se(sfx_songsel_beginsong);
        var transition = instance_create_depth(room_width / 2, room_height / 2, -1000, o_transition_diamond);
        with (transition)
        {
            TweenEasyScale(1, 1, 320, 320, 0, 60, EaseOutQuad);
            next_room = scene_mainmenu;
            alarm[0] = 60;
        }
        confirmMenu = true;
    }
}

function vs_lobby_browser_cycle_top(_dir)
{
    var st = vs_lobby_browser_st();
    var n = array_length(vs_lobby_browser_labels());
    if (n <= 0) return;
    st.top_i = (n + st.top_i + _dir) % n;
    play_se(sfx_songsel_cursor);
}

function vs_lobby_browser_step()
{
    if (!vs_lobby_browser_active()) return false;
    if (!instance_exists(obj_multiplayer_lobby)) return false;
    if (vs_lobby_lobby_id() > 0) return false;
    if (obj_multiplayer_lobby.entering_code) return false;

    var st = vs_lobby_browser_st();
    // Unstick a hung list refresh so Match/Host stay usable.
    if (st.loading && st.inflight <= 0)
        st.loading = false;
    vs_lobby_browser_clamp();

    // F only — input 10 is often Shift / secondary, which must stay free for
    // Shift+Host (private) and Shift+Join (paste).
    if (keyboard_check_pressed(ord("F")))
    {
        st.filter = (st.filter + 1) % 3;
        st.page = 0;
        st.list_i = 0;
        vs_lobby_browser_clamp();
        vs_lobby_browser_set_status("Filter: " + vs_lobby_browser_filter_name(st.filter) + "  (F)");
        play_se(sfx_songsel_cursor);
    }

    var left = input_check_pressed(11);
    var right = input_check_pressed(12);
    var up = input_check_pressed(13);
    var down = input_check_pressed(14);

    if (st.focus == 0)
    {
        // L/R always cycle Match/Host/Join.
        if (left) vs_lobby_browser_cycle_top(-1);
        if (right) vs_lobby_browser_cycle_top(1);
        // U/D: legacy muscle memory — cycle buttons; Down enters list when ready.
        if (up) vs_lobby_browser_cycle_top(-1);
        if (down)
        {
            var rowsDown = vs_lobby_browser_filtered();
            if (array_length(rowsDown) > 0 && !st.loading)
            {
                st.focus = 1;
                play_se(sfx_songsel_cursor);
            }
            else
                vs_lobby_browser_cycle_top(1);
        }
        if (input_check_pressed(4) || keyboard_check_pressed(vk_enter))
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
        if (input_check_pressed(4) || keyboard_check_pressed(vk_enter))
        {
            play_se(sfx_songsel_select);
            vs_lobby_browser_do_list();
        }
    }
    return true;
}

// Draw_0 entry: codepatch inserts `vs_lobby_draw0(); exit;` at the top
// (Type 1). vsml Type 2 is InsertBefore — NOT a full replace — so an
// ExternalFile Type 2 previously left the stock Draw_0 running too.
function vs_lobby_draw0()
{
    draw_set_default();
    if (vs_lobby_lobby_id() <= 0)
    {
        if (vs_lobby_browser_active())
            vs_lobby_browser_draw();
        else
            vs_lobby_draw0_legacy();
    }
    vs_lobby_draw0_status();
}

function vs_lobby_draw0_legacy()
{
    var height = 19;
    var width = 110;
    var gap = 11;
    var itemCount = array_length(menu_actions_landing);
    var totalHeight = (itemCount * (height + gap)) - gap;
    var startY = floor((180 - totalHeight) / 2);
    for (var i = 0; i < itemCount; i++)
    {
        var _x = 104;
        var _y = startY + (i * (height + gap));
        draw_set_color(c_black);
        draw_rectangle(_x + 1, _y + 1, _x + 1 + width, _y + 1 + height, true);
        draw_set_color(c_white);
        draw_rectangle(_x + 1, _y + 1, _x + 1 + width, _y + 1 + height, false);
        if (i != cursor_pos)
        {
            draw_set_color(c_black);
            draw_rectangle(_x + 2, _y + 2, _x + width, _y + height, false);
        }
        draw_set_color((i == cursor_pos) ? c_black : c_white);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(_x + 1 + floor(width / 2), _y + 2 + floor(height / 2), menu_actions_landing[i].txt);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_o(160, startY + totalHeight + 7, "Total Lobbies: " + string(lobbyCount) + "\nHold Shift and Press \"Paste Code\" to join random lobby");
    if (entering_code)
    {
        draw_sprite(sp_multiplayer_entercode, 0, 135, startY + totalHeight + 6);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_o(160, startY + totalHeight + 7, string_upper(keyboard_string));
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

function vs_lobby_draw0_status()
{
    var label = vs_online_is_custom() ? "Server:" : "Steamworks:";
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_white);
    draw_set_font(global.default_font);
    draw_text(2, 170, label);
    var ox = 2 + string_width(label + " ");
    if (vs_online_is_connected())
    {
        draw_set_color(c_lime);
        draw_text(ox, 170, "Connected");
    }
    else
    {
        draw_set_color(c_red);
        draw_text(ox, 170, "Disconnected");
    }
}

function vs_lobby_browser_keychip(_x, _y, _key, _hint, _right)
{
    var kw = string_width(_key);
    var hw = string_width(_hint);
    var need = kw + 4 + hw + 5;
    if (_right > 0 && _x + need > _right) return _x;
    draw_set_color(make_color_rgb(80, 220, 230));
    draw_rectangle(_x - 1, _y - 1, _x + kw + 1, _y + 8, false);
    draw_set_color(c_black);
    draw_text(_x, _y, _key);
    draw_set_color(make_color_rgb(170, 176, 186));
    draw_text(_x + kw + 4, _y, _hint);
    return _x + need;
}

function vs_lobby_browser_draw()
{
    if (!vs_lobby_browser_active()) return;
    if (!instance_exists(obj_multiplayer_lobby)) return;

    var st = vs_lobby_browser_st();
    vs_lobby_browser_clamp();

    // Downloader-like panel in room space (320x180).
    var pad = 3;
    var bx = pad;
    var by = pad;
    var bw = 320 - pad * 2;
    var bh = 166 - pad;
    draw_set_alpha(0.55);
    draw_set_color(c_black);
    draw_rectangle(0, 0, 320, 180, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(12, 14, 18));
    draw_rectangle(bx, by, bx + bw, by + bh, false);
    draw_set_color(make_color_rgb(48, 52, 60));
    draw_rectangle(bx, by, bx + bw, by + bh, true);

    draw_set_font(fnt_monacovs);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(make_color_rgb(80, 220, 230));
    draw_text(bx + 5, by + 2, "Lobby");
    draw_set_font(global.default_font);
    draw_set_halign(fa_right);
    draw_set_color(make_color_rgb(180, 186, 196));
    var left = vs_lobby_browser_refresh_left();
    draw_text(bx + bw - 5, by + 3, string(left) + "s");
    draw_set_halign(fa_left);

    var labels = vs_lobby_browser_labels();
    var nbtn = array_length(labels);
    var tabx = bx + 5;
    var taby = by + 14;
    var i = 0;
    repeat (nbtn)
    {
        var lab = labels[i];
        var tw = string_width(lab) + 10;
        var sel = (st.focus == 0 && st.top_i == i);
        if (sel)
        {
            draw_set_color(make_color_rgb(240, 210, 70));
            draw_rectangle(tabx, taby, tabx + tw, taby + 11, false);
            draw_set_color(c_black);
        }
        else
        {
            draw_set_color(make_color_rgb(110, 116, 126));
        }
        draw_text(tabx + 5, taby + 1, lab);
        tabx += tw + 4;
        i++;
    }

    var listTop = by + 28;
    var listBot = by + bh - 22;
    var row_h = 14;
    var mid_x = bx + floor(bw / 2);

    if (st.loading || st.busy)
    {
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(80, 220, 230));
        draw_set_font(fnt_monacovs);
        draw_text(mid_x, listTop + 28, st.busy ? "Working..." : "Loading rooms");
        draw_set_font(global.default_font);
        draw_set_color(make_color_rgb(180, 186, 196));
        draw_text(mid_x, listTop + 48, st.busy ? "Please wait" : "Refreshing...");
        draw_set_halign(fa_left);
    }
    else
    {
        var rows = vs_lobby_browser_filtered();
        var n = array_length(rows);
        var pages = vs_lobby_browser_page_count(n);
        var ps = st.page_size;
        var start = st.page * ps;
        var on_page = clamp(n - start, 0, ps);
        if (on_page <= 0)
        {
            draw_set_halign(fa_center);
            draw_set_color(make_color_rgb(140, 146, 156));
            var empty = "No rooms";
            if (st.filter == 1) empty = "No joinable rooms";
            else if (st.filter == 2) empty = "No unjoinable rooms";
            draw_text(mid_x, listTop + 36, empty);
            draw_set_halign(fa_left);
        }
        else
        {
            var ri = 0;
            repeat (on_page)
            {
                var row = rows[start + ri];
                var ry = listTop + ri * row_h;
                if (ry + row_h > listBot) break;
                var sel = (st.focus == 1 && st.list_i == ri);
                var joinable = vs_lobby_browser_row_joinable(row);
                var rx0 = bx + 4;
                var rx1 = bx + bw - 4;
                if (sel)
                {
                    draw_set_color(make_color_rgb(240, 210, 70));
                    draw_rectangle(rx0, ry, rx1, ry + row_h - 2, false);
                }
                else
                {
                    draw_set_color(make_color_rgb(22, 24, 30));
                    draw_rectangle(rx0, ry, rx1, ry + row_h - 2, false);
                    draw_set_color(make_color_rgb(40, 44, 52));
                    draw_rectangle(rx0, ry, rx1, ry + row_h - 2, true);
                }
                draw_set_color(sel ? c_black : (joinable ? make_color_rgb(200, 204, 212) : make_color_rgb(120, 124, 134)));
                draw_set_halign(fa_left);
                var host = variable_struct_exists(row, "hostName") ? string(row.hostName) : "?";
                if (string_length(host) > 12) host = string_copy(host, 1, 11) + ".";
                var cur = variable_struct_exists(row, "memberCount") ? string(floor(row.memberCount)) : "0";
                var mx = variable_struct_exists(row, "maxMembers") ? string(floor(row.maxMembers)) : "?";
                var invite = "";
                if (variable_struct_exists(row, "code")) invite = string(variable_struct_get(row, "code"));
                var mark = joinable ? "" : " X";
                draw_text(rx0 + 4, ry + 2, host + "  " + cur + "/" + mx + "  " + invite + mark);
                ri++;
            }
        }
        draw_set_halign(fa_right);
        draw_set_color(make_color_rgb(180, 186, 196));
        draw_text(bx + bw - 5, by + bh - 20, "[" + string(st.page + 1) + "/" + string(pages) + "] "
            + vs_lobby_browser_filter_name(st.filter) + " " + string(n));
        draw_set_halign(fa_left);
        if (st.status != "" && current_time < st.status_until)
        {
            draw_set_color(make_color_rgb(120, 210, 140));
            draw_text(bx + 5, by + bh - 20, st.status);
        }
    }

    var hx = bx + 5;
    var hy = by + bh - 10;
    var right = bx + bw - 5;
    if (st.focus == 0)
    {
        hx = vs_lobby_browser_keychip(hx, hy, "ENTER", "ok", right);
        hx = vs_lobby_browser_keychip(hx, hy, "LR/UD", "btn", right);
        hx = vs_lobby_browser_keychip(hx, hy, "SHIFT", "priv/paste", right);
        vs_lobby_browser_keychip(hx, hy, "F", "filt", right);
    }
    else
    {
        hx = vs_lobby_browser_keychip(hx, hy, "ENTER", "join", right);
        hx = vs_lobby_browser_keychip(hx, hy, "LR", "page", right);
        hx = vs_lobby_browser_keychip(hx, hy, "F", "filt", right);
        vs_lobby_browser_keychip(hx, hy, "UD", "move", right);
    }

    if (obj_multiplayer_lobby.entering_code)
    {
        draw_set_alpha(0.55);
        draw_set_color(c_black);
        draw_rectangle(0, 0, 320, 180, false);
        draw_set_alpha(1);
        draw_sprite(sp_multiplayer_entercode, 0, 135, 140);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_o(160, 141, string_upper(keyboard_string));
        draw_set_halign(fa_left);
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_white);
}
