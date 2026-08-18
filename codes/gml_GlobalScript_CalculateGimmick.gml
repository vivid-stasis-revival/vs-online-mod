function CalcGimmickWeight(modsDef){
    var sum_w=0;
    for (i = 0; i < array_length(modsDef.mods); i++)
    {
        sum_w += modsDef.mods[i].w??1;
    }
    return sum_w;
}