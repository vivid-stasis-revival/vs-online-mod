// ============================================================================
// Runtime CJK / symbol font (GMS font_add).
//
// IDE fonts (fnt_monacovs, global.default_font) are baked glyph atlases.
// Missing codepoints draw as U+9647 ▯. Dynamic strings (chart names, artists,
// player names, search) are not in that atlas.
//
// Official path: font_add() a TTF/OTF (or a Windows CJK system font). first/last
// are ignored for file fonts; glyphs are cached into a dynamic texture page.
// ASCII UI chrome keeps the original pixel fonts. Only strings with codepoints
// > 127 switch to this font for measure + draw, then restore.
//
// Optional override: drop vs_cjk.ttf next to the exe or in working_directory.
// ============================================================================

function vs_font_needs_dyn(_s)
{
    var s = string(_s);
    var n = string_length(s);
    var i = 1;
    repeat (n)
    {
        if (ord(string_char_at(s, i)) > 127) return true;
        i++;
    }
    return false;
}

function vs_font_stack_ensure()
{
    if (!variable_global_exists("vs_font_stack")) global.vs_font_stack = [];
}

function vs_font_push(_f)
{
    if (_f == -1 || !font_exists(_f)) return false;
    var cur = draw_get_font();
    if (cur == _f) return false;
    vs_font_stack_ensure();
    array_push(global.vs_font_stack, cur);
    draw_set_font(_f);
    return true;
}

function vs_font_pop()
{
    vs_font_stack_ensure();
    var n = array_length(global.vs_font_stack);
    if (n <= 0) return;
    var prev = global.vs_font_stack[n - 1];
    array_pop(global.vs_font_stack);
    if (prev != -1 && font_exists(prev)) draw_set_font(prev);
}

function vs_font_covers_cjk(_f)
{
    if (_f == -1 || !font_exists(_f)) return false;
    var prev = draw_get_font();
    draw_set_font(_f);
    var ok = (string_width("汉") > 0) || (string_width("あ") > 0);
    draw_set_font(prev);
    return ok;
}

function vs_font_try_add(_name, _size)
{
    if (_name == "" || _size <= 0) return -1;
    var f = -1;
    try
    {
        f = font_add(_name, _size, false, false, 32, 65535);
    }
    catch (_e)
    {
        f = -1;
    }
    if (f == -1 || !font_exists(f)) return -1;
    if (vs_font_covers_cjk(f)) return f;
    try
    {
        font_delete(f);
    }
    catch (_e2)
    {
        f = -1;
    }
    return -1;
}

function vs_font_copy_into_workdir(_src)
{
    if (_src == "" || !file_exists(_src)) return "";
    var dest = working_directory + "vs_cjk.ttf";
    if (_src == dest) return dest;
    try
    {
        file_copy(_src, dest);
    }
    catch (_e)
    {
        dest = _src;
    }
    if (file_exists(dest)) return dest;
    return _src;
}

function vs_font_candidates()
{
    var out = [];
    var local = working_directory + "vs_cjk.ttf";
    if (file_exists(local)) array_push(out, local);
    var otf = working_directory + "vs_cjk.otf";
    if (file_exists(otf)) array_push(out, otf);
    var bundled = program_directory + "vs_cjk.ttf";
    if (file_exists(bundled))
    {
        var copied = vs_font_copy_into_workdir(bundled);
        if (copied != "") array_push(out, copied);
        array_push(out, "vs_cjk.ttf");
        array_push(out, bundled);
    }
    array_push(out, "vs_cjk.ttf");
    array_push(out, "C:/Windows/Fonts/msyh.ttf");
    array_push(out, "C:/Windows/Fonts/msyhbd.ttf");
    array_push(out, "C:/Windows/Fonts/simhei.ttf");
    array_push(out, "C:/Windows/Fonts/simsun.ttf");
    array_push(out, "C:/Windows/Fonts/msgothic.ttf");
    array_push(out, "C:/Windows/Fonts/YuGothR.ttf");
    array_push(out, "C:/Windows/Fonts/meiryo.ttf");
    array_push(out, "Microsoft YaHei UI");
    array_push(out, "Microsoft YaHei");
    array_push(out, "微软雅黑");
    array_push(out, "Yu Gothic UI");
    array_push(out, "Yu Gothic");
    array_push(out, "Meiryo UI");
    array_push(out, "Meiryo");
    array_push(out, "MS Gothic");
    array_push(out, "Malgun Gothic");
    array_push(out, "Noto Sans CJK SC");
    array_push(out, "Source Han Sans SC");
    array_push(out, "SimHei");
    array_push(out, "SimSun");
    array_push(out, "Microsoft JhengHei");
    return out;
}

