shader_type canvas_item;

uniform sampler2D screen_texture: hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount: hint_range(0.0, 4.0) = 2.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col = vec4(0.0);
	float total = 0.0;

	for (float x = -2.0; x <= 2.0; x += 1.0) {
		for (float y = -2.0; y <= 2.0; y += 1.0) {
			vec2 offset = vec2(x, y) * blur_amount * 0.001;
			col += texture(screen_texture, uv + offset);
			total += 1.0;
		}
	}

	COLOR = col / total;
}
