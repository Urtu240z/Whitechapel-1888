shader_type canvas_item;

uniform sampler2D screen_texture: hint_screen_texture, filter_linear_mipmap;
uniform float intensity: hint_range(0.0, 1.0) = 0.3;
uniform float speed: hint_range(0.0, 5.0) = 1.5;

void fragment() {
	vec2 uv = SCREEN_UV;
	float wave_x = sin(uv.y * 8.0 + TIME * speed) * intensity * 0.02;
	float wave_y = cos(uv.x * 6.0 + TIME * speed * 0.8) * intensity * 0.015;
	uv += vec2(wave_x, wave_y);
	COLOR = texture(screen_texture, uv);
}
