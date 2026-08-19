column_widths = [];
// Official MAX/MIN stop at "17". The next filter slot is 17+ (const 17.5).
array_push(column_options[4], "17+");
array_push(column_options[5], "17+");
for (var i = 0; i < 20; i++)
{
    var n = 18 + floor(i / 2);
    var _text = (i % 2 == 0) ? string(n) : (string(n) + "+");
    array_push(column_options[4], _text);
    array_push(column_options[5], _text);
}
