shader_type canvas_item;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float radius = 0.45;
uniform float edge_softness = 0.35;
uniform float pulse_speed = 0.4;
uniform float pulse_strength = 0.15;

void fragment() {
    vec2 uv = (UV - 0.5) * 2.0;
    float dist = length(uv);
    
    float pulse = sin(TIME * pulse_speed) * pulse_strength;
    float glow = smoothstep(radius + pulse, radius + pulse + edge_softness, dist);
    
    // ✅ Multiplica por COLOR (que incluye modulate)
    COLOR = vec4(color.rgb, (1.0 - glow) * color.a) * COLOR;
}