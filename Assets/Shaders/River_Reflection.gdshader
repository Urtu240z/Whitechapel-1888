shader_type canvas_item;

// ============================================================
// RIVER REFLECTION SHADER
// Anima las reflexiones del río sin distorsionar el sprite.
// Solo afecta al brillo de las luces reflejadas.
// ============================================================

uniform float shimmer_speed : hint_range(0.1, 3.0) = 0.8;
uniform float shimmer_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float shimmer_scale : hint_range(1.0, 30.0) = 12.0;

uniform float wave_speed : hint_range(0.1, 3.0) = 0.4;
uniform float wave_amount : hint_range(0.0, 0.02) = 0.006;  // muy sutil
uniform float wave_scale : hint_range(1.0, 20.0) = 8.0;

uniform float brightness_threshold : hint_range(0.0, 1.0) = 0.3; // solo anima píxeles brillantes
uniform vec4 modulate_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 uv = UV;

	// Micro-ondulación horizontal muy sutil — solo desplaza ligeramente
	float wave = sin(uv.x * wave_scale + TIME * wave_speed) * wave_amount;
	uv.y += wave;

	vec4 tex = texture(TEXTURE, uv);

	// Calcular brillo del píxel
	float brightness = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

	// Shimmer — solo en zonas brillantes (reflexiones de luz)
	float shimmer = sin(uv.x * shimmer_scale + TIME * shimmer_speed)
				  * sin(uv.y * shimmer_scale * 0.5 + TIME * shimmer_speed * 0.7);

	// Normalizar shimmer a rango 0-1
	shimmer = shimmer * 0.5 + 0.5;

	// Solo aplicar donde hay reflexiones brillantes
	float mask = smoothstep(brightness_threshold, brightness_threshold + 0.2, brightness);
	float shimmer_final = shimmer * shimmer_intensity * mask;

    tex.rgb += shimmer_final * tex.rgb;

    // Modulate final
    COLOR = tex * modulate_color;
}
