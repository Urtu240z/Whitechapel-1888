shader_type canvas_item;

uniform float blur_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int samples : hint_range(2, 16) = 8;
uniform float blur_spread : hint_range(0.0, 0.05) = 0.018;

uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	vec4 blurred = vec4(0.0);
	float total_weight = 0.0;
	float spread = blur_spread * blur_intensity;

	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1);
		float offset = (t - 0.5) * spread;
		float weight = max(1.0 - abs(t - 0.5) * 1.2, 0.1);

		vec2 uv_offset = UV + vec2(offset, 0.0);
		blurred += texture(TEXTURE, uv_offset) * weight;
		total_weight += weight;
	}
	blurred /= total_weight;

	float edge_fade = smoothstep(0.0, spread * 2.0, UV.x)
					* smoothstep(1.0, 1.0 - spread * 2.0, UV.x);
	blurred.a *= mix(1.0, edge_fade, blur_intensity * 0.4);

	vec4 result = mix(original, blurred, blur_intensity);

	// Brillo
	result.rgb *= brightness;

	// Contraste
	result.rgb = (result.rgb - 0.5) * contrast + 0.5;

	// Saturación
	float luma = dot(result.rgb, vec3(0.299, 0.587, 0.114));
	result.rgb = mix(vec3(luma), result.rgb, saturation);

	result.a = original.a;
	COLOR = clamp(result, 0.0, 1.0);
}
