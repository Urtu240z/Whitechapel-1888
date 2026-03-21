shader_type canvas_item;

uniform float intensity: hint_range(0.0, 1.0) = 0.5;
uniform float softness: hint_range(0.0, 1.0) = 0.45;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 center = uv - 0.5;
    float dist = length(center);
    float vignette = smoothstep(0.5, 0.5 - softness, dist * (1.0 + intensity));
    float alpha = (1.0 - vignette) * intensity;
    COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
