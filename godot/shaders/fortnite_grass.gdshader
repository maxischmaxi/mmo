// Fortnite-Style Grass Shader
// Stylized, cartoon-like grass with subtle wind animation
// Designed to match the Fortnite aesthetic with vibrant colors and soft cel-shading

shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, vertex_lighting;

// ============================================================================
// COLOR SETTINGS - Vibrant Fortnite-style colors
// ============================================================================

// Base color (bottom of grass blade) - darker, richer green
uniform vec3 base_color : source_color = vec3(0.18, 0.45, 0.12);
// Tip color (top of grass blade) - brighter, more yellow-green
uniform vec3 tip_color : source_color = vec3(0.45, 0.78, 0.25);
// Highlight color for cartoon effect
uniform vec3 highlight_color : source_color = vec3(0.65, 0.92, 0.45);

// Color variation to make grass patches look more natural
uniform float color_variation : hint_range(0.0, 0.3) = 0.1;
// How much of the blade uses the base color (0.3 = bottom 30%)
uniform float base_color_height : hint_range(0.0, 0.5) = 0.25;

// ============================================================================
// WIND ANIMATION SETTINGS - Subtle, natural movement
// ============================================================================

// Overall wind strength (keep low for subtle effect)
uniform float wind_strength : hint_range(0.0, 0.3) = 0.08;
// Primary wind wave speed
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;
// Secondary wind wave speed (for variation)
uniform float wind_speed_secondary : hint_range(0.0, 3.0) = 2.5;
// Direction of wind (normalized internally)
uniform vec2 wind_direction = vec2(1.0, 0.3);
// Scale of wind waves (larger = bigger waves across terrain)
uniform float wind_scale : hint_range(0.01, 0.5) = 0.15;

// ============================================================================
// APPEARANCE SETTINGS
// ============================================================================

// How sharp the cel-shading transitions are (higher = more cartoon)
uniform float toon_sharpness : hint_range(1.0, 10.0) = 3.0;
// Number of shading bands for cel-shading effect
uniform float toon_bands : hint_range(2.0, 8.0) = 4.0;
// Minimum brightness (prevents completely dark grass)
uniform float ambient_light : hint_range(0.0, 0.5) = 0.35;
// Rim lighting strength for cartoon pop
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
// Translucency - light passing through grass blades
uniform float translucency : hint_range(0.0, 1.0) = 0.25;

// Alpha cutoff for grass blade shape (if using texture)
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.1;
// Optional grass blade texture (can be white for solid blades)
uniform sampler2D grass_texture : hint_default_white;

// ============================================================================
// VARYINGS
// ============================================================================

varying vec3 world_position;
varying float height_factor;
varying float color_noise;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// Simple hash for color variation
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise for wind
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ============================================================================
// VERTEX SHADER - Wind Animation
// ============================================================================

void vertex() {
	// Get world position for wind calculation
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Height factor from UV.y (0 at base, 1 at tip)
	// This ensures only the top of the grass moves
	height_factor = UV.y;
	
	// Generate color variation based on world position (per-blade)
	// Use the instance position for variation
	vec2 blade_id = floor(world_position.xz * 0.5);
	color_noise = hash(blade_id) * 2.0 - 1.0; // -1 to 1 range
	
	// ========================================================================
	// WIND CALCULATION
	// ========================================================================
	
	// Normalize wind direction
	vec2 wind_dir = normalize(wind_direction);
	
	// Primary wind wave (large, slow movements)
	float wind_phase_1 = dot(world_position.xz, wind_dir) * wind_scale;
	float wind_wave_1 = sin(TIME * wind_speed + wind_phase_1);
	
	// Secondary wind wave (smaller, faster for detail)
	float wind_phase_2 = dot(world_position.xz, wind_dir.yx) * wind_scale * 2.0;
	float wind_wave_2 = sin(TIME * wind_speed_secondary + wind_phase_2) * 0.3;
	
	// Add subtle noise-based variation for natural look
	float wind_noise = noise(world_position.xz * wind_scale + TIME * 0.3) * 0.2;
	
	// Combine wind effects
	float wind_offset = (wind_wave_1 + wind_wave_2 + wind_noise) * wind_strength;
	
	// Apply wind only to upper parts of grass (squared for more natural bend)
	float bend_factor = height_factor * height_factor;
	
	// Displace vertex
	VERTEX.x += wind_offset * wind_dir.x * bend_factor;
	VERTEX.z += wind_offset * wind_dir.y * bend_factor;
	
	// Slight vertical compression when bending (grass doesn't stretch)
	VERTEX.y -= abs(wind_offset) * bend_factor * 0.1;
}

