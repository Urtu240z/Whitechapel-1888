shader_type canvas_item;

// === Colores base ===
uniform vec4 paint_color = vec4(0.9, 0.6, 0.3, 1.0); // @hint_color
uniform vec4 wet_light_color = vec4(1.0, 0.95, 0.8, 1.0); // @hint_color
uniform vec4 shadow_color = vec4(0.2, 0.1, 0.05, 1.0); // @hint_color

// === Texturas ===
uniform sampler2D brush_tex;
uniform sampler2D wet_mask;

// === Parámetros ===
uniform float brush_scale = 3.0;
uniform float brush_strength = 0.6;
uniform float wet_intensity = 0.6;
uniform float wet_speed = 0.4;
uniform float flow_amount = 0.05;
uniform float time_speed = 1.0;

// === Ruido procedural ===
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// === Función principal ===
void fragment() {
	vec2 uv = UV;

	// Textura de brocha / lienzo
	vec2 brush_uv = uv * brush_scale;
	float brush_pattern = texture(brush_tex, brush_uv).r;

	// Ruido procedural dinámico
	float t = TIME * time_speed;
	float flow = noise(uv * 5.0 + vec2(0.0, t * wet_speed)) * flow_amount;
	uv.y += flow;

	// Mapa de humedad (si no hay textura, usa ruido)
	float wet = 0.0;
	vec4 wet_tex = texture(wet_mask, uv);
	if (wet_tex.a > 0.0 || wet_tex.r > 0.0) {
		wet = wet_tex.r;
	} else {
		wet = smoothstep(0.3, 0.7, noise(uv * 2.5 + vec2(t * 0.2, 0.0)));
	}

	// Base de pintura
	vec3 color = paint_color.rgb;
	color += (brush_pattern - 0.5) * brush_strength;

	// Oscurecer zonas "secas"
	color = mix(shadow_color.rgb, color, 0.8);

	// Brillo tipo “húmedo”
	float highlight = sin((uv.x + uv.y + t * wet_speed) * 10.0) * 0.5 + 0.5;
	vec3 wet_highlight = mix(color, wet_light_color.rgb, wet * highlight * wet_intensity);

	COLOR = vec4(wet_highlight, 1.0);
}
