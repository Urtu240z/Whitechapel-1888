shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 8.0) = 3.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.7;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 color = vec4(0.0);
    vec2 pixel_size = TEXTURE_PIXEL_SIZE;
    float samples = 0.0;

    // Blur gaussiano de 5x5
    for(float x = -2.0; x <= 2.0; x += 1.0) {
        for(float y = -2.0; y <= 2.0; y += 1.0) {
            color += texture(TEXTURE, UV + vec2(x, y) * pixel_size * blur_strength);
            samples += 1.0;
        }
    }

    color = color / samples;

    // Aplicar tonalidad (tint)
    color.rgb *= tint_color.rgb;

    // Aplicar brillo
    color.rgb *= brightness;

    // Aplicar opacidad
    color.a *= opacity;

    COLOR = color;
}