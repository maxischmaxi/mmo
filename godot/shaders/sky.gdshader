shader_type sky;

// Sky gradient colors (set by DayNightController)
uniform vec3 sky_top_color : source_color = vec3(0.02, 0.02, 0.06);
uniform vec3 sky_horizon_color : source_color = vec3(0.05, 0.08, 0.15);
uniform vec3 ground_bottom_color : source_color = vec3(0.01, 0.01, 0.02);
uniform vec3 ground_horizon_color : source_color = vec3(0.03, 0.04, 0.06);

// Star parameters
uniform float star_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float star_visibility : hint_range(0.0, 1.0) = 1.0;

// Sun/Moon parameters - controlled directly by DayNightController
uniform float sun_disk_size : hint_range(0.0, 0.1) = 0.03;
uniform float sun_glow_size : hint_range(0.0, 0.5) = 0.15;
uniform float moon_disk_size : hint_range(0.0, 0.05) = 0.015;
uniform float moon_glow_size : hint_range(0.0, 0.2) = 0.05;

// Direct sun/moon control (set by DayNightController for accurate positioning)
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float sun_energy : hint_range(0.0, 2.0) = 0.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float moon_energy : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moon_color : source_color = vec3(0.7, 0.8, 1.0);

// Atmospheric scattering parameters
uniform float rayleigh_strength : hint_range(0.0, 2.0) = 0.5;
uniform float mie_strength : hint_range(0.0, 1.0) = 0.3;
uniform float atmosphere_density : hint_range(0.0, 2.0) = 1.0;
uniform float horizon_fade_power : hint_range(0.1, 3.0) = 1.2;

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

// Generate realistic star field
float stars(vec3 dir) {
    if (dir.y < 0.0) return 0.0;
    
    vec2 uv = dir_to_uv(dir);
    float star_value = 0.0;
    
    // Layer 1: Faint background stars
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
    
    // Layer 2: Medium stars
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
    
    // Layer 3: Bright stars
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
    
    // Layer 4: Very bright stars
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
    
    // Fade stars near horizon
    float horizon_fade = smoothstep(0.0, 0.15, dir.y);
    
    return star_value * horizon_fade;
}

// Render sun disk and glow
vec3 render_sun(vec3 dir, vec3 light_dir, float energy, vec3 light_color) {
	if (energy < 0.01) return vec3(0.0);
	
	// Angle between view direction and light direction
	float cos_angle = dot(normalize(dir), normalize(light_dir));
	float angle = acos(clamp(cos_angle, -1.0, 1.0));
	
	vec3 sun_result = vec3(0.0);
	
	// Sun disk (sharp edge) - natural brightness, not blinding
	float disk = smoothstep(sun_disk_size, sun_disk_size * 0.9, angle);
	sun_result += light_color * disk * 0.5;
	
	// Inner glow (soft halo around sun) - very subtle
	float inner_glow = smoothstep(sun_glow_size * 0.4, 0.0, angle) * (1.0 - disk);
	sun_result += light_color * inner_glow * 0.15;
	
	// Outer glow (very subtle atmospheric scattering)
	float outer_glow = smoothstep(sun_glow_size, 0.0, angle) * (1.0 - disk);
	sun_result += light_color * outer_glow * 0.05;
	
	// Reduce glow near horizon (atmospheric extinction)
	float horizon_factor = smoothstep(-0.1, 0.3, light_dir.y);
	
	// Add orange/red tint near horizon
	float horizon_tint = 1.0 - smoothstep(0.0, 0.2, light_dir.y);
	vec3 sunset_tint = mix(light_color, vec3(1.0, 0.5, 0.2), horizon_tint * 0.5);
	
	return sun_result * energy * horizon_factor * mix(vec3(1.0), sunset_tint, outer_glow);
}

// Render moon disk and glow
vec3 render_moon(vec3 dir, vec3 light_dir, float energy, vec3 light_color) {
	if (energy < 0.01) return vec3(0.0);
	
	float cos_angle = dot(normalize(dir), normalize(light_dir));
	float angle = acos(clamp(cos_angle, -1.0, 1.0));
	
	vec3 moon_result = vec3(0.0);
	
	// Moon disk - small, bright but not overwhelming
	float disk = smoothstep(moon_disk_size, moon_disk_size * 0.8, angle);
	moon_result += light_color * disk * 0.6;
	
	// Very subtle glow around moon - much smaller and dimmer than sun
	float glow = smoothstep(moon_glow_size * 0.5, 0.0, angle) * (1.0 - disk);
	moon_result += light_color * glow * 0.02;
	
	return moon_result * energy;
}

