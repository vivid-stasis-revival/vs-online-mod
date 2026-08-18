column_widths = [];
var _text="";
for (var i=1;i<=20;i++){
    if (i%2==0){
        _text=string(18+i/2);
    }
    else{
        _text=string(18+(i-1)/2)+"+";
    }
    array_push(column_options[5],_text);
}
