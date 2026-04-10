shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 bruise_pos = vec2(0.5, 0.4);
uniform float bruise_radius : hint_range(0.0, 0.5) = 0.15;
uniform vec4 bruise_color : source_color = vec4(0.4, 0.1, 0.3, 1.0);

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	if (original.a > 0.01) {
		float dist = length(UV - bruise_pos);
		float bruise = smoothstep(bruise_radius, bruise_radius * 0.3, dist);
		bruise *= intensity;
		vec3 mixed = mix(original.rgb, bruise_color.rgb, bruise * 0.7);
		COLOR = vec4(mixed, original.a);
	} else {
		COLOR = original;
	}
}