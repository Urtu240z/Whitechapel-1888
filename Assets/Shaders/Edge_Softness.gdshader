shader_type canvas_item;

uniform float edge_softness : hint_range(0.0, 0.5) = 0.15;
uniform float edge_start : hint_range(0.0, 1.0) = 0.65;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec4 modulate_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);

	float alpha = 1.0 - smoothstep(edge_start, edge_start + edge_softness, dist);
	tex.a *= alpha;

	float gray = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	tex.rgb = mix(vec3(gray), tex.rgb, saturation);

	COLOR = tex * modulate_color;
}