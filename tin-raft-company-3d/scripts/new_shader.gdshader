shader_type sky;

uniform float star_density : hint_range(0.0, 1.0) = 0.0; // 0.0 = много, 1.0 = мало
uniform float star_brightness : hint_range(0.0, 5.0) = 1.5;
uniform vec3 sky_color : source_color = vec3(0.0, 0.0, 0.05);
uniform float star_size_min : hint_range(0.01, 0.2) = 0.01;
uniform float star_size_max : hint_range(0.01, 0.2) = 0.20;
uniform float star_size_bias : hint_range(0.5, 5.0) = 4.0;
uniform vec3 star_color_warm : source_color = vec3(1.2, 0.85, 0.5);
uniform vec3 star_color_cold : source_color = vec3(0.5, 0.85, 1.2);
uniform float color_variance : hint_range(0.0, 1.0) = 0.5;
uniform float flicker_speed : hint_range(0.0, 5.0) = 4.0;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.15;

float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float hash2(vec2 p) {
	p = fract(p * vec2(567.89, 123.45));
	p += dot(p, p + 78.12);
	return fract(p.x * p.y);
}

vec3 drawStars(vec2 uv) {
	uv *= 40.0;
	vec2 cell = floor(uv);
	vec2 local = fract(uv) - 0.5;

	vec2 offset = vec2(hash(cell), hash(cell + 13.7)) - 0.5;
	vec2 starPos = local - offset * 0.6;

	float h = hash(cell);
	float h2 = hash2(cell);

	float sizeRand = pow(hash(cell + 7.3), star_size_bias);
	float size = star_size_min + sizeRand * (star_size_max - star_size_min);

	float brightness = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 shift = vec2(float(x), float(y)) * 0.008;
			float d = length(starPos + shift);
			float aa = 0.005;
			brightness += smoothstep(size + aa, size - aa, d);
		}
	}
	brightness /= 9.0;

	float sizeFactor = (size - star_size_min) / (star_size_max - star_size_min);
	brightness *= 0.3 + 0.7 * sizeFactor;

	brightness *= step(star_density, h2) * star_brightness;
	brightness *= (1.0 - flicker_strength) + flicker_strength * sin(TIME * flicker_speed * (1.0 + hash(cell + 0.5) * 4.0));

	float temp = mix(0.5, hash(cell + 99.0), color_variance);
	vec3 starColor = mix(star_color_warm, star_color_cold, temp);

	return starColor * brightness;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 absDir = abs(dir);
	vec2 uv;

	if (absDir.x >= absDir.y && absDir.x >= absDir.z) {
		uv = (dir.x > 0.0)
				? vec2(-dir.z, -dir.y) / absDir.x
				: vec2(dir.z, -dir.y) / absDir.x;
		uv += vec2(0.0, 0.0);
	} else if (absDir.y >= absDir.x && absDir.y >= absDir.z) {
		uv = (dir.y > 0.0)
				? vec2(dir.x, dir.z) / absDir.y
				: vec2(dir.x, -dir.z) / absDir.y;
		uv += vec2(10.0, 0.0);
	} else {
		uv = (dir.z > 0.0)
				? vec2(dir.x, -dir.y) / absDir.z
				: vec2(-dir.x, -dir.y) / absDir.z;
		uv += vec2(20.0, 0.0);
	}

	COLOR = sky_color + drawStars(uv);
}
