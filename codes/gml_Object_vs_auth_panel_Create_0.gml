// VS Online account panel — Create
// Methods live in vs_auth_* GlobalScripts (object anons cannot call mod scripts).
depth = -10000;

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
