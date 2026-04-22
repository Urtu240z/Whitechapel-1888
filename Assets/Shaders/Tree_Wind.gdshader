shader_type canvas_item;

uniform float speed : hint_range(0.1, 50.0) = 1.5;
uniform float strength : hint_range(0.0, 0.05) = 0.008;
uniform vec3 target_color : source_color = vec3(0.8, 0.6, 0.1);
uniform float color_threshold : hint_range(0.0, 1.0) = 0.3;
uniform vec4 modulate_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec2 uv = UV;
    vec4 original = texture(TEXTURE, uv);
    
    // Distancia al color objetivo
    float dist = distance(original.rgb, target_color);
    
    // Si el pixel es parecido al color objetivo, lo movemos
    if (dist < color_threshold && original.a > 0.1) {
        float wave = sin(TIME * speed + UV.x * 8.0 + UV.y * 5.0) * strength;
        uv.x += wave;
        uv.y += wave * 0.5;
    }
    
    vec4 result = texture(TEXTURE, uv);
    COLOR = result * modulate_color;
}