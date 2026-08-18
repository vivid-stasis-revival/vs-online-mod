// Auth panel — Create. No vs_* names here. vs_auth_setup() runs after create.
depth = -10000;
cfg = undefined;
signed_in = false;
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
