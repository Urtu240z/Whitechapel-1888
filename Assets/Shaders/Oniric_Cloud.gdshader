shader_type canvas_item;

// ==========================
// ✨ PARÁMETROS AJUSTABLES
// ==========================

// 🌊 Ondulación
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.02;
uniform float wave_frequency : hint_range(0.0, 10.0) = 3.0;

// ✨ Pulso
uniform bool enable_pulse = true;
uniform float pulse_speed : hint_range(0.0, 5.0) = 0.8;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.15;

// 💫 Brillo (para WorldEnvironment Glow)
uniform bool enable_glow = true;
uniform float glow_speed : hint_range(0.0, 5.0) = 1.2;
uniform float glow_intensity : hint_range(0.0, 5.0) = 1.5;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 0.9, 1.0);

// 🎨 Ajustes de color
uniform float brightness : hint_range(-1.0, 1.0) = 0.0;
uniform float contrast : hint_range(0.0, 3.0) = 1.0;
uniform float saturation : hint_range(0.0, 3.0) = 1.0;

// 🎨 Equilibrio de color (Color Balance)
uniform vec3 shadows_tint : source_color = vec3(0.0, 0.0, 0.0);     // Tonos oscuros
uniform vec3 midtones_tint : source_color = vec3(0.0, 0.0, 0.0);    // Tonos medios
uniform vec3 highlights_tint : source_color = vec3(0.0, 0.0, 0.0);  // Tonos claros
uniform float color_balance_strength : hint_range(0.0, 1.0) = 0.5;

// ✨ Suavidad del borde
uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;

// ==========================
// FUNCIÓN PRINCIPAL
// ==========================

void fragment() {
	float time = TIME * wave_speed;
	vec2 uv = UV;
	
	// 🌊 Ondulación
	float wave_x = sin(uv.y * wave_frequency + time) * wave_amplitude;
	float wave_y = cos(uv.x * wave_frequency * 0.7 + time * 0.8) * wave_amplitude * 0.5;
	vec2 distorted_uv = uv + vec2(wave_x, wave_y);
	
	// Color base
	vec4 color = texture(TEXTURE, distorted_uv);
	
	// 💫 BRILLO SIMPLE (activa WorldEnvironment Glow con valores HDR)
	if (enable_glow) {
		float glow_pulse = sin(TIME * glow_speed) * 0.5 + 0.5; // 0.0 a 1.0
		vec3 emission = glow_color.rgb * glow_pulse * glow_intensity;
		color.rgb += emission * color.a;
	}
	
	// ✨ PULSO DE TRANSPARENCIA
	if (enable_pulse) {
		float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
		float pulse_amount = 1.0 - pulse_intensity + (pulse * pulse_intensity);
		color.a *= pulse_amount;
	}
	
	// ✨ Suavidad en bordes
	if (edge_softness > 0.0) {
		float edge_fade = 1.0;
		float border = 0.1;
		
		if (UV.x < border) edge_fade *= smoothstep(0.0, border, UV.x);
		if (UV.x > 1.0 - border) edge_fade *= smoothstep(1.0, 1.0 - border, UV.x);
		if (UV.y < border) edge_fade *= smoothstep(0.0, border, UV.y);
		if (UV.y > 1.0 - border) edge_fade *= smoothstep(1.0, 1.0 - border, UV.y);
		
		color.a *= mix(1.0, edge_fade, edge_softness);
	}
	
	// 🎨 AJUSTES DE COLOR (Brillo, Contraste, Saturación)
	
	// Brillo
	if (brightness != 0.0) {
		color.rgb += brightness;
	}
	
	// Contraste
	if (contrast != 1.0) {
		color.rgb = (color.rgb - 0.5) * contrast + 0.5;
	}
	
	// Saturación
	if (saturation != 1.0) {
		// Calcular luminancia (escala de grises)
		float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 gray = vec3(luminance);
		// Mezclar entre gris y color original según saturación
		color.rgb = mix(gray, color.rgb, saturation);
	}
	
	// 🎨 EQUILIBRIO DE COLOR POR TONOS (como Photoshop)
	if (color_balance_strength > 0.0) {
		// Calcular luminancia para determinar si es sombra/medio/luz
		float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
		
		// Máscaras suaves para cada rango tonal
		// Sombras: afecta más a los tonos oscuros (0.0-0.4)
		float shadow_mask = smoothstep(0.5, 0.0, lum);
		
		// Medios: afecta al rango medio (0.3-0.7)
		float midtone_mask = 1.0 - abs(lum - 0.5) * 2.0;
		midtone_mask = clamp(midtone_mask, 0.0, 1.0);
		
		// Luces: afecta más a los tonos claros (0.6-1.0)
		float highlight_mask = smoothstep(0.5, 1.0, lum);
		
		// Aplicar tintes a cada rango
		vec3 color_shift = vec3(0.0);
		color_shift += shadows_tint * shadow_mask;
		color_shift += midtones_tint * midtone_mask;
		color_shift += highlights_tint * highlight_mask;
		
		// Aplicar con fuerza ajustable
		color.rgb += color_shift * color_balance_strength;
	}
	
	COLOR = color;
}