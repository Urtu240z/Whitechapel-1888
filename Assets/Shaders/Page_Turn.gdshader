shader_type canvas_item;

uniform float fold_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool fold_from_right = true;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);

void vertex() {
	float t = fold_progress;
	float w = 1.0 / TEXTURE_PIXEL_SIZE.x;
	float h = 1.0 / TEXTURE_PIXEL_SIZE.y;

	// UV normalizado del vértice (0 a 1)
	float uv_x = VERTEX.x / w;

	// Curva de doblez — seno simula la curvatura 3D
	float curve = sin(uv_x * 3.14159 * 0.5);

	if (fold_from_right) {
		// Compresión desde la derecha hacia la encuadernación (izq)
		float compress = 1.0 - t + t * curve * 0.15;
		VERTEX.x = VERTEX.x * (1.0 - t) + VERTEX.x * curve * t * 0.15;
		// Perspectiva — los vértices centrales suben ligeramente
		VERTEX.y += sin(uv_x * 3.14159) * t * h * 0.04;
	} else {
		// Compresión desde la izquierda hacia la encuadernación (der)
		float uv_x_inv = 1.0 - uv_x;
		float compress_inv = sin(uv_x_inv * 3.14159 * 0.5);
		VERTEX.x = w - (w - VERTEX.x) * (1.0 - t) - (w - VERTEX.x) * compress_inv * t * 0.15;
		VERTEX.y += sin(uv_x_inv * 3.14159) * t * h * 0.04;
	}
}

void fragment() {
	// Blur de movimiento — más fuerte cuanto más rápido se dobla
	float blur_strength = fold_progress * (1.0 - fold_progress) * 120.0;
	float blur_samples = 16.0;
	vec4 tex = vec4(0.0);
	for (float i = 0.0; i < blur_samples; i++) {
		float offset = (i / (blur_samples - 1.0) - 0.5) * blur_strength * TEXTURE_PIXEL_SIZE.x;
		tex += texture(TEXTURE, UV + vec2(offset, 0.0));
	}
	tex /= blur_samples;

	float edge = fold_from_right ? UV.x : (1.0 - UV.x);
	float shadow = pow(fold_progress, 1.5) * (1.0 - pow(edge, 0.5)) * shadow_color.a * 2.5;
	tex.rgb = mix(tex.rgb, shadow_color.rgb, shadow * fold_progress);
	float center_dark = sin(edge * 3.14159) * fold_progress * 0.3;
	tex.rgb *= (1.0 - center_dark);
	COLOR = tex;
}