shader_type canvas_item;

uniform float red_tint = 0.3;   // 0.0 - 1.0
uniform float saturation = 0.8; // <1 desatura
uniform float contrast = 1.2;   // >1 aumenta contraste

void fragment() {
	vec4 color = texture(TEXTURE, UV);

	// Convertir a gris
	float gray = dot(color.rgb, vec3(0.3, 0.59, 0.11));
	color.rgb = mix(vec3(gray), color.rgb, saturation);

	// Tinte rojizo
	color.r += red_tint * 0.5;
	color.g *= 0.85;
	color.b *= 0.7;

	// Contraste
	color.rgb = ((color.rgb - 0.5) * contrast) + 0.5;

	COLOR = color;
}
