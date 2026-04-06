shader_type canvas_item;

// ============================================================
// RIVER SHADER — ondulaciones y flujo para Godot 4
// Aplícalo a un Sprite2D o TextureRect del río
// ============================================================

uniform float wave_speed : hint_range(0.1, 5.0) = 1.2;
uniform float wave_strength : hint_range(0.0, 0.05) = 0.018;
uniform float wave_frequency : hint_range(1.0, 20.0) = 6.0;

uniform float ripple_speed : hint_range(0.1, 5.0) = 0.8;
uniform float ripple_strength : hint_range(0.0, 0.03) = 0.010;
uniform float ripple_frequency : hint_range(1.0, 20.0) = 12.0;

uniform float flow_speed : hint_range(0.0, 1.0) = 0.15;  // velocidad de scroll vertical
uniform float darkness : hint_range(0.0, 1.0) = 0.25;    // oscuridad en los valles

uniform vec4 water_tint : source_color = vec4(0.15, 0.18, 0.22, 1.0); // tinte azul oscuro victoriano
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float time = TIME;
	vec2 uv = UV;

	// Flujo — la textura se desplaza hacia abajo
	uv.y += time * flow_speed;

	// Onda principal — ondulación horizontal suave
	float wave = sin(uv.y * wave_frequency + time * wave_speed) * wave_strength;
	uv.x += wave;

	// Ripple secundario — ondulación más rápida y pequeña
	float ripple = sin(uv.x * ripple_frequency + time * ripple_speed) * ripple_strength;
	uv.y += ripple;

	// Sample de la textura con UVs desplazadas
	vec4 tex = texture(TEXTURE, uv);

	// Oscurecer los valles para dar profundidad
	float depth = sin(uv.y * wave_frequency + time * wave_speed) * 0.5 + 0.5;
	tex.rgb *= mix(1.0 - darkness, 1.0, depth);

	// Tinte oscuro victoriano
	tex.rgb = mix(tex.rgb, water_tint.rgb, tint_strength);

	COLOR = tex;
}
