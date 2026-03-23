shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.0;
uniform float edge_size : hint_range(0.5, 6.0) = 0.5;
uniform float fill_strength : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	vec2 px = TEXTURE_PIXEL_SIZE * edge_size;

	float a = tex.a;
	float a_l = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	float a_r = texture(TEXTURE, UV + vec2( px.x, 0.0)).a;
	float a_u = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
	float a_d = texture(TEXTURE, UV + vec2(0.0,  px.y)).a;

	float edge = abs(a - a_l) + abs(a - a_r) + abs(a - a_u) + abs(a - a_d);
	edge = clamp(edge, 0.0, 1.0);

	vec3 final_rgb = tex.rgb;
	final_rgb += glow_color.rgb * (edge * glow_strength * 1.4);
	final_rgb += glow_color.rgb * (fill_strength * glow_strength);

	COLOR = vec4(final_rgb, tex.a);
}