function vs_font_px(_font, _fallback)
{
    if (_font != -1 && font_exists(_font))
    {
        var sz = font_get_size(_font);
        if (sz > 0) return sz;
    }
    return _fallback;
}

function vs_font_ensure()
{
    if (variable_global_exists("vs_font_ready")) return;
    global.vs_font_ready = true;
    global.vs_font_body = -1;
    global.vs_font_title = -1;
    global.vs_font_src = "";

    var body_sz = 12;
    var title_sz = 14;
    if (variable_global_exists("default_font")) body_sz = vs_font_px(global.default_font, body_sz);
    title_sz = vs_font_px(fnt_monacovs, body_sz + 2);

    font_add_enable_aa(true);
    font_texture_page_size = 2048;

    var names = vs_font_candidates();
    var i = 0;
    repeat (array_length(names))
    {
        var src = names[i];
        var body = vs_font_try_add(src, body_sz);
        if (body != -1)
        {
            global.vs_font_body = body;
            global.vs_font_src = src;
            if (title_sz == body_sz)
            {
                global.vs_font_title = body;
            }
            else
            {
                var title = vs_font_try_add(src, title_sz);
                global.vs_font_title = (title != -1) ? title : body;
            }
            show_debug_message("VS Online: dyn font " + src + " body=" + string(body_sz) + " title=" + string(title_sz));
            return;
        }
        i++;
    }
    show_debug_message("VS Online: dyn font failed (CJK will still tofu)");
}

function vs_font_init()
{
    vs_font_ensure();
}

function vs_font_body()
{
    vs_font_ensure();
    return global.vs_font_body;
}

function vs_font_title()
{
    vs_font_ensure();
    return global.vs_font_title;
}

function vs_font_for_current()
{
    vs_font_ensure();
    var cur = draw_get_font();
    if (cur == fnt_monacovs)
    {
        if (global.vs_font_title != -1) return global.vs_font_title;
    }
    return global.vs_font_body;
}

function vs_font_push_for(_s)
{
    if (!vs_font_needs_dyn(_s)) return false;
    return vs_font_push(vs_font_for_current());
}

function vs_font_begin(_s)
{
    return vs_font_push_for(_s);
}

function vs_font_end(_on)
{
    if (_on) vs_font_pop();
}

function vs_font_clip_now(_s, _maxw)
{
    var s = string(_s);
    if (_maxw <= 0 || string_width(s) <= _maxw) return s;
    while (string_length(s) > 1 && string_width(s + "..") > _maxw)
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    return s + "..";
}

function vs_draw_text(_x, _y, _s)
{
    var s = string(_s);
    var on = vs_font_push_for(s);
    draw_text(_x, _y, s);
    vs_font_end(on);
}

function vs_draw_clip(_x, _y, _s, _maxw)
{
    var s = string(_s);
    var on = vs_font_push_for(s);
    draw_text(_x, _y, vs_font_clip_now(s, _maxw));
    vs_font_end(on);
}

function vs_draw_text_max(_x, _y, _s, _maxw)
{
    vs_draw_clip(_x, _y, _s, _maxw);
}

function vs_draw_text_o(_x, _y, _s)
{
    var s = string(_s);
    var on = vs_font_push_for(s);
    draw_text_o(_x, _y, s);
    vs_font_end(on);
}

function vs_draw_text_o_max(_x, _y, _s, _maxw)
{
    var s = string(_s);
    var on = vs_font_push_for(s);
    draw_text_o(_x, _y, vs_font_clip_now(s, _maxw));
    vs_font_end(on);
}

function vs_draw_text_ext(_x, _y, _s, _sep, _w)
{
    var s = string(_s);
    var on = vs_font_push_for(s);
    draw_text_ext(_x, _y, s, _sep, _w);
    vs_font_end(on);
}
