shader_type canvas_item;

// Star field shader for night sky
// Creates a static starfield using procedural noise

uniform float star_density : hint_range(0.0, 1.0) = 0.3;
uniform float star_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float star_size : hint_range(0.1, 3.0) = 1.0;
uniform float visibility : hint_range(0.0, 1.0) = 1.0;

// Simple hash function for pseudo-random values
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
    // Scale UV to create star grid
    vec2 grid_size = vec2(200.0, 100.0) / star_size;
    vec2 scaled_uv = UV * grid_size;
    
    // Get grid cell
    vec2 cell = floor(scaled_uv);
    vec2 cell_uv = fract(scaled_uv);
    
    // Random value for this cell
    float random = hash(cell);
    
    // Only show star if random value is below density threshold
    float star = 0.0;
    if (random < star_density) {
        // Star position within cell (centered with some randomness)
        vec2 star_pos = vec2(
            hash(cell + vec2(1.0, 2.0)),
            hash(cell + vec2(3.0, 4.0))
        ) * 0.6 + 0.2;
        
        // Distance from star center
        float dist = length(cell_uv - star_pos);
        
        // Star brightness falloff
        float star_radius = 0.05 * star_size;
        star = smoothstep(star_radius, 0.0, dist);
        
        // Vary brightness per star
        float brightness_var = hash(cell + vec2(5.0, 6.0)) * 0.5 + 0.5;
        star *= brightness_var;
    }
    
    // Apply brightness and visibility
    float final_brightness = star * star_brightness * visibility;
    
    // Output white stars with calculated alpha
    COLOR = vec4(1.0, 1.0, 1.0, final_brightness);
}
