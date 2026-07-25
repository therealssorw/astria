shader_type spatial;
render_mode specular_toon, diffuse_lambert;

uniform vec4 water_color : source_color = vec4(0.0, 0.4, 0.6, 1.0);
uniform float wave_speed = 1.2;
uniform float wave_strength = 2;
uniform float wave_frequency = 2;

// Higher numbers make sharp stairs; lower numbers make smooth hills
uniform float terrace_sharpness = 4.0;

// Second wave octave: breaks up the repeating sin/cos grid so the sea reads
// as one body of water instead of a diagonal checkerboard. 0 = off.
uniform float detail_strength = 0.35;
uniform float detail_frequency = 0.13;

// Freeze support: the editor shows the waves paused at frozen_time (for
// cinematic shots); the running game animates with TIME as usual.
uniform bool freeze_time = false;
uniform float frozen_time = 0.0;

void vertex() {
    // World-space wave phase so separately-placed ocean tiles line up
    // seamlessly (local coords would repeat the same pattern per tile)
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float t = freeze_time ? frozen_time : TIME;
    float coord_x = world_pos.x * wave_frequency + t * wave_speed;
    float coord_z = world_pos.z * wave_frequency + t * wave_speed;
    
    // Smooth raw wave base plus a counter-moving detail octave
    float raw_wave = (sin(coord_x) + cos(coord_z)) * 0.5;
    raw_wave += sin(world_pos.x * detail_frequency - t * wave_speed * 1.7)
            * cos(world_pos.z * detail_frequency * 0.83 + t * wave_speed * 1.3)
            * detail_strength;
    
    // Terrace the wave heights: smooth transitions with flat tops
    float grid_base = floor(raw_wave);
    float fraction = fract(raw_wave);
    float smoothed_fraction = pow(fraction, terrace_sharpness);
    float terraced_wave = grid_base + smoothed_fraction;
    
    VERTEX.y += terraced_wave * wave_strength;
}

// Helper function for the fract calculation missing in standard spatial templates
float frac(float v) {
    return v - floor(v);
}

void fragment() {
    // Perfect flat-faceted triangle calculation
    vec3 x_deriv = dFdx(VERTEX);
    vec3 y_deriv = dFdy(VERTEX);
    vec3 face_normal = normalize(cross(x_deriv, y_deriv));
    
    NORMAL = face_normal;
    ALBEDO = water_color.rgb;
    ROUGHNESS = 0.2;
    SPECULAR = 0.4;
}