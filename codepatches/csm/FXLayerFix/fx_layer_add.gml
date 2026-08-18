
chromaLayer=layer_get_id("Fx_chroma")
redLayer = layer_create(-2300, "FX_red");
twirlLayer = layer_create(-2200, "FX_twirl");
posterizeLayer = layer_create(-2100, "FX_posterize");
edgeLayer = layer_create(-2000, "FX_edge");
hueLayer = layer_create(-1900, "FX_hue");
underwaterLayer = layer_create(-1400, "FX_underwater");
zoomLayer = layer_create(300, "FX_zoom");

//Underwater Init
underwaterFX=fx_create("_filter_underwater")
fx_set_parameter(underwaterFX,"g_Distort1Speed",0.01)
fx_set_parameter(underwaterFX,"g_Distort2Speed",0.03)
fx_set_parameter(underwaterFX,"g_Distort1Scale",[ 20,2 ])
fx_set_parameter(underwaterFX,"g_Distort2Scale",[ 100,10 ])
fx_set_parameter(underwaterFX,"g_Distort1Amount",0.01)
fx_set_parameter(underwaterFX,"g_Distort2Amount",0.01)
fx_set_parameter(underwaterFX,"g_ChromaSpreadAmount",1)
fx_set_parameter(underwaterFX,"g_CamOffsetScale",1)
fx_set_parameter(underwaterFX,"g_GlintCol",[ 0,0,0,1 ])
fx_set_parameter(underwaterFX,"g_TintCol",[ 1,1,1,1 ])
fx_set_parameter(underwaterFX,"g_AddCol",[ 0,0,0,1 ])

//Hue Init
hueFX=fx_create("_filter_hue")
fx_set_parameter(hueFX, "g_HueShift", 0);
fx_set_parameter(hueFX, "g_HueSaturation",1);

//chorma Init
fx_set_parameter(layer_get_fx("FX_chroma"), "g_Distort2Amount", 0.01);

layer_set_fx(redLayer, fx_create("_filter_colourise"));
layer_set_fx(twirlLayer, fx_create("_filter_twirl_distort"));
layer_set_fx(posterizeLayer, fx_create("_filter_posterise"));
layer_set_fx(edgeLayer, fx_create("_filter_edgedetect"));
layer_set_fx(hueLayer, hueFX);
layer_set_fx(underwaterLayer,underwaterFX );
layer_set_fx(zoomLayer,fx_create("_filter_zoom_blur"));
layer_set_visible(chromaLayer, 1);
layer_set_visible(redLayer, 0);
layer_set_visible(posterizeLayer, 0);
layer_set_visible(edgeLayer, 0);
layer_set_visible(hueLayer, 1);
layer_set_visible(underwaterLayer, 1);
layer_set_visible(zoomLayer, 0);