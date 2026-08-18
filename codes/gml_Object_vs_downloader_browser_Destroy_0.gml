// Chart Downloader — Destroy. No vs_* names (old vsml compiles those as instance vars).
if (variable_instance_exists(id, "do_destroy") && do_destroy != undefined)
{
    do_destroy();
}
