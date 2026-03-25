shader_type canvas_item;

uniform sampler2D front_texture : source_color, filter_linear_mipmap;
uniform sampler2D back_texture : source_color, filter_linear_mipmap;

// Gradiente de sombra (Negro a Transparente)
uniform sampler2D spine_shadow_gradient : source_color, filter_linear, repeat_disable;

// Intensidad global animada desde GDScript (0.0 = sin sombra, 1.0 = máxima)
uniform float shadow_intensity : hint_range(0.0, 1.0) = 0.0;

// Cuánto ocupa la sombra como máximo (0.3 = 30% del ancho de página)
uniform float max_shadow_spread : hint_range(0.0, 1.0) = 0.35;

// Suavidad del borde exterior de la sombra (mayor = más difuminado)
uniform float shadow_softness : hint_range(0.5, 8.0) = 2.5;

// Curvatura de la caída (mayor = cae más rápido cerca del lomo)
uniform float shadow_curve : hint_range(0.5, 4.0) = 1.8;

uniform bool debug_mode = false;

void fragment() {
	// 1. DETECCIÓN DE CARA
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	float face_dir = uv_dx.x * uv_dy.y - uv_dx.y * uv_dy.x;
	bool is_front = face_dir > 0.0;

	// 2. TEXTURA BASE
	vec4 base_color;
	if (is_front) {
		base_color = texture(front_texture, UV);
		if (debug_mode) base_color = vec4(0.0, 1.0, 0.0, 0.5);
	} else {
		base_color = texture(back_texture, vec2(1.0 - UV.x, UV.y));
		if (debug_mode) base_color = vec4(1.0, 0.0, 0.0, 0.5);
	}

	// 3. CÁLCULO DE SOMBRA MEJORADA
	float current_spread = max(max_shadow_spread * shadow_intensity, 0.001);

	// Ratio normalizado dentro de la zona de sombra (0 = lomo, 1 = borde de sombra)
	float ratio = UV.x / current_spread;

	// Curva de caída no lineal: más intensa cerca del lomo, suave hacia afuera
	float curved_ratio = pow(clamp(ratio, 0.0, 1.0), shadow_curve);

	// Leemos el gradiente con la ratio curvada
	float shadow_alpha = texture(spine_shadow_gradient, vec2(curved_ratio, 0.0)).a;

	// Borde suave: smoothstep en los últimos % de la zona de sombra
	float edge_fade = 1.0 - smoothstep(1.0 - (1.0 / shadow_softness), 1.0, ratio);
	shadow_alpha *= edge_fade;

	// Corte fuera del área
	if (ratio > 1.0) shadow_alpha = 0.0;

	// Intensidad global
	shadow_alpha *= shadow_intensity;

	// *** FIX CLAVE: la sombra respeta el alpha de la página ***
	// Si el pixel es transparente (borde irregular de la hoja),
	// la sombra también desaparece -> no se ve el rectángulo duro
	shadow_alpha *= base_color.a;

	// 4. APLICAR SOMBRA
	// Sombra ligeramente cálida (no negro puro) para integrarse
	// mejor con el papel amarillento del diario
	vec3 shadow_color = vec3(0.08, 0.05, 0.02);
	vec3 final_rgb = mix(base_color.rgb, shadow_color, shadow_alpha * 0.85);

	COLOR = vec4(final_rgb, base_color.a);
}
