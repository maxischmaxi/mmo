// Realistic Water Shader for MMO
// Supports both rivers (flowing water) and lakes (still water)
// Physically-based rendering with absorption, refraction, and caustics

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// WATER TYPE - River vs Lake Detection
// ============================================================================
// Set flow_direction to (0,0) for a lake/still water
// Set flow_direction to a non-zero vector for a river (direction of flow)
// The magnitude affects flow speed

group_uniforms water_type;
uniform vec2 flow_direction = vec2(0.0, 0.0);
uniform float flow_speed : hint_range(0.0, 5.0) = 1.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.3;

// ============================================================================
// WATER COLORS - Physically Based
// ============================================================================

group_uniforms colors;
// Surface colors
uniform vec3 shallow_color : source_color = vec3(0.08, 0.55, 0.55);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.22);

// Light absorption per meter (water absorbs red first, then green, blue last)
uniform vec3 absorption : source_color = vec3(0.42, 0.038, 0.020);

// Scattering color (light bouncing inside water)
uniform vec3 scatter_color : source_color = vec3(0.0, 0.08, 0.12);
uniform float scatter_strength : hint_range(0.0, 1.0) = 0.3;

// Foam and reflection
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 sky_reflection_color : source_color = vec3(0.55, 0.72, 0.92);

// ============================================================================
// WAVE SETTINGS - Vertex Displacement
// ============================================================================

group_uniforms waves;
uniform float wave_amplitude : hint_range(0.0, 3.0) = 0.4;
uniform float wave_frequency : hint_range(0.01, 0.2) = 0.06;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;

// ============================================================================
// RIPPLE SETTINGS - Normal Perturbation
// ============================================================================

group_uniforms ripples;
uniform float ripple_scale_large : hint_range(0.01, 0.5) = 0.08;
uniform float ripple_scale_small : hint_range(0.1, 2.0) = 0.4;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.5;
uniform float ripple_speed : hint_range(0.0, 2.0) = 1.0;

// ============================================================================
// FOAM SETTINGS
// ============================================================================

group_uniforms foam;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.35;
uniform float shore_foam_width : hint_range(0.5, 10.0) = 2.5;
uniform float shore_foam_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float river_foam_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float crest_foam_threshold : hint_range(0.0, 1.0) = 0.6;

// ============================================================================
// OPTICAL PROPERTIES
// ============================================================================

group_uniforms optical;
// How far you can see through the water (meters)
uniform float clarity : hint_range(1.0, 50.0) = 12.0;

// Refraction (distortion of underwater view)
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.04;
uniform bool enable_chromatic_aberration = true;

// Reflection
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.6;

// ============================================================================
// CAUSTICS - Underwater Light Patterns
// ============================================================================

group_uniforms caustics;
uniform bool enable_caustics = true;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.35;
uniform float caustic_scale : hint_range(0.05, 0.5) = 0.12;
uniform float caustic_speed : hint_range(0.0, 1.0) = 0.4;

// ============================================================================
// MATERIAL PROPERTIES
// ============================================================================

group_uniforms material;
uniform float roughness_calm : hint_range(0.0, 0.3) = 0.02;
uniform float roughness_turbulent : hint_range(0.1, 0.6) = 0.25;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 0.1) = 0.0;

// ============================================================================
// TEXTURES
// ============================================================================

uniform sampler2D depth_texture : source_color, hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// ============================================================================
// VARYINGS
// ============================================================================

varying vec3 world_pos;
varying vec3 vertex_normal;
varying float wave_height;
varying float camera_distance;

// ============================================================================
// CONSTANTS
// ============================================================================

// PI and TAU are built-in in Godot shaders
const float WATER_IOR = 1.333;
const float F0 = 0.02; // Fresnel reflectance at normal incidence for water

// ============================================================================
// HASH FUNCTIONS - High Quality
// ============================================================================

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// ============================================================================
// NOISE FUNCTIONS
// ============================================================================

// Gradient noise (Perlin-like)
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	
	// Quintic interpolation for C2 continuity
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	
	float a = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

// Fractional Brownian Motion
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	
	for (int i = 0; i < octaves; i++) {
		value += amplitude * gnoise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	
	return value;
}

