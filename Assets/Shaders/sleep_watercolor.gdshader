shader_type canvas_item;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform float blur_amount : hint_range(0.0, 4.0) = 1.4;
uniform float poster_levels : hint_range(2.0, 12.0) = 6.0;
uniform float edge_strength : hint_range(0.0, 2.0) = 0.65;
uniform float wash_strength : hint_range(0.0, 1.0) = 0.35;
uniform float paper_strength : hint_range(0.0, 1.0) = 0.25;
uniform float stroke_jitter : hint_range(0.0, 0.25) = 0.10;
uniform vec3 paper_tint : source_color = vec3(0.11, 0.09, 0.07);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(a, b, u.x) +
		(c - a) * u.y * (1.0 - u.x) +
		(d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));

	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = m * p;
		a *= 0.5;
	}

	return v;
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 posterize(vec3 c, float levels) {
	return floor(c * levels) / max(levels - 1.0, 1.0);
}

vec3 sample_blur(vec2 uv, vec2 px, float radius) {
	vec3 c = vec3(0.0);

	c += textureLod(SCREEN_TEXTURE, uv, 0.0).rgb * 0.30;
	c += textureLod(SCREEN_TEXTURE, uv + vec2(px.x * radius, 0.0), 0.0).rgb * 0.12;
	c += textureLod(SCREEN_TEXTURE, uv - vec2(px.x * radius, 0.0), 0.0).rgb * 0.12;
	c += textureLod(SCREEN_TEXTURE, uv + vec2(0.0, px.y * radius), 0.0).rgb * 0.12;
	c += textureLod(SCREEN_TEXTURE, uv - vec2(0.0, px.y * radius), 0.0).rgb * 0.12;
	c += textureLod(SCREEN_TEXTURE, uv + px * radius, 0.0).rgb * 0.11;
	c += textureLod(SCREEN_TEXTURE, uv - px * radius, 0.0).rgb * 0.11;

	return c;
}

float edge_detect(vec2 uv, vec2 px) {
	float l = luminance(textureLod(SCREEN_TEXTURE, uv - vec2(px.x, 0.0), 0.0).rgb);
	float r = luminance(textureLod(SCREEN_TEXTURE, uv + vec2(px.x, 0.0), 0.0).rgb);
	float u = luminance(textureLod(SCREEN_TEXTURE, uv - vec2(0.0, px.y), 0.0).rgb);
	float d = luminance(textureLod(SCREEN_TEXTURE, uv + vec2(0.0, px.y), 0.0).rgb);

	float gx = abs(r - l);
	float gy = abs(d - u);
	return clamp(gx + gy, 0.0, 1.0);
}

float brush_reveal_mask(vec2 uv) {
	float drift = fbm(uv * vec2(7.0, 16.0) + vec2(TIME * 0.06, TIME * 0.02));
	float streaks = sin((uv.y + drift * 0.18) * 55.0) * 0.5 + 0.5;
	float breakup = fbm(uv * vec2(28.0, 20.0) + vec2(0.0, TIME * 0.08));

	float front = uv.x + (drift - 0.5) * stroke_jitter;
	float jagged = (streaks - 0.5) * 0.08 + (breakup - 0.5) * 0.06;

	float e0 = reveal_progress - 0.10 + jagged;
	float e1 = reveal_progress + 0.02 + jagged;

	return 1.0 - smoothstep(e0, e1, front);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;

	// pequeña deformación tipo papel/acuarela
	float wash = fbm(uv * 8.0 + vec2(TIME * 0.03, TIME * 0.02));
	vec2 warped_uv = uv + (vec2(
		fbm(uv * 9.0 + vec2(11.0, TIME * 0.03)),
		fbm(uv * 9.0 + vec2(27.0, TIME * 0.03))
	) - 0.5) * 0.004 * wash_strength;

	vec3 blurred = sample_blur(warped_uv, px, blur_amount);
	vec3 base = posterize(blurred, poster_levels);

	float edge = edge_detect(warped_uv, px * 1.5);
	base *= 1.0 - edge * edge_strength;

	// grano / papel
	float paper = fbm(uv * 150.0 + vec2(TIME * 0.01, 0.0));
	base *= mix(1.0, 0.92 + paper * 0.12, paper_strength);

	// lavado de acuarela
	base = mix(base, base * (0.90 + wash * 0.18), wash_strength);

	// máscara de aparición en pinceladas
	float mask = clamp(brush_reveal_mask(uv), 0.0, 1.0);

	// fondo oscuro/papel para que no se vea el vídeo original sin filtrar
	vec3 hidden = paper_tint;
	vec3 final_col = mix(hidden, base, mask);

	COLOR = vec4(final_col, 1.0);
}