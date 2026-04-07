shader_type canvas_item;

// ============================================================
// VICTORIAN NIGHT CLOUDS SHADER
// Nubes procedurales oscuras para cielo nocturno.
// Aplícalo a un ColorRect o Sprite2D de fondo.
// ============================================================

uniform float cloud_speed : hint_range(0.0, 0.5) = 0.04;
uniform float cloud_scale : hint_range(0.5, 8.0) = 2.8;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_softness : hint_range(0.0, 1.0) = 0.45;

uniform vec4 sky_color_top : source_color = vec4(0.03, 0.03, 0.06, 1.0);    // negro azulado
uniform vec4 sky_color_bottom : source_color = vec4(0.06, 0.05, 0.08, 1.0); // negro violáceo
uniform vec4 cloud_color_dark : source_color = vec4(0.08, 0.08, 0.12, 1.0); // nubes oscuras
uniform vec4 cloud_color_light : source_color = vec4(0.22, 0.20, 0.28, 1.0); // bordes de nube con algo de luna

uniform float moon_glow : hint_range(0.0, 1.0) = 0.3; // claridad luna en bordes de nube
uniform float moon_glow_x : hint_range(0.0, 1.0) = 0.75; // posición X de la luna
uniform float moon_glow_y : hint_range(0.0, 1.0) = 0.25; // posición Y de la luna

// ============================================================
// FUNCIONES DE RUIDO
// ============================================================

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

// FBM — ruido fractal para nubes naturales
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.1;
	}
	return value;
}

// ============================================================
// FRAGMENT
// ============================================================

void fragment() {
	vec2 uv = UV;

	// Gradiente vertical del cielo
	vec4 sky = mix(sky_color_bottom, sky_color_top, uv.y);

	// UVs animadas para movimiento de nubes
	vec2 cloud_uv = uv * cloud_scale;
	cloud_uv.x += TIME * cloud_speed;
	cloud_uv.y += TIME * cloud_speed * 0.3; // más lento vertical

	// Segunda capa de nubes más lenta y grande — profundidad
	vec2 cloud_uv2 = uv * cloud_scale * 0.55;
	cloud_uv2.x += TIME * cloud_speed * 0.6;

	// Generar nubes con FBM
	float clouds1 = fbm(cloud_uv);
	float clouds2 = fbm(cloud_uv2);
	float clouds = mix(clouds1, clouds2, 0.4);

	// Aplicar densidad y suavidad
	float cloud_mask = smoothstep(cloud_density - cloud_softness, cloud_density + cloud_softness, clouds);

	// Brillo de luna en los bordes de las nubes
	vec2 moon_pos = vec2(moon_glow_x, moon_glow_y);
	float moon_dist = distance(uv, moon_pos);
	float moon_influence = exp(-moon_dist * 3.5) * moon_glow;

	// Color de las nubes con influencia lunar
	vec4 cloud_col = mix(cloud_color_dark, cloud_color_light, moon_influence * cloud_mask);

	// Composición final
	vec4 final_color = mix(sky, cloud_col, cloud_mask);

	// Añadir un sutil toque de luz de luna en el cielo despejado
	final_color.rgb += vec3(0.03, 0.03, 0.05) * moon_influence * (1.0 - cloud_mask);

	COLOR = final_color;
}
