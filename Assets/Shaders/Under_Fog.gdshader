shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 fog_color : source_color = vec4(0.7, 0.7, 0.8, 1.0);
uniform vec2 speed = vec2(0.03, 0.01);
uniform float density : hint_range(0.0, 2.0) = 0.8;

// Nuevos controles para los bordes
uniform float top_feathering : hint_range(0.0, 0.5) = 0.15;
uniform float bottom_feathering : hint_range(0.0, 0.5) = 0.15;

void fragment() {
    // Movimiento del ruido
    vec2 uv1 = UV + TIME * speed;
    vec2 uv2 = UV - TIME * speed * 0.6;
    
    float noise1 = texture(noise_tex, uv1).r;
    float noise2 = texture(noise_tex, uv2).r;
    float final_noise = (noise1 + noise2) / 2.0;
    
    // --- LÓGICA DE SUAVIZADO ---
    // smoothstep crea una transición suave entre dos valores
    // Suavizado superior (de 0.0 a top_feathering)
    float top_mask = smoothstep(0.0, top_feathering, UV.y);
    
    // Suavizado inferior (de 1.0 a 1.0 - bottom_feathering)
    float bottom_mask = smoothstep(1.0, 1.0 - bottom_feathering, UV.y);
    
    // Combinamos ambas máscaras
    float edge_mask = top_mask * bottom_mask;
    
    // Aplicamos todo al canal Alpha
    COLOR = fog_color;
    COLOR.a = final_noise * density * edge_mask;
}