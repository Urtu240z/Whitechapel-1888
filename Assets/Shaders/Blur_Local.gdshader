shader_type canvas_item;
render_mode unshaded;

uniform float blur_radius : hint_range(0.0, 10.0, 0.1) = 2.0;  // qué tan fuerte el blur
uniform float blur_strength : hint_range(0.0, 1.0, 0.01) = 0.7; // mezcla con el original
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // color opcional del trazo

void fragment() {
    vec2 pixel = 1.0 / vec2(textureSize(TEXTURE, 0));
    vec4 sum = vec4(0.0);

    // Muestra 9 puntos alrededor (blur 3x3)
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 offset = vec2(float(x), float(y)) * pixel * blur_radius;
            sum += texture(TEXTURE, UV + offset);
        }
    }

    sum /= 9.0; // promedio
    vec4 original = texture(TEXTURE, UV);

    // Mezclamos el original con el difuminado
    vec4 blurred = mix(original, sum, blur_strength);

    // Aplicar color de tinte opcional
    blurred.rgb *= tint_color.rgb;

    COLOR = blurred;
}
