shader_type canvas_item;

// ============================================================
// VICTORIAN NIGHT CLOUDS — domain warping
// Nubes con formas más orgánicas y alargadas
// ============================================================

uniform float cloud_speed : hint_range(0.0, 0.5) = 0.03;
uniform float cloud_scale : hint_range(0.5, 8.0) = 2.2;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.30;
uniform float cloud_elongation : hint_range(0.1, 4.0) = 2.5; // estira horizontalmente

uniform vec4 sky_color_top : source_color = vec4(0.03, 0.01, 0.01, 1.0);
uniform vec4 sky_color_bottom : source_color = vec4(0.08, 0.02, 0.02, 1.0);
uniform vec4 cloud_color_dark : source_color = vec4(0.10, 0.03, 0.03, 1.0);
uniform vec4 cloud_color_light : source_color = vec4(0.35, 0.10, 0.10, 1.0);

uniform float moon_glow : hint_range(0.0, 1.0) = 0.30;
uniform float moon_glow_x : hint_range(0.0, 1.0) = 0.50;
uniform float moon_glow_y : hint_range(0.0, 1.0) = 0.20;
uniform float warp_strength : hint_range(0.0, 2.0) = 0.9; // fuerza del domain warp

// ============================================================
// RUIDO BASE
// ============================================================
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(hash2(i + vec2(0,0)), f - vec2(0,0));
	float b = dot(hash2(i + vec2(1,0)), f - vec2(1,0));
	float c = dot(hash2(i + vec2(0,1)), f - vec2(0,1));
	float d = dot(hash2(i + vec2(1,1)), f - vec2(1,1));
	return mix(mix(a,b,u.x), mix(c,d,u.x), u.y) * 0.5 + 0.5;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = p * 2.1 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// ============================================================
// FRAGMENT
// ============================================================
void fragment() {
	vec2 uv = UV;

	// Elongar horizontalmente para nubes más alargadas
	vec2 cloud_uv = vec2(uv.x * cloud_elongation, uv.y) * cloud_scale;
	cloud_uv.x += TIME * cloud_speed;
	cloud_uv.y += TIME * cloud_speed * 0.15;

	// DOMAIN WARPING — distorsionar las UVs con otro fbm
	// Esto es lo que da formas orgánicas de nube en lugar de manchas
	vec2 warp_uv = cloud_uv + vec2(1.7, 9.2);
	vec2 warp = vec2(
		fbm(warp_uv),
		fbm(warp_uv + vec2(3.4, 2.6))
	);
	vec2 warped_uv = cloud_uv + warp * warp_strength;

	// Nube principal con UVs warpeadas
	float clouds = fbm(warped_uv);

	// Segunda capa más grande y lenta — profundidad
	vec2 cloud_uv2 = vec2(uv.x * cloud_elongation * 0.6, uv.y) * cloud_scale * 0.5;
	cloud_uv2.x += TIME * cloud_speed * 0.5;
	vec2 warp2 = vec2(fbm(cloud_uv2 + vec2(5.2, 1.3)), fbm(cloud_uv2 + vec2(1.7, 8.1)));
	float clouds2 = fbm(cloud_uv2 + warp2 * warp_strength * 0.6);

	// Mezclar capas
	float cloud_final = mix(clouds, clouds2, 0.35);

	// Mask de nube
	float cloud_mask = smoothstep(cloud_density, cloud_density + cloud_softness, cloud_final);

	// Gradiente de cielo
	vec4 sky = mix(sky_color_bottom, sky_color_top, uv.y);

	// Influencia lunar/fuente de luz
	vec2 moon_pos = vec2(moon_glow_x, moon_glow_y);
	float moon_dist = distance(uv, moon_pos);
	float moon_influence = exp(-moon_dist * 2.5) * moon_glow;

	// Color nubes — más claras cerca de la fuente de luz
	vec4 cloud_col = mix(cloud_color_dark, cloud_color_light, moon_influence + cloud_mask * 0.3);

	// Composición final
	vec4 final_color = mix(sky, cloud_col, cloud_mask);
	final_color.rgb += vec3(0.04, 0.01, 0.01) * moon_influence * (1.0 - cloud_mask * 0.5);

	COLOR = final_color;
}