// Domain-warped FBM for more organic patterns
float fbm_warped(vec2 p, int octaves) {
	vec2 q = vec2(
		fbm(p + vec2(0.0, 0.0), 2),
		fbm(p + vec2(5.2, 1.3), 2)
	);
	return fbm(p + q * 2.0, octaves);
}

// Voronoi noise for caustics
float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	
	float min_dist = 1.0;
	
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash21(i + neighbor), hash21(i + neighbor + vec2(17.0, 31.0)));
			vec2 diff = neighbor + point - f;
			float dist = length(diff);
			min_dist = min(min_dist, dist);
		}
	}
	
	return min_dist;
}

// ============================================================================
// GERSTNER WAVE FUNCTION
// ============================================================================

vec3 gerstner_wave(vec2 pos, float time, vec2 direction, float steepness, float wavelength, float speed_mult) {
	float k = TAU / wavelength;
	float c = sqrt(9.8 / k) * speed_mult;
	vec2 d = normalize(direction);
	float f = k * (dot(d, pos) - c * time);
	float a = steepness / k;
	
	return vec3(
		d.x * a * cos(f),
		a * sin(f),
		d.y * a * cos(f)
	);
}

// ============================================================================
// CAUSTIC PATTERN
// ============================================================================

float caustic_pattern(vec2 p, float time) {
	// Two layers of voronoi at different scales and speeds
	float c1 = voronoi(p * 8.0 + vec2(time * 0.4, time * 0.2));
	float c2 = voronoi(p * 10.0 - vec2(time * 0.3, time * 0.5));
	
	// Create bright lines at cell edges
	c1 = 1.0 - smoothstep(0.0, 0.15, c1);
	c2 = 1.0 - smoothstep(0.0, 0.12, c2);
	
	// Combine and add variation
	float caustic = c1 * c2;
	caustic = pow(caustic, 1.5);
	
	// Add some noise to break up patterns
	caustic *= fbm(p * 5.0 + time * 0.1, 2) * 0.5 + 0.5;
	
	return caustic;
}

