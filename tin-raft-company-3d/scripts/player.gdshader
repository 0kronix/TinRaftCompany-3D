shader_type canvas_item;

uniform float grain_strength : hint_range(0.0, 1.0) = 0.007;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.05;
uniform float vignette_size : hint_range(0.0, 1.0) = 0.3;
uniform float aberration_strength : hint_range(0.0, 0.02) = 0.002;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.01;
uniform float scanline_count : hint_range(100.0, 2000.0) = 600.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.95;
uniform vec3 tint_color : source_color = vec3(0.95, 0.97, 0.91);

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float hash(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    // Хроматическая аберрация
    float r = texture(SCREEN_TEXTURE, uv + vec2(aberration_strength, 0.0)).r;
    float g = texture(SCREEN_TEXTURE, uv).g;
    float b = texture(SCREEN_TEXTURE, uv - vec2(aberration_strength, 0.0)).b;
    vec3 color = vec3(r, g, b);

    // Сканлайны
    float scanline = sin(uv.y * scanline_count) * 0.5 + 0.5;
    color *= 1.0 - scanline_strength * (1.0 - scanline);

    // Зернистость
    float grain = hash(uv + fract(TIME * 0.1)) * 2.0 - 1.0;
    color += grain * grain_strength;

    // Виньетка
    vec2 vigUV = uv * 2.0 - 1.0;
    float vignette = 1.0 - dot(vigUV, vigUV) * vignette_strength * vignette_size;
    vignette = clamp(vignette, 0.0, 1.0);
    color *= vignette;

    // Тинт и яркость
    color *= tint_color * brightness;

    COLOR = vec4(color, 1.0);
}