// Rayleigh scattering - blue light scatters more than red
// This creates the realistic blue sky and red sunsets
vec3 rayleigh_scatter(vec3 view_dir, vec3 light_dir, float energy) {
	if (energy < 0.01 || rayleigh_strength < 0.01) return vec3(0.0);
	
	// Rayleigh scattering coefficient (blue scatters ~5.5x more than red)
	vec3 rayleigh_coeff = vec3(0.0058, 0.0135, 0.0331) * rayleigh_strength;
	
	// Phase function for Rayleigh scattering
	float cos_theta = dot(view_dir, light_dir);
	float phase = 0.75 * (1.0 + cos_theta * cos_theta);
	
	// Height-based attenuation (less scattering when looking straight up)
	float height_factor = pow(max(0.0, view_dir.y), 0.3);
	
	// Path length through atmosphere (longer near horizon)
	float path_length = 1.0 / max(0.1, view_dir.y + 0.1);
	path_length = min(path_length, 10.0); // Clamp to prevent extreme values
	
	// Calculate scattered light
	vec3 scatter = rayleigh_coeff * phase * path_length * energy * atmosphere_density;
	
	// Apply height attenuation
	scatter *= mix(1.0, 0.3, height_factor);
	
	return scatter;
}

// Mie scattering - creates the bright halo around the sun
vec3 mie_scatter(vec3 view_dir, vec3 light_dir, float energy, vec3 light_color) {
	if (energy < 0.01 || mie_strength < 0.01) return vec3(0.0);
	
	// Mie scattering (forward scattering dominant)
	float cos_theta = dot(view_dir, light_dir);
	
	// Henyey-Greenstein phase function for forward scattering
	float g = 0.76; // Anisotropy factor (forward scattering)
	float g2 = g * g;
	float phase = (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5);
	phase *= 0.25 / PI;
	
	// Path length through atmosphere
	float path_length = 1.0 / max(0.1, view_dir.y + 0.1);
	path_length = min(path_length, 8.0);
	
	// Mie scattering is wavelength-independent (white/sun colored)
	vec3 scatter = light_color * phase * mie_strength * path_length * energy * 0.1;
	
	return scatter;
}

// Calculate atmospheric extinction (how much light is absorbed)
float atmospheric_extinction(float view_height, float path_length) {
	float optical_depth = path_length * atmosphere_density * 0.1;
	return exp(-optical_depth);
}

void sky() {
	vec3 dir = EYEDIR;
	float vertical = dir.y;
	
	vec3 sky_color;
	
	if (vertical > 0.0) {
		// Looking up - sky gradient with enhanced horizon blend
		// Use a softer power curve for more natural gradient
		float t = pow(vertical, horizon_fade_power * 0.5);
		sky_color = mix(sky_horizon_color, sky_top_color, t);
		
		// Use our direct sun uniforms for atmospheric scattering
		// Only apply when sun has energy AND is above horizon (y > 0)
		if (sun_energy > 0.01 && sun_direction.y > 0.0) {
			// Rayleigh scattering (blue sky effect) - subtle addition
			vec3 rayleigh = rayleigh_scatter(dir, sun_direction, sun_energy);
			sky_color += rayleigh * 0.5;
			
			// Mie scattering (sun haze/glow through atmosphere) - subtle
			vec3 mie = mie_scatter(dir, sun_direction, sun_energy, sun_color);
			sky_color += mie * 0.5;
			
			// Enhanced horizon glow during golden hour
			// When sun is low, add warm colors to horizon
			float sun_height = sun_direction.y;
			if (sun_height < 0.3 && sun_height > 0.0) {
				float golden_factor = 1.0 - smoothstep(0.0, 0.3, sun_height);
				float horizon_proximity = 1.0 - smoothstep(0.0, 0.4, vertical);
				vec3 golden_tint = vec3(1.0, 0.6, 0.3) * golden_factor * horizon_proximity * sun_energy * 0.2;
				sky_color += golden_tint;
			}
		}
		
		// Add stars (only when visible)
		if (star_visibility > 0.0) {
			float star_intensity = stars(dir) * star_visibility * star_brightness;
			// Slight color variation in stars (mostly white, some blue/orange tints)
			vec3 star_color_tint = vec3(0.95, 0.97, 1.0);
			sky_color += star_color_tint * star_intensity;
		}
		
		// Add sun - only render when above horizon AND has energy
		if (sun_energy > 0.01 && sun_direction.y > 0.0) {
			sky_color += render_sun(dir, sun_direction, sun_energy, sun_color);
		}
		
		// Add moon - only render when above horizon AND has energy
		if (moon_energy > 0.01 && moon_direction.y > 0.0) {
			sky_color += render_moon(dir, moon_direction, moon_energy, moon_color);
		}
		
		// Apply subtle atmospheric perspective near horizon (reduced at night)
		// Objects near horizon appear hazier/lighter during day
		float horizon_haze = 1.0 - smoothstep(0.0, 0.15, vertical);
		vec3 haze_color = sky_horizon_color * 1.1;
		// Reduce haze effect at night (when stars are visible)
		float haze_strength = 0.15 * atmosphere_density * (1.0 - star_visibility * 0.8);
		sky_color = mix(sky_color, haze_color, horizon_haze * haze_strength);
		
	} else {
		// Looking down - ground gradient with smoother blend
		float t = pow(-vertical, horizon_fade_power);
		sky_color = mix(ground_horizon_color, ground_bottom_color, t);
		
		// Add subtle atmospheric effect to ground gradient too
		float ground_haze = 1.0 - smoothstep(0.0, 0.1, -vertical);
		sky_color = mix(sky_color, ground_horizon_color, ground_haze * 0.3);
	}
	
	COLOR = sky_color;
}
