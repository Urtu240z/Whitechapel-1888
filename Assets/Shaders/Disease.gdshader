shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 screen_color = texture(SCREEN_TEXTURE, uv);

	// Distancia desde el centro para la viñeta
	vec2 center = uv - vec2(0.5, 0.5);
	float dist = length(center) * 1.8;
	dist = clamp(dist, 0.0, 1.0);

	// Viñeta agresiva que se cierra bastante hacia el centro
	float vignette = smoothstep(0.1, 1.0, dist * intensity);

	// Tinte verdoso-amarillento más intenso
	vec3 disease_tint = vec3(0.5, 0.7, 0.15);

	// Desaturar ligeramente la imagen (aspecto enfermizo)
	float gray = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(screen_color.rgb, vec3(gray), intensity * 0.4);

	// Mezclar tinte con imagen desaturada — más agresivo
	vec3 tinted = mix(desaturated, disease_tint, intensity * 0.45);

	// Viñeta verde oscura opresiva
	vec3 final_color = mix(tinted, vec3(0.05, 0.12, 0.02), vignette);

	// Pulso sutil — la imagen "late" levemente con la enfermedad
	float pulse = 1.0 + sin(TIME * 1.5) * intensity * 0.04;
	final_color *= pulse;

	COLOR = vec4(final_color, 1.0);
}