// ============================================================================
// VERTEX SHADER
// ============================================================================

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	camera_distance = length(world_pos - (inverse(VIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	
	float time = TIME * wave_speed;
	vec2 pos = world_pos.xz * wave_frequency;
	
	// Determine flow characteristics
	float flow_magnitude = length(flow_direction);
	vec2 flow_dir = flow_magnitude > 0.001 ? normalize(flow_direction) : vec2(1.0, 0.0);
	bool is_river = flow_magnitude > 0.001;
	
	// Calculate wave sum based on water type
	vec3 wave_sum = vec3(0.0);
	
	// LOD: Reduce wave complexity at distance
	float lod = smoothstep(50.0, 200.0, camera_distance);
	float wave_scale = mix(1.0, 0.5, lod);
	
	if (is_river) {
		// RIVER WAVES: Mostly perpendicular to flow direction
		vec2 perp = vec2(-flow_dir.y, flow_dir.x);
		float river_speed = flow_speed * flow_magnitude;
		
		// Main waves perpendicular to flow
		wave_sum += gerstner_wave(pos, time * river_speed, perp, 0.22, 8.0, 1.0);
		wave_sum += gerstner_wave(pos, time * river_speed * 1.1, -perp, 0.15, 6.0, 1.1);
		
		// Secondary waves at angles
		wave_sum += gerstner_wave(pos, time * river_speed * 0.9, perp * 0.7 + flow_dir * 0.3, 0.12, 5.0, 0.9);
		
		// Small downstream waves
		wave_sum += gerstner_wave(pos, time * river_speed * 0.7, flow_dir, 0.08, 10.0, 1.2);
		
		// Turbulence adds chaotic small waves
		if (turbulence > 0.1) {
			wave_sum += gerstner_wave(pos, time * 1.5, vec2(0.8, 0.6), 0.08 * turbulence, 3.0, 1.3);
			wave_sum += gerstner_wave(pos, time * 1.3, vec2(-0.7, 0.7), 0.06 * turbulence, 2.5, 1.4);
		}
	} else {
		// LAKE WAVES: Omnidirectional, wind-driven
		
		// Primary swell directions (as if wind from multiple angles)
		wave_sum += gerstner_wave(pos, time, vec2(1.0, 0.2), 0.18, 20.0, 0.8);
		wave_sum += gerstner_wave(pos, time * 0.9, vec2(0.3, 1.0), 0.14, 15.0, 0.9);
		wave_sum += gerstner_wave(pos, time * 1.1, vec2(-0.5, 0.85), 0.12, 12.0, 1.0);
		
		// Secondary smaller waves
		if (lod < 0.5) {
			wave_sum += gerstner_wave(pos, time * 0.85, vec2(0.9, -0.45), 0.08, 8.0, 1.1);
			wave_sum += gerstner_wave(pos, time * 1.15, vec2(-0.8, -0.6), 0.06, 10.0, 0.85);
			wave_sum += gerstner_wave(pos, time * 0.75, vec2(-0.2, -0.98), 0.05, 18.0, 0.7);
		}
		
		// Turbulence adds chop
		if (turbulence > 0.1) {
			wave_sum += gerstner_wave(pos, time * 1.4, vec2(0.6, 0.8), 0.1 * turbulence, 4.0, 1.2);
			wave_sum += gerstner_wave(pos, time * 1.2, vec2(-0.7, 0.5), 0.08 * turbulence, 3.0, 1.3);
		}
	}
	
	// Apply wave displacement
	vec3 displacement = wave_sum * wave_amplitude * wave_scale;
	VERTEX.y += displacement.y;
	VERTEX.x += displacement.x * 0.3;
	VERTEX.z += displacement.z * 0.3;
	
	wave_height = displacement.y;
	
	// Update world position after displacement
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Calculate approximate vertex normal from wave
	// This is a simplified normal - fragment shader will refine it
	vec3 bitangent = normalize(vec3(1.0, wave_sum.x * 0.5, 0.0));
	vec3 tangent = normalize(vec3(0.0, wave_sum.z * 0.5, 1.0));
	vertex_normal = normalize(cross(tangent, bitangent));
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

void fragment() {
	float time = TIME;
	
	// Flow characteristics
	float flow_magnitude = length(flow_direction);
	vec2 flow_dir = flow_magnitude > 0.001 ? normalize(flow_direction) : vec2(0.0);
	bool is_river = flow_magnitude > 0.001;
	float effective_flow = flow_magnitude * flow_speed;
	
	// ========================================================================
	// DEPTH CALCULATION
	// ========================================================================
	
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view_coords = INV_PROJECTION_MATRIX * ndc;
	view_coords.xyz /= view_coords.w;
	float scene_depth = -view_coords.z;
	float water_surface_depth = -VERTEX.z;
	float water_depth = max(0.0, scene_depth - water_surface_depth);
	
	// Depth factors
	float depth_fade = 1.0 - exp(-water_depth / clarity);
	float visibility_fade = exp(-water_depth * 0.15);
	
	// ========================================================================
	// RIPPLE NORMALS
	// ========================================================================
	
	vec2 uv = world_pos.xz;
	
	// LOD for ripples
	float ripple_lod = smoothstep(30.0, 150.0, camera_distance);
	int octaves_large = int(mix(4.0, 2.0, ripple_lod));
	int octaves_small = int(mix(3.0, 1.0, ripple_lod));
	
	vec2 ripple_uv1, ripple_uv2, ripple_uv3;
	
	if (is_river) {
		// RIVER: Ripples flow downstream
		vec2 flow_offset = flow_dir * time * effective_flow * ripple_speed;
		
		ripple_uv1 = uv * ripple_scale_large + flow_offset;
		ripple_uv2 = uv * ripple_scale_large * 1.4 + flow_offset * 0.7 + vec2(3.7, 2.1);
		ripple_uv3 = uv * ripple_scale_small + flow_offset * 1.5;
	} else {
		// LAKE: Ripples move in multiple directions (interference pattern)
		float t = time * ripple_speed;
		
		ripple_uv1 = uv * ripple_scale_large + vec2(t * 0.03, t * 0.02);
		ripple_uv2 = uv * ripple_scale_large * 1.3 - vec2(t * 0.025, t * 0.035);
		ripple_uv3 = uv * ripple_scale_small + vec2(sin(t * 0.5) * 0.02, cos(t * 0.3) * 0.02);
	}
	
	// Sample noise for normals
	float n1 = fbm_warped(ripple_uv1, octaves_large);
	float n2 = fbm_warped(ripple_uv2, octaves_large);
	float n3 = fbm(ripple_uv3, octaves_small);
	
	// Calculate normal from gradient
	float epsilon = 0.02;
	float h_center = (n1 + n2 * 0.7 + n3 * 0.4) / 2.1;
	float h_x = (fbm_warped(ripple_uv1 + vec2(epsilon, 0.0), octaves_large) + 
	             fbm_warped(ripple_uv2 + vec2(epsilon, 0.0), octaves_large) * 0.7 +
	             fbm(ripple_uv3 + vec2(epsilon, 0.0), octaves_small) * 0.4) / 2.1;
	float h_z = (fbm_warped(ripple_uv1 + vec2(0.0, epsilon), octaves_large) + 
	             fbm_warped(ripple_uv2 + vec2(0.0, epsilon), octaves_large) * 0.7 +
	             fbm(ripple_uv3 + vec2(0.0, epsilon), octaves_small) * 0.4) / 2.1;
	
	vec3 ripple_normal = normalize(vec3(
		(h_center - h_x) / epsilon * ripple_strength,
		1.0,
		(h_center - h_z) / epsilon * ripple_strength
	));
	
	// Blend with vertex normal
	vec3 water_normal = normalize(mix(vertex_normal, ripple_normal, 0.7));
	
	// Transform to view space
	vec3 view_normal = normalize(mat3(VIEW_MATRIX) * water_normal);
	
	// ========================================================================
	// FRESNEL - Schlick Approximation
	// ========================================================================
	
	vec3 view_dir = normalize(VIEW);
	float NdotV = max(dot(view_normal, view_dir), 0.0);
	float fresnel = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);
	
	// Increase fresnel in turbulent water
	fresnel = mix(fresnel, fresnel * 1.3, turbulence * 0.5);
	fresnel = clamp(fresnel, 0.0, 1.0);
	
	// ========================================================================
	// REFRACTION
	// ========================================================================
	
	vec2 refract_offset = water_normal.xz * refraction_strength * (1.0 - fresnel);
	
	// Reduce refraction at distance
	refract_offset *= (1.0 - smoothstep(50.0, 150.0, camera_distance));
	
	vec3 refracted_color;
	
	if (enable_chromatic_aberration && camera_distance < 100.0) {
		// Chromatic aberration - slight color separation
		float r = texture(screen_texture, SCREEN_UV + refract_offset * 0.9).r;
		float g = texture(screen_texture, SCREEN_UV + refract_offset * 1.0).g;
		float b = texture(screen_texture, SCREEN_UV + refract_offset * 1.1).b;
		refracted_color = vec3(r, g, b);
	} else {
		refracted_color = texture(screen_texture, SCREEN_UV + refract_offset).rgb;
	}
	
	// ========================================================================
	// ABSORPTION & SCATTERING
	// ========================================================================
	
	// Beer-Lambert law: light absorbed exponentially with depth
	vec3 absorbed = exp(-absorption * water_depth);
	refracted_color *= absorbed;
	
	// Add scattering (light bouncing inside water)
	vec3 scatter = scatter_color * (1.0 - exp(-water_depth * scatter_strength * 0.5));
	refracted_color += scatter;
	
	// ========================================================================
	// WATER SURFACE COLOR
	// ========================================================================
	
	// Blend shallow to deep based on actual water depth
	vec3 water_surface_color = mix(shallow_color, deep_color, depth_fade);
	
	// Blend refraction with water color based on visibility
	vec3 underwater_color = mix(refracted_color, water_surface_color, depth_fade * 0.6);
	
	// ========================================================================
	// REFLECTION
	// ========================================================================
	
	// Simple sky reflection (could sample environment probe for better results)
	vec3 reflection_color = sky_reflection_color;
	
	// Add some variation to reflection based on normal
	reflection_color *= 0.9 + water_normal.y * 0.1;
	
	// ========================================================================
	// COMBINE REFLECTION AND REFRACTION
	// ========================================================================
	
	vec3 surface_color = mix(underwater_color, reflection_color, fresnel * reflection_strength);
	
	// ========================================================================
	// FOAM
	// ========================================================================
	
	float foam = 0.0;
	
	// Shore foam - where water meets terrain
	float shore = 1.0 - smoothstep(0.0, shore_foam_width, water_depth);
	float shore_noise = fbm(uv * 2.0 + vec2(time * 0.08, time * 0.05), 2);
	float shore_pattern = smoothstep(0.3, 0.6, shore_noise);
	foam += shore * shore_pattern * shore_foam_intensity;
	
	// Secondary shore foam line
	float shore2 = smoothstep(shore_foam_width * 0.3, shore_foam_width * 0.5, water_depth) * 
	               (1.0 - smoothstep(shore_foam_width * 0.5, shore_foam_width * 0.7, water_depth));
	foam += shore2 * shore_pattern * shore_foam_intensity * 0.5;
	
	if (is_river) {
		// River foam - streaky patterns following flow
		vec2 foam_uv = uv + flow_dir * time * effective_flow * 0.5;
		
		// Streak pattern perpendicular to flow
		vec2 perp = vec2(-flow_dir.y, flow_dir.x);
		float streak = sin(dot(uv, perp) * 15.0 + time * 2.0) * 0.5 + 0.5;
		streak = smoothstep(0.6, 0.9, streak);
		
		// Foam noise following flow
		float river_noise = fbm(foam_uv * 3.0, 2);
		river_noise = smoothstep(0.45, 0.7, river_noise);
		
		float river_foam = streak * river_noise * river_foam_intensity * flow_magnitude;
		
		// More foam in turbulent areas
		river_foam *= (1.0 + turbulence * 2.0);
		
		foam += river_foam;
	}
	
	// Wave crest foam
	float crest_threshold = wave_amplitude * crest_foam_threshold;
	float crest_foam_val = smoothstep(crest_threshold, wave_amplitude, wave_height);
	float crest_noise = fbm(uv * 4.0 + time * 0.2, 2);
	crest_foam_val *= smoothstep(0.4, 0.6, crest_noise);
	foam += crest_foam_val * 0.6;
	
	// Apply foam
	foam = clamp(foam * foam_amount, 0.0, 1.0);
	surface_color = mix(surface_color, foam_color, foam);
	
	// ========================================================================
	// CAUSTICS
	// ========================================================================
	
	if (enable_caustics && water_depth > 0.1 && water_depth < clarity * 1.5 && camera_distance < 100.0) {
		float caustic = caustic_pattern(uv * caustic_scale, time * caustic_speed);
		
		// Fade caustics with depth
		float caustic_fade = (1.0 - depth_fade) * visibility_fade;
		
		// Caustics are brighter in shallow, clear water
		caustic *= caustic_strength * caustic_fade;
		
		// Add caustic light
		surface_color += caustic * shallow_color * 0.8;
	}
	
	// ========================================================================
	// FINAL OUTPUT
	// ========================================================================
	
	ALBEDO = surface_color;
	
	// Normal
	NORMAL = view_normal;
	
	// Roughness: calm water is smooth, turbulent/foamy water is rough
	float base_roughness = mix(roughness_calm, roughness_turbulent, turbulence);
	if (is_river) {
		base_roughness = mix(base_roughness, roughness_turbulent, flow_magnitude * 0.3);
	}
	ROUGHNESS = mix(base_roughness, 0.7, foam); // Foam is rough
	
	// Metallic and specular
	METALLIC = metallic;
	SPECULAR = mix(specular_intensity, specular_intensity * 0.3, foam);
	
	// Alpha - deeper water is more opaque
	float alpha = mix(0.6, 0.95, depth_fade);
	alpha = mix(alpha, 1.0, foam * 0.6); // Foam is opaque
	alpha = mix(alpha, 1.0, fresnel * 0.2); // Reflective areas more opaque
	
	// Fade out alpha at very shallow edges for smooth shore blend
	alpha *= smoothstep(0.0, 0.5, water_depth);
	
	ALPHA = alpha;
}