// ============================================================================
// FRAGMENT SHADER - Stylized Coloring
// ============================================================================

void fragment() {
	// Sample texture for alpha (optional grass blade shape)
	vec4 tex = texture(grass_texture, UV);
	
	// Alpha cutoff for blade shape
	if (tex.a < alpha_cutoff) {
		discard;
	}
	
	// ========================================================================
	// COLOR GRADIENT
	// ========================================================================
	
	// Create gradient from base to tip
	// Use smoothstep for nicer transition
	float gradient = smoothstep(0.0, base_color_height, height_factor);
	gradient = smoothstep(0.0, 1.0, gradient); // Extra smoothing
	
	// Mix base and tip colors
	vec3 grass_color = mix(base_color, tip_color, gradient);
	
	// Add highlight at the very tip
	float tip_highlight = smoothstep(0.7, 1.0, height_factor);
	grass_color = mix(grass_color, highlight_color, tip_highlight * 0.3);
	
	// Apply color variation per blade
	grass_color += vec3(color_noise * color_variation);
	
	// ========================================================================
	// OUTPUT
	// ========================================================================
	
	ALBEDO = grass_color * tex.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
	METALLIC = 0.0;
	
	// Store height factor for lighting
	// We'll use AO channel to pass data to light function
	AO = height_factor;
	AO_LIGHT_AFFECT = 0.0; // Don't actually use it as AO
}

// ============================================================================
// LIGHT SHADER - Cel-Shading / Toon Lighting
// ============================================================================

void light() {
	// Get normal and light direction
	float NdotL = dot(NORMAL, LIGHT);
	
	// ========================================================================
	// CEL-SHADING
	// ========================================================================
	
	// Quantize lighting into bands for cartoon effect
	float lit = (NdotL + 1.0) * 0.5; // Remap to 0-1
	lit = pow(lit, 1.0 / toon_sharpness); // Adjust contrast
	
	// Quantize into discrete bands
	float quantized = floor(lit * toon_bands + 0.5) / toon_bands;
	quantized = max(quantized, ambient_light);
	
	// ========================================================================
	// TRANSLUCENCY (Back-lighting through grass)
	// ========================================================================
	
	// When light is behind the grass, some passes through
	float backlight = max(0.0, -NdotL);
	float translucent = backlight * translucency * AO; // More at tips (using height from AO)
	
	// ========================================================================
	// RIM LIGHTING
	// ========================================================================
	
	// Add rim light for cartoon pop (light at edges)
	float NdotV = dot(NORMAL, VIEW);
	float rim = 1.0 - max(0.0, NdotV);
	rim = pow(rim, 2.0) * rim_strength;
	
	// Only show rim when facing light
	rim *= max(0.0, NdotL * 0.5 + 0.5);
	
	// ========================================================================
	// FINAL LIGHTING
	// ========================================================================
	
	// Combine all lighting components
	vec3 diffuse = ALBEDO * LIGHT_COLOR * quantized * ATTENUATION;
	vec3 translucent_light = ALBEDO * LIGHT_COLOR * translucent * ATTENUATION * 0.5;
	vec3 rim_light = ALBEDO * LIGHT_COLOR * rim * ATTENUATION * 0.3;
	
	DIFFUSE_LIGHT += diffuse + translucent_light + rim_light;
}
