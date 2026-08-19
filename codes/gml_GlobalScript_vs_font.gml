// ============================================================================
// Runtime CJK / symbol font — pixel TTF via font_add.
//
// IDE fonts are baked atlases; missing codepoints draw as U+9647 ▯.
// Official GMS path for Asian glyphs is font_add() of a TTF. Pixel look needs:
//   - font_add_enable_aa(false)
//   - size = the font's native pixel size (do not scale)
//   - gpu_set_tex_filter(false) while drawing
//
// Bundled: raw/vs_cjk.ttf (Fusion Pixel 12px proportional, OFL-1.1).
// vsml copies it next to the exe; we font_add at 12px. Override by dropping
// vs_cjk.ttf / vs_cjk8.ttf / vs_cjk10.ttf in the game or save folder.
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
    if (!variable_global_exists("vs_font_filter_stack")) global.vs_font_filter_stack = [];
}

function vs_font_push(_f)
{
    if (_f == -1 || !font_exists(_f)) return false;
    var cur = draw_get_font();
    if (cur == _f)
    {
        gpu_set_tex_filter(false);
        return false;
    }
    vs_font_stack_ensure();
    array_push(global.vs_font_stack, cur);
    array_push(global.vs_font_filter_stack, gpu_get_tex_filter());
    gpu_set_tex_filter(false);
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
    var nf = array_length(global.vs_font_filter_stack);
    if (nf > 0)
    {
        gpu_set_tex_filter(global.vs_font_filter_stack[nf - 1]);
        array_pop(global.vs_font_filter_stack);
    }
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

function vs_font_copy_into_workdir(_src, _dest_name)
{
    if (_src == "" || !file_exists(_src)) return "";
    var dest = working_directory + _dest_name;
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

function vs_font_push_file(_out, _path, _size)
{
    if (_path == "" || !file_exists(_path)) return;
    array_push(_out, { name: _path, size: _size, pixel: true });
}

function vs_font_push_name(_out, _name, _size)
{
    array_push(_out, { name: _name, size: _size, pixel: false });
}

function vs_font_collect_files(_out, _fname, _size)
{
    vs_font_push_file(_out, working_directory + _fname, _size);
    var bundled = program_directory + _fname;
    if (file_exists(bundled))
    {
        var copied = vs_font_copy_into_workdir(bundled, _fname);
        vs_font_push_file(_out, copied, _size);
        vs_font_push_name(_out, _fname, _size);
        vs_font_push_file(_out, bundled, _size);
    }
}

function vs_font_candidates()
{
    var out = [];
    vs_font_collect_files(out, "vs_cjk.ttf", 12);
    vs_font_collect_files(out, "vs_cjk.otf", 12);
    vs_font_collect_files(out, "vs_cjk10.ttf", 10);
    vs_font_collect_files(out, "vs_cjk8.ttf", 8);
    vs_font_push_name(out, "vs_cjk.ttf", 12);
    return out;
}

function vs_font_ensure()
{
    if (variable_global_exists("vs_font_ready")) return;
    global.vs_font_ready = true;
    global.vs_font_body = -1;
    global.vs_font_title = -1;
    global.vs_font_src = "";

    font_add_enable_aa(false);
    font_texture_page_size = 2048;

    var names = vs_font_candidates();
    var i = 0;
    repeat (array_length(names))
    {
        var c = names[i];
        var body = vs_font_try_add(c.name, c.size);
        if (body != -1)
        {
            global.vs_font_body = body;
            global.vs_font_title = body;
            global.vs_font_src = c.name;
            show_debug_message("VS Online: pixel font " + c.name + " @" + string(c.size) + "px");
            return;
        }
        i++;
    }
    show_debug_message("VS Online: pixel font failed (CJK will still tofu)");
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
