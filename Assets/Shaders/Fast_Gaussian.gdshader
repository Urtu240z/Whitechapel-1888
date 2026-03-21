shader_type canvas_item;
uniform float blur_radius : hint_range(0.0, 10.0) = 2.0;
uniform vec2 blur_direction = vec2(1.0, 0.0);

void fragment() {
    vec4 color = vec4(0.0);
    float total = 0.0;

    for(float i = -blur_radius; i <= blur_radius; i++) {
        float weight = exp(-0.5 * (i * i) / (blur_radius * blur_radius));
        color += texture(TEXTURE, UV + i * TEXTURE_PIXEL_SIZE * blur_direction) * weight;
        total += weight;
    }

    COLOR = color / total;
}