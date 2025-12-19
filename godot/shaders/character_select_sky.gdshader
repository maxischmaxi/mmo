shader_type sky;

// Character Select Sky Shader
// An isolated copy of the main sky shader, specifically for the character selection screen.
// This ensures changes to the game's sky don't affect character select.

// Sky gradient colors - configured for dark, dramatic look
uniform vec3 sky_top_color : source_color = vec3(0.005, 0.005, 0.015);
uniform vec3 sky_horizon_color : source_color = vec3(0.015, 0.02, 0.035);
uniform vec3 ground_bottom_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 ground_horizon_color : source_color = vec3(0.005, 0.005, 0.01);

// Star parameters
uniform float star_brightness : hint_range(0.0, 3.0) = 1.5;
uniform float star_visibility : hint_range(0.0, 1.0) = 1.0;

// High quality hash functions for stable star positions
float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Convert 3D direction to 2D coordinates for star field
vec2 dir_to_uv(vec3 dir) {
    vec3 n = normalize(dir);
    float u = atan(n.x, n.z) / TAU + 0.5;
    float v = asin(clamp(n.y, -1.0, 1.0)) / PI + 0.5;
    return vec2(u, v);
}

// Generate realistic star field with 4 layers
float stars(vec3 dir) {
    if (dir.y < 0.0) return 0.0;
    
    vec2 uv = dir_to_uv(dir);
    float star_value = 0.0;
    
    // Layer 1: Faint background stars (most numerous)
    {
        float scale = 800.0;
        vec2 grid = floor(uv * scale);
        vec2 f = fract(uv * scale);
        float rand = hash21(grid);
        if (rand > 0.97) {
            vec2 star_pos = vec2(hash21(grid + 0.1), hash21(grid + 0.2));
            float d = length(f - star_pos);
            float brightness = hash21(grid + 0.3) * 0.3 + 0.1;
            star_value += smoothstep(0.03, 0.0, d) * brightness;
        }
    }
    
    // Layer 2: Medium stars with subtle twinkle
    {
        float scale = 400.0;
        vec2 grid = floor(uv * scale);
        vec2 f = fract(uv * scale);
        float rand = hash21(grid + vec2(17.0, 31.0));
        if (rand > 0.985) {
            vec2 star_pos = vec2(hash21(grid + 0.4), hash21(grid + 0.5));
            float d = length(f - star_pos);
            float brightness = hash21(grid + 0.6) * 0.5 + 0.3;
            float twinkle = sin(hash21(grid) * TAU + TIME * (hash21(grid + 0.7) * 2.0 + 1.0)) * 0.15 + 0.85;
            star_value += smoothstep(0.04, 0.0, d) * brightness * twinkle;
        }
    }
    
    // Layer 3: Bright stars with glow
    {
        float scale = 200.0;
        vec2 grid = floor(uv * scale);
        vec2 f = fract(uv * scale);
        float rand = hash21(grid + vec2(73.0, 41.0));
        if (rand > 0.995) {
            vec2 star_pos = vec2(hash21(grid + 0.8), hash21(grid + 0.9));
            float d = length(f - star_pos);
            float brightness = hash21(grid + 1.0) * 0.4 + 0.6;
            float twinkle = sin(hash21(grid + 1.1) * TAU + TIME * (hash21(grid + 1.2) * 1.5 + 0.5)) * 0.2 + 0.8;
            float glow = smoothstep(0.08, 0.0, d) * 0.3;
            float core = smoothstep(0.025, 0.0, d);
            star_value += (core + glow) * brightness * twinkle;
        }
    }
    
    // Layer 4: Very bright stars with prominent glow
    {
        float scale = 100.0;
        vec2 grid = floor(uv * scale);
        vec2 f = fract(uv * scale);
        float rand = hash21(grid + vec2(127.0, 59.0));
        if (rand > 0.998) {
            vec2 star_pos = vec2(hash21(grid + 1.3), hash21(grid + 1.4));
            float d = length(f - star_pos);
            float brightness = hash21(grid + 1.5) * 0.3 + 0.7;
            float twinkle = sin(hash21(grid + 1.6) * TAU + TIME * 0.8) * 0.15 + 0.85;
            float glow = smoothstep(0.12, 0.0, d) * 0.2;
            float core = smoothstep(0.02, 0.0, d);
            star_value += (core * 1.2 + glow) * brightness * twinkle;
        }
    }
    
    // Fade stars near horizon for natural look
    float horizon_fade = smoothstep(0.0, 0.15, dir.y);
    
    return star_value * horizon_fade;
}

void sky() {
    vec3 dir = EYEDIR;
    float vertical = dir.y;
    
    vec3 sky_color;
    
    if (vertical > 0.0) {
        // Looking up - sky gradient
        float t = pow(vertical, 0.5);
        sky_color = mix(sky_horizon_color, sky_top_color, t);
        
        // Add stars
        if (star_visibility > 0.0) {
            float star_intensity = stars(dir) * star_visibility * star_brightness;
            // Slight color variation for stars (white to blue-white)
            vec3 star_color = vec3(0.95, 0.97, 1.0);
            sky_color += star_color * star_intensity;
        }
    } else {
        // Looking down - ground gradient (pure black for character select)
        float t = pow(-vertical, 0.5);
        sky_color = mix(ground_horizon_color, ground_bottom_color, t);
    }
    
    COLOR = sky_color;
}
