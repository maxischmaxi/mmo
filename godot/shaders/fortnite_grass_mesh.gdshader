// Fortnite-Style Grass Mesh Shader for Terrain3D Particle System
// This shader renders the grass blades with stylized cartoon/cel-shading
// Works with the Terrain3D GPU particle system for placement

shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, blend_mix;

// ============================================================================
// COLOR SETTINGS - Vibrant Fortnite-style colors
// ============================================================================

group_uniforms colors;
// Base color (bottom of grass blade) - darker, richer green
uniform vec3 base_color : source_color = vec3(0.18, 0.45, 0.12);
// Tip color (top of grass blade) - brighter, more yellow-green  
uniform vec3 tip_color : source_color = vec3(0.45, 0.78, 0.25);
// Highlight color for cartoon effect at tips
uniform vec3 highlight_color : source_color = vec3(0.65, 0.92, 0.45);
// Color variation strength (per-instance randomness)
uniform float color_variation : hint_range(0.0, 0.3) = 0.12;
// How much of the blade uses base color (0.3 = bottom 30%)
uniform float base_color_height : hint_range(0.0, 0.5) = 0.25;

// ============================================================================
// WIND SETTINGS - Subtle animation
// ============================================================================

group_uniforms wind;
// Wind direction (from particle system, but can be overridden)
uniform vec2 wind_direction = vec2(1.0, 0.3);
// Additional subtle sway speed
uniform float sway_speed : hint_range(0.0, 4.0) = 1.5;
// Sway amount (very subtle)
uniform float sway_amount : hint_range(0.0, 0.3) = 0.05;

// ============================================================================
// TOON SHADING SETTINGS
// ============================================================================

group_uniforms toon_shading;
// Number of shading bands for cel-shading effect
uniform float toon_bands : hint_range(2.0, 8.0) = 4.0;
// Minimum brightness (ambient)
uniform float ambient_light : hint_range(0.0, 0.6) = 0.4;
// Rim lighting strength for cartoon pop
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;
// Translucency - light passing through grass
uniform float translucency : hint_range(0.0, 1.0) = 0.2;

// ============================================================================
// VARYINGS - Data passed from vertex to fragment
// ============================================================================

varying float v_height_factor;
varying float v_wind_force;
varying vec2 v_random;
varying vec3 v_color_tint;

// ============================================================================
// VERTEX SHADER
// ============================================================================

void vertex() {
	// Get height factor from vertex Y (normalized 0-1 from mesh)
	// Assumes grass mesh has Y from 0 (base) to ~1 (tip)
	// The +0.55 offset is for the ribbon mesh used by Terrain3D
	v_height_factor = clamp((VERTEX.y + 0.55), 0.0, 1.0);
	float height_squared = v_height_factor * v_height_factor;
	
	// Pinch the top of ribbon mesh (like original Terrain3D grass)
	VERTEX.xz *= (1.0 - height_squared * 0.8);
	
	// Get per-instance random values from particle system
	v_random = INSTANCE_CUSTOM.rg;
	
	// World space vertex
	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Get wind force from particle process shader (stored in INSTANCE_CUSTOM[2])
	float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	float wind_force = INSTANCE_CUSTOM[2] * height_squared * scale;
	
	// Add subtle lateral wobble for more natural look
	float wobble_phase = v_random.x * TAU + v_random.y * 3.14;
	float lateral_wobble = sin(TIME * sway_speed + wobble_phase) * sway_amount * (1.0 - wind_force * 0.5);
	
	// Apply wind movement
	vec2 direction = normalize(wind_direction);
	w_vertex.xz -= (vec2(-direction.y, direction.x) * lateral_wobble + direction * wind_force) * height_squared;
	
	// Flatten grass when wind is strong
	w_vertex.y -= wind_force * height_squared * 0.3;
	
	// Store wind force for fragment shader
	v_wind_force = wind_force;
	
	// Calculate color tint from terrain color map (passed through COLOR)
	v_color_tint = COLOR.rgb;
	
	// Transform to view space
	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

void fragment() {
	// ========================================================================
	// COLOR GRADIENT (Fortnite style - vibrant gradients)
	// ========================================================================
	
	// Create smooth gradient from base to tip
	float gradient = smoothstep(0.0, base_color_height, v_height_factor);
	gradient = smoothstep(0.0, 1.0, gradient);
	
	// Mix base and tip colors
	vec3 grass_color = mix(base_color, tip_color, gradient);
	
	// Add highlight at the very tip
	float tip_highlight = smoothstep(0.75, 1.0, v_height_factor);
	grass_color = mix(grass_color, highlight_color, tip_highlight * 0.35);
	
	// Per-instance color variation for natural look
	float variation = (v_random.r + v_random.g - 1.0) * color_variation;
	grass_color += vec3(variation * 0.5, variation, variation * 0.3);
	
	// Apply terrain color map tint (subtle)
	grass_color *= mix(vec3(1.0), v_color_tint, 0.3);
	
	// Brighten tips slightly based on height
	grass_color *= 1.0 + v_height_factor * 0.15;
	
	// ========================================================================
	// OUTPUT
	// ========================================================================
	
	ALBEDO = grass_color;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
	METALLIC = 0.0;
	
	// Enable backlight for translucency effect
	BACKLIGHT = vec3(translucency * 0.5);
	
	// Store height for light function
	AO = v_height_factor;
	AO_LIGHT_AFFECT = 0.0;
}

// ============================================================================
// LIGHT SHADER - Cel-Shading / Toon Lighting
// ============================================================================

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	
	// ========================================================================
	// CEL-SHADING (Fortnite cartoon style)
	// ========================================================================
	
	// Remap lighting to 0-1 range
	float lit = (NdotL + 1.0) * 0.5;
	
	// Quantize into discrete bands for cartoon effect
	float quantized = floor(lit * toon_bands + 0.5) / toon_bands;
	quantized = max(quantized, ambient_light);
	
	// ========================================================================
	// TRANSLUCENCY (subsurface scattering simulation)
	// ========================================================================
	
	// Light passing through from behind
	float backlight = max(0.0, -NdotL);
	float translucent = backlight * translucency * AO;
	
	// ========================================================================
	// RIM LIGHTING (cartoon edge highlight)
	// ========================================================================
	
	float NdotV = dot(NORMAL, VIEW);
	float rim = 1.0 - max(0.0, NdotV);
	rim = pow(rim, 2.5) * rim_strength;
	rim *= max(0.0, NdotL * 0.5 + 0.5);
	
	// ========================================================================
	// COMBINE LIGHTING
	// ========================================================================
	
	vec3 diffuse = ALBEDO * LIGHT_COLOR * quantized * ATTENUATION;
	vec3 trans_light = ALBEDO * LIGHT_COLOR * translucent * ATTENUATION * 0.4;
	vec3 rim_light = ALBEDO * LIGHT_COLOR * rim * ATTENUATION * 0.25;
	
	DIFFUSE_LIGHT += diffuse + trans_light + rim_light;
}
