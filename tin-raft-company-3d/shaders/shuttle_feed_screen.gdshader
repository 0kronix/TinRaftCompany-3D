shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D screen_texture : filter_linear_mipmap, repeat_disable;
/// 0 — плоский, 1 — CRT (выпуклость), 2 — иллюминатор
uniform float display_profile : hint_range(0.0, 2.0) = 1.0;
uniform float crt_barrel : hint_range(0.0, 0.45) = 0.14;
uniform float porthole_radius : hint_range(0.35, 0.5) = 0.48;
uniform float porthole_feather : hint_range(0.005, 0.12) = 0.035;
uniform float noise_amount : hint_range(0.0, 0.45) = 0.07;
uniform float chroma_aberration : hint_range(0.0, 0.02) = 0.0035;
uniform float scanline_strength : hint_range(0.0, 0.25) = 0.06;
uniform float vignette_strength : hint_range(0.0, 0.6) = 0.18;
uniform float global_brightness : hint_range(0.5, 1.4) = 1.0;
/// 1 — выкл.; выше — крупнее «пиксели» (мозаика по UV).
uniform float bad_net_mosaic : hint_range(1.0, 192.0) = 1.0;
/// Сдвиг строк как при рваном битстриме.
uniform float bad_net_tear : hint_range(0.0, 0.025) = 0.0;
/// Случайные скачки блока (потерянные макроблоки).
uniform float bad_net_glitch : hint_range(0.0, 1.0) = 0.0;
/// Редкие провалы в тёмный / зелёный кадр.
uniform float bad_net_dropout : hint_range(0.0, 1.0) = 0.0;
/// Постеризация (0 = нет).
uniform float bad_net_posterize : hint_range(0.0, 1.0) = 0.0;
/// Доп. снег по каналам на макроблоках.
uniform float bad_net_chroma_snow : hint_range(0.0, 0.35) = 0.0;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

/// Сжатие UV: мозаика, рвань, скачки блоков — до сэмпла картинки.
vec2 bad_net_warp_uv(vec2 uv_in) {
	vec2 u = uv_in;
	if (bad_net_mosaic > 1.001) {
		vec2 cell = floor(u * bad_net_mosaic);
		u = (cell + vec2(0.5)) / bad_net_mosaic;
	}
	u.x += bad_net_tear * (hash12(vec2(floor(u.y * 320.0), floor(TIME * 22.0))) - 0.5) * 2.0;
	vec2 blk = floor(u * vec2(36.0, 20.0));
	float gtab = hash13(vec3(blk.x, blk.y, floor(TIME * 14.0)));
	if (gtab < bad_net_glitch * 0.11) {
		vec2 ofs = vec2(hash12(blk + vec2(3.1, 9.7)), hash12(blk + vec2(1.3, 4.2))) - 0.5;
		u += ofs * 0.1 * bad_net_glitch;
	}
	return clamp(u, vec2(0.001), vec2(0.999));
}

vec2 barrel_uv(vec2 uv, float k) {
	vec2 c = uv * 2.0 - 1.0;
	float r2 = dot(c, c);
	c *= 1.0 + k * r2;
	return c * 0.5 + 0.5;
}

void fragment() {
	int prof = clamp(int(floor(display_profile + 0.01)), 0, 2);
	vec2 uv = UV;
	if (prof == 1) {
		uv = barrel_uv(uv, crt_barrel);
	}
	uv = bad_net_warp_uv(uv);
	vec2 ca = vec2(chroma_aberration, chroma_aberration * 0.7);
	vec2 uvR = clamp(uv + vec2(ca.x, 0.0), vec2(0.001), vec2(0.999));
	vec2 uvG = clamp(uv, vec2(0.001), vec2(0.999));
	vec2 uvB = clamp(uv - vec2(ca.x, ca.y), vec2(0.001), vec2(0.999));
	float r = textureLod(screen_texture, uvR, 0.0).r;
	float g = textureLod(screen_texture, uvG, 0.0).g;
	float b = textureLod(screen_texture, uvB, 0.0).b;
	vec3 col = vec3(r, g, b);

	float n = hash12(uv * vec2(1920.0, 1080.0) + fract(TIME) * 1200.0);
	n = mix(1.0, n * 2.0, noise_amount);
	col *= n;
	if (bad_net_chroma_snow > 0.001) {
		vec2 sb = floor(UV * vec2(48.0, 28.0));
		float sn = hash13(vec3(sb.x, sb.y, floor(TIME * 45.0)));
		vec3 snow = vec3(
			hash13(vec3(sb.x, sb.y, 1.1 + TIME)),
			hash13(vec3(sb.x, sb.y, 2.7 + TIME * 0.9)),
			hash13(vec3(sb.x, sb.y, 4.3 + TIME * 1.1))
		) - 0.5;
		col += snow * bad_net_chroma_snow * (0.35 + sn * 0.65);
	}
	vec2 dblk = floor(UV * vec2(28.0, 16.0));
	if (hash13(vec3(dblk.x, dblk.y, floor(TIME * 18.0))) < bad_net_dropout * 0.018) {
		float dr = hash12(dblk * 3.17 + vec2(TIME * 2.7, TIME * 1.9));
		col = mix(col, vec3(0.02, 0.04, 0.03) * (0.4 + dr), 0.55 + bad_net_dropout * 0.35);
	}
	if (bad_net_posterize > 0.001) {
		float lv = mix(40.0, 5.0, clamp(bad_net_posterize, 0.0, 1.0));
		col = floor(col * lv + vec3(0.5)) / lv;
	}

	/* Строки развёртки — только CRT; иллюминатор без «мониторных» полос */
	if (prof == 1) {
		float scan = sin(uv.y * 900.0 + TIME * 3.0) * 0.5 + 0.5;
		col *= 1.0 - scanline_strength * scan;
	}

	if (prof == 2) {
		vec2 d = uv - vec2(0.5);
		float dist = length(d);
		float edge = 1.0 - smoothstep(porthole_radius - porthole_feather, porthole_radius + porthole_feather * 0.5, dist);
		vec3 hull = vec3(0.025, 0.028, 0.032);
		col = mix(hull, col, edge);
		vec2 vign_uv = uv * (1.0 - uv.yx);
		float vig = pow(vign_uv.x * vign_uv.y * 15.0, 0.35);
		col *= mix(0.55, 1.0, vig);
	} else {
		vec2 vigc = uv - 0.5;
		float vig = 1.0 - vignette_strength * dot(vigc, vigc) * 3.2;
		col *= vig;
	}

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		col *= 0.12;
	}

	ALBEDO = col * global_brightness;
}
