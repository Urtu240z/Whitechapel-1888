shader_type canvas_item;

uniform sampler2D main_tex;
uniform sampler2D noise_tex;

// --- Parámetros base del efecto ---
uniform float iterations : hint_range(1.0, 50.0, 1.0) = 10.0;
uniform float shift : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float rotation_speed = 1.0;
uniform float smoothness = 3.0;
uniform bool smooth_enabled = true;

uniform float rotation_min = 0.01;
uniform float rotation_max = 0.20;
uniform float sharpness : hint_range(1.0, 10.0, 0.01) = 2.0;

// --- Controles de color ---
uniform float hue_shift : hint_range(-180.0, 180.0, 1.0) = 0.0;   // grados
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float brightness : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float contrast : hint_range(0.0, 2.0, 0.01) = 1.0;

// --- Equilibrio de color (sin alpha, mezcla suave) ---
uniform vec3 shadows_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 midtones_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 highlights_color : source_color = vec3(1.0, 1.0, 1.0);

mat2 rotate(float a) {
	float sa = sin(a);
	float ca = cos(a);
	return mat2(vec2(ca, sa), vec2(-sa, ca));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Conversión RGB <-> HSL
vec3 rgb_to_hsl(vec3 c) {
	float maxc = max(c.r, max(c.g, c.b));
	float minc = min(c.r, min(c.g, c.b));
	float h = 0.0;
	float s = 0.0;
	float l = (maxc + minc) * 0.5;

	if (maxc != minc) {
		float d = maxc - minc;
		s = (l > 0.5) ? d / (2.0 - maxc - minc) : d / (maxc + minc);
		if (maxc == c.r) h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
		else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
		else h = (c.r - c.g) / d + 4.0;
		h /= 6.0;
	}
	return vec3(h, s, l);
}

float hue_to_rgb(float p, float q, float t) {
	if (t < 0.0) t += 1.0;
	if (t > 1.0) t -= 1.0;
	if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
	if (t < 1.0/2.0) return q;
	if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
	return p;
}

vec3 hsl_to_rgb(vec3 hsl) {
	float h = hsl.x;
	float s = hsl.y;
	float l = hsl.z;
	float r, g, b;
	if (s == 0.0) {
		r = g = b = l;
	} else {
		float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
		float p = 2.0 * l - q;
		r = hue_to_rgb(p, q, h + 1.0/3.0);
		g = hue_to_rgb(p, q, h);
		b = hue_to_rgb(p, q, h - 1.0/3.0);
	}
	return vec3(r, g, b);
}

void fragment() {
	vec2 uv = UV;
	vec2 resolution = 1.0 / TEXTURE_PIXEL_SIZE;
	float aspect_ratio = resolution.x / resolution.y;
	vec3 color = vec3(0.0);

	float noise = pow(texture(noise_tex, uv).r, sharpness);

	// === ROTATION (suave/brusco) ===
	float t = TIME * rotation_speed;
	float base = floor(t);
	float frac = fract(t);

	float rand_curr = hash(vec2(base, base * 3.17));
	float rand_next = hash(vec2(base + 1.0, (base + 1.0) * 3.17));

	float val_a = mix(rotation_min, rotation_max, rand_curr);
	float val_b = mix(rotation_min, rotation_max, rand_next);

	float rotation_anim;

	if (smooth_enabled) {
		float interp = smoothstep(0.0, 1.0, pow(frac, 1.0 / smoothness));
		rotation_anim = mix(val_a, val_b, interp);
	} else {
		rotation_anim = val_a;
	}

	float rot = rotation_anim * 4.0;

	for (float i = 0.0; i < iterations; i++) {
		vec2 offset = vec2(1.0 / aspect_ratio, 0.0) * rotate(i * rot);
		offset *= (1.0 + i * 0.005) * shift * 0.1;
		color += texture(main_tex, uv + noise * offset).rgb;
	}
	color /= iterations;

	// === Postprocesado de color ===

	// HSL: Hue + Saturation
	vec3 hsl = rgb_to_hsl(color);
	hsl.x = mod(hsl.x + hue_shift / 360.0, 1.0);
	hsl.y *= saturation;
	color = hsl_to_rgb(hsl);

	// Brillo + Contraste
	color = (color - 0.5) * contrast + 0.5 + brightness;

	// Equilibrio de color suave
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 balance = mix(
		mix(shadows_color, midtones_color, smoothstep(0.0, 0.5, luma)),
		highlights_color,
		smoothstep(0.5, 1.0, luma)
	);
	color *= balance;

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
