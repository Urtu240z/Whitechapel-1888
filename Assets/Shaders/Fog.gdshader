shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable;
uniform float noise_scale : hint_range(0.0, 10.0) = 2.0;
uniform float flatness : hint_range(0.0, 5.0) = 1.0;
uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform vec4 fog_color : source_color = vec4(0.8, 0.8, 0.9, 0.6);
uniform float fog_speed : hint_range(-5.0, 5.0) = 0.3;

void fragment() {
    // UV basado en el tiempo para animar el ruido
    vec2 uv = UV * noise_scale + vec2(TIME * fog_speed, 0.0);

    // Ruido doble para dar profundidad
    float n1 = texture(noise_tex, uv).r;
    float n2 = texture(noise_tex, uv * 0.5 + n1).r;

    // Combina ruido con altura (para que sea más denso abajo)
    float height_factor = 1.0 - UV.y * flatness;
    float alpha = n2 * height_factor * density;

    COLOR = fog_color;
    COLOR.a *= clamp(alpha, 0.0, 1.0);
}
