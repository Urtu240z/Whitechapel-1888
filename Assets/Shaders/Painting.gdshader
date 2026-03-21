shader_type canvas_item;

uniform sampler2D main_tex;   // textura principal (imagen a la que se aplica el efecto)
uniform sampler2D noise_tex;  // textura de ruido

uniform float iterations: hint_range(1.0, 50.0, 1.0) = 10.0; // @hint_range(1.0, 50.0, 1.0)
uniform float shift: hint_range(0.0, 1.0, 0.01) = 0.0;       // @hint_range(0.0, 1.0, 0.01)
uniform float rotation: hint_range(0.0, 2.0, 0.01) = 1.0;    // @hint_range(0.0, 2.0, 0.01)
uniform float sharpness: hint_range(1.0, 10.0, 0.01) = 2.0;   // @hint_range(1.0, 10.0, 0.01)

mat2 rotate(float a) {
	float sa = sin(a);
	float ca = cos(a);
	return mat2(vec2(ca, sa), vec2(-sa, ca));
}

void fragment() {
	vec2 uv = UV;
	vec2 resolution = 1.0 / TEXTURE_PIXEL_SIZE;
	float aspect_ratio = resolution.x / resolution.y; 
	vec3 color = vec3(0.0);

	float noise = pow(texture(noise_tex, uv).r, sharpness);

	for (float i = 0.0; i < iterations; i++) {
		vec2 offset = vec2(1.0 / aspect_ratio, 0.0) * rotate(i * rotation);
		offset *= (1.0 + i * 0.005) * shift * 0.1;
		color += texture(main_tex, uv + noise * offset).rgb;
	}

	color /= iterations;
	COLOR = vec4(color, 1.0);
}
