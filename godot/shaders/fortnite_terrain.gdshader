// Fortnite-Style Procedural Terrain Shader for Terrain3D
// Clean, stylized height-based coloring with shoreline effect

shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

// ============================================================================
// TERRAIN3D REQUIRED DEFINITIONS
// ============================================================================

#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
	#define dFdxCoarse(a) dFdx(a)
	#define dFdyCoarse(a) dFdy(a)
#endif

// Terrain3D Private Uniforms (required)
uniform vec3 _camera_pos = vec3(0.0);
uniform float _mesh_size = 48.0;
uniform uint _background_mode = 1u;
uniform uint _mouse_layer = 0x80000000u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625;
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;

// ============================================================================
// FORTNITE STYLE - COLORS (vibrant, cartoon-like)
// ============================================================================

// Brighter yellow-green grass like Fortnite
uniform vec3 grass_color : source_color = vec3(0.42, 0.75, 0.28);
uniform vec3 dirt_color : source_color = vec3(0.60, 0.45, 0.30);
uniform vec3 rock_color : source_color = vec3(0.52, 0.50, 0.55);
uniform vec3 snow_color : source_color = vec3(0.96, 0.98, 1.0);

// Warmer, more visible beach
uniform vec3 sand_color : source_color = vec3(0.88, 0.78, 0.58);
uniform vec3 wet_sand_color : source_color = vec3(0.50, 0.42, 0.30);

// ============================================================================
// HEIGHT THRESHOLDS
// ============================================================================

// Water level - where the water surface is
uniform float water_level : hint_range(-100, 0) = -20.0;

// How many meters above water the beach extends (water_level to water_level + shoreline_height)
uniform float shoreline_height : hint_range(1, 30) = 8.0;

// Main terrain heights (grass goes up to this height, measured from shoreline_top)
uniform float grass_max_height : hint_range(0, 200) = 40.0;
uniform float dirt_max_height : hint_range(0, 200) = 70.0;
uniform float rock_max_height : hint_range(0, 200) = 100.0;

// Transition sharpness (higher = sharper transitions)
uniform float transition_sharpness : hint_range(2, 30) = 10.0;

// ============================================================================
// SLOPE SETTINGS
// ============================================================================

// How much steep slopes turn to rock (1.0 = fully rock on steep slopes)
uniform float slope_rock_influence : hint_range(0, 1) = 0.95;
// How steep before rock appears (lower = rock appears on gentler slopes)
uniform float slope_rock_threshold : hint_range(0, 1) = 0.3;

// ============================================================================
// MATERIAL PROPERTIES
// ============================================================================

uniform float grass_roughness : hint_range(0, 1) = 0.9;
uniform float dirt_roughness : hint_range(0, 1) = 0.95;
uniform float rock_roughness : hint_range(0, 1) = 0.8;
uniform float snow_roughness : hint_range(0, 1) = 0.7;
uniform float sand_roughness : hint_range(0, 1) = 0.92;
uniform float wet_sand_roughness : hint_range(0, 1) = 0.5;

// ============================================================================
// VARYINGS
// ============================================================================

varying float v_vertex_xz_dist;
varying vec3 v_vertex;

// ============================================================================
// TERRAIN3D FUNCTIONS
// ============================================================================

ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv, _region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[pos.y * _region_map_size + pos.x] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}

// ============================================================================
// VERTEX SHADER
// ============================================================================

void vertex() {
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);
	
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	
	vec2 shift = (scale < _vertex_spacing + 1e-6) ?
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))) :
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;
	
	UV = v_vertex.xz * _vertex_density;
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));
	
	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = bool(control >> 2u & 0x1u);
	
	if (!(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z < 0))) {
		v_vertex.x = 0.0 / 0.0;
	} else {
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r, texelFetch(_height_maps, uv_b, 0).r, vertex_lerp);
		v_vertex.y = h;
	}
	
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

