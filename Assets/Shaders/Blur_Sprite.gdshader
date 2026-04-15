shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 24.0) = 7.0;
uniform float blur_quality : hint_range(1.0, 3.0) = 3.0;
uniform float center_preserve : hint_range(0.0, 1.0) = 0.0;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.3;
uniform vec4 tint_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);

const int DIR_COUNT = 16;
const int MAX_RINGS = 3;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;

	vec4 base_color = texture(TEXTURE, UV);
	vec4 blur_color = vec4(0.0);
	float total_weight = 0.0;

	// Mantener bastante información del centro
	float center_weight = 2.2 + center_preserve * 4.0;
	blur_color += base_color * center_weight;
	total_weight += center_weight;

	float rings = max(blur_quality, 1.0);

	for (int ring = 1; ring <= MAX_RINGS; ring++) {
		if (float(ring) > rings) {
			break;
		}

		// Radios repartidos: cercano, medio, lejano
		float ring_t = float(ring) / rings;
		float radius = blur_strength * ring_t;

		// Más peso en anillos interiores, menos en exteriores
		float ring_weight = mix(1.6, 0.55, ring_t);

		for (int i = 0; i < DIR_COUNT; i++) {
			float a = TAU * float(i) / float(DIR_COUNT);
			vec2 dir = vec2(cos(a), sin(a));

			vec2 offset = dir * px * radius;
			blur_color += texture(TEXTURE, UV + offset) * ring_weight;
			total_weight += ring_weight;
		}
	}

	vec4 color = blur_color / max(total_weight, 0.0001);

	color.rgb *= tint_color.rgb;
	color.rgb *= brightness;
	color.a *= tint_color.a;
	color.a *= opacity;

	COLOR = color;
}