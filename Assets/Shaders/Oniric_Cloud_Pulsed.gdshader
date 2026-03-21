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

// 🎨 Equilibrio de color
uniform vec3 shadows_tint : source_color = vec3(0.0);
uniform vec3 midtones_tint : source_color = vec3(0.0);
uniform vec3 highlights_tint : source_color = vec3(0.0);
uniform float color_balance_strength : hint_range(0.0, 1.0) = 0.5;

// ✨ Suavidad del borde
uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;

// 🌈 HUE SELECTOR
uniform float hue_shift : hint_range(0.0, 1.0) = 0.0; // 0.0–1.0 = 0°–360°

// ==========================
// 🔧 FUNCIONES AUXILIARES
// ==========================

// Convertir RGB → HSV
vec3 rgb_to_hsv(vec3 c) {
	float maxc = max(c.r, max(c.g, c.b));
	float minc = min(c.r, min(c.g, c.b));
	float delta = maxc - minc;

	float h = 0.0;
	if (delta > 0.00001) {
		if (maxc == c.r) {
			h = mod((c.g - c.b) / delta, 6.0);
		} else if (maxc == c.g) {
			h = ((c.b - c.r) / delta) + 2.0;
		} else {
			h = ((c.r - c.g) / delta) + 4.0;
		}
		h /= 6.0;
		if (h < 0.0) h += 1.0;
	}
	float s = (maxc <= 0.0) ? 0.0 : delta / maxc;
	return vec3(h, s, maxc);
}

// Convertir HSV → RGB
vec3 hsv_to_rgb(vec3 c) {
	float h = c.x * 6.0;
	float s = c.y;
	float v = c.z;

	int i = int(floor(h));
	float f = h - float(i);
	float p = v * (1.0 - s);
	float q = v * (1.0 - s * f);
	float t = v * (1.0 - s * (1.0 - f));

	vec3 out_color;
	if (i == 0) out_color = vec3(v, t, p);
	else if (i == 1) out_color = vec3(q, v, p);
	else if (i == 2) out_color = vec3(p, v, t);
	else if (i == 3) out_color = vec3(p, q, v);
	else if (i == 4) out_color = vec3(t, p, v);
	else out_color = vec3(v, p, q);

	return out_color;
}

// ==========================
// 🎨 FRAGMENT PRINCIPAL
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

	// 🌈 HUE ROTATION
	if (hue_shift != 0.0) {
		vec3 hsv = rgb_to_hsv(color.rgb);
		hsv.x = mod(hsv.x + hue_shift, 1.0);
		color.rgb = hsv_to_rgb(hsv);
	}

	// 💫 BRILLO SIMPLE
	if (enable_glow) {
		float glow_pulse = sin(TIME * glow_speed) * 0.5 + 0.5;
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

	// 🎨 Brillo / Contraste / Saturación
	color.rgb += brightness;
	color.rgb = (color.rgb - 0.5) * contrast + 0.5;
	float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(lum), color.rgb, saturation);

	// 🎨 EQUILIBRIO DE COLOR
	if (color_balance_strength > 0.0) {
		float l = dot(color.rgb, vec3(0.299, 0.587, 0.114));
		float sh = smoothstep(0.5, 0.0, l);
		float mid = clamp(1.0 - abs(l - 0.5) * 2.0, 0.0, 1.0);
		float hi = smoothstep(0.5, 1.0, l);
		vec3 shift = (shadows_tint * sh + midtones_tint * mid + highlights_tint * hi);
		color.rgb += shift * color_balance_strength;
	}

	COLOR = color;
}