void fragment() {
	vec2 uv = UV;
	
	// Grid lookup for normals
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv);
	vec2 weight = fract(uv);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y,
		weight.x * weight.y,
		weight.x * invert.y,
		invert.x * invert.y
	);
	
	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	float region_mip = log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);
	bool bilerp = region_mip < 0.0;
	
	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy, FRAGMENT_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, FRAGMENT_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, FRAGMENT_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, FRAGMENT_PASS);
	
	// Calculate terrain normal
	vec3 index_normal[4];
	float h[4];
	
	h[3] = texelFetch(_height_maps, index[3], 0).r;
	h[2] = texelFetch(_height_maps, index[2], 0).r;
	h[0] = texelFetch(_height_maps, index[0], 0).r;
	index_normal[3] = normalize(vec3(h[3] - h[2], _vertex_spacing, h[3] - h[0]));
	
	vec3 w_normal = index_normal[3];
	
	if (bilerp) {
		h[1] = texelFetch(_height_maps, index[1], 0).r;
		float h_4 = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, FRAGMENT_PASS), 0).r;
		float h_5 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, FRAGMENT_PASS), 0).r;
		float h_6 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, FRAGMENT_PASS), 0).r;
		float h_7 = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, FRAGMENT_PASS), 0).r;
		
		index_normal[0] = normalize(vec3(h[0] - h[1], _vertex_spacing, h[0] - h_7));
		index_normal[1] = normalize(vec3(h[1] - h_5, _vertex_spacing, h[1] - h_4));
		index_normal[2] = normalize(vec3(h[2] - h_6, _vertex_spacing, h[2] - h[1]));
		
		w_normal = normalize(
			index_normal[0] * weights[0] +
			index_normal[1] * weights[1] +
			index_normal[2] * weights[2] +
			index_normal[3] * weights[3]
		);
	}
	
	// Apply terrain normals
	vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;
	
	// ========================================================================
	// FORTNITE STYLE COLORING
	// ========================================================================
	
	float height = v_vertex.y;
	float t = transition_sharpness;
	
	// Calculate slope (0 = flat, 1 = vertical)
	float slope = 1.0 - w_normal.y;
	slope = clamp(slope * 1.5, 0.0, 1.0);
	
	// ========================================================================
	// SIMPLE HEIGHT-BASED COLORING
	// Grass below grass_max_height, then dirt, rock, snow
	// ========================================================================
	
	// Initialize blends
	float grass_blend = 0.0;
	float dirt_blend = 0.0;
	float rock_blend = 0.0;
	float snow_blend = 0.0;
	float sand_blend = 0.0;
	
	// Beach/shoreline zone (below shoreline_top)
	float shoreline_top = water_level + shoreline_height;
	
	if (height < shoreline_top) {
		// In shoreline/beach zone
		sand_blend = 1.0;
	} else if (height < shoreline_top + grass_max_height) {
		// Grass zone
		grass_blend = 1.0;
	} else if (height < shoreline_top + dirt_max_height) {
		// Dirt zone
		dirt_blend = 1.0;
	} else if (height < shoreline_top + rock_max_height) {
		// Rock zone
		rock_blend = 1.0;
	} else {
		// Snow zone
		snow_blend = 1.0;
	}
	
	// ========================================================================
	// SMOOTH TRANSITIONS
	// ========================================================================
	
	// Smooth transition from sand to grass
	float sand_to_grass = smoothstep(shoreline_top - t, shoreline_top + t, height);
	if (height > shoreline_top - t && height < shoreline_top + t) {
		sand_blend = 1.0 - sand_to_grass;
		grass_blend = sand_to_grass;
	}
	
	// Smooth transition from grass to dirt
	float grass_to_dirt_h = shoreline_top + grass_max_height;
	float grass_to_dirt = smoothstep(grass_to_dirt_h - t, grass_to_dirt_h + t, height);
	if (height > grass_to_dirt_h - t && height < grass_to_dirt_h + t) {
		grass_blend = 1.0 - grass_to_dirt;
		dirt_blend = grass_to_dirt;
	}
	
	// Smooth transition from dirt to rock
	float dirt_to_rock_h = shoreline_top + dirt_max_height;
	float dirt_to_rock = smoothstep(dirt_to_rock_h - t, dirt_to_rock_h + t, height);
	if (height > dirt_to_rock_h - t && height < dirt_to_rock_h + t) {
		dirt_blend = 1.0 - dirt_to_rock;
		rock_blend = dirt_to_rock;
	}
	
	// Smooth transition from rock to snow
	float rock_to_snow_h = shoreline_top + rock_max_height;
	float rock_to_snow = smoothstep(rock_to_snow_h - t, rock_to_snow_h + t, height);
	if (height > rock_to_snow_h - t && height < rock_to_snow_h + t) {
		rock_blend = 1.0 - rock_to_snow;
		snow_blend = rock_to_snow;
	}
	
	// ========================================================================
	// SLOPE-BASED ROCK (steep areas become rock instantly above 0m)
	// ========================================================================
	
	// Calculate slope rock amount - steeper = more rock
	float slope_rock = smoothstep(slope_rock_threshold, slope_rock_threshold + 0.15, slope) * slope_rock_influence;
	
	// Only apply slope-based rock above water level (height > 0)
	// Below water level, keep beach/sand colors even on slopes
	float above_water = smoothstep(-5.0, 5.0, height);
	slope_rock *= above_water;
	
	// Mix in rock on steep slopes - rock completely replaces other materials
	float non_rock = 1.0 - slope_rock;
	grass_blend *= non_rock;
	dirt_blend *= non_rock;
	sand_blend *= non_rock;
	snow_blend *= non_rock * 0.5 + 0.5; // Snow stays partially on steep slopes at high altitude
	rock_blend = rock_blend * non_rock + slope_rock;
	
	// ========================================================================
	// NORMALIZE AND CALCULATE FINAL COLOR
	// ========================================================================
	
	float total = grass_blend + dirt_blend + rock_blend + snow_blend + sand_blend;
	total = max(total, 0.001);
	grass_blend /= total;
	dirt_blend /= total;
	rock_blend /= total;
	snow_blend /= total;
	sand_blend /= total;
	
	// Beach color varies from wet to dry
	float shore_progress = clamp((height - water_level) / shoreline_height, 0.0, 1.0);
	vec3 beach_color = mix(wet_sand_color, sand_color, shore_progress);
	float beach_roughness = mix(wet_sand_roughness, sand_roughness, shore_progress);
	
	vec3 albedo = grass_color * grass_blend
	            + dirt_color * dirt_blend
	            + rock_color * rock_blend
	            + snow_color * snow_blend
	            + beach_color * sand_blend;
	
	float roughness = grass_roughness * grass_blend
	                + dirt_roughness * dirt_blend
	                + rock_roughness * rock_blend
	                + snow_roughness * snow_blend
	                + beach_roughness * sand_blend;
	
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
