@tool
extends Node
class_name TerrainGenerator
## Metin2-style terrain generator for MMO zones.
## 
## This tool generates pre-built terrain for each empire zone:
## - Shinsoo: Mountains and forests (Korean/Chinese theme)
## - Chunjo: Desert and plains (arid theme)
## - Jinno: Coastal areas (island theme)
##
## Usage: Add this node to a scene, configure empire, and call generate_and_save()

# =============================================================================
# CONFIGURATION
# =============================================================================

## Size of terrain in world units (512x512 is good for performance)
const TERRAIN_SIZE: int = 512

## Terrain3D region size (256 for smaller maps, 512 for larger)
const REGION_SIZE: int = 256

## Height map resolution (pixels per region)
const HEIGHT_MAP_SIZE: int = 512

## Empire types matching Metin2 kingdoms
enum Empire { SHINSOO, CHUNJO, JINNO }

## Which empire terrain to generate
@export var empire: Empire = Empire.SHINSOO

## Output directory for terrain data
@export_dir var output_directory: String = "res://assets/terrain"

## Village center position (relative to terrain center)
@export var village_center: Vector2 = Vector2(0, 0)

## Village flat radius (creates a plateau for buildings)
@export var village_radius: float = 60.0

## Generate terrain button (editor only)
@export var generate_terrain: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			generate_and_save()

## Preview in editor
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		if value and Engine.is_editor_hint():
			_create_preview()
		elif not value:
			_remove_preview()

# =============================================================================
# TEXTURE PATHS
# =============================================================================

const TEXTURES: Dictionary = {
	"grass": {
		"albedo": "res://assets/textures/leaves_forest_ground/textures/leaves_forest_ground_diff_2k.jpg",
		"normal": "res://assets/textures/leaves_forest_ground/textures/leaves_forest_ground_nor_gl_2k.jpg",
		"roughness": "res://assets/textures/leaves_forest_ground/textures/leaves_forest_ground_rough_2k.jpg",
	},
	"rock": {
		"albedo": "res://assets/textures/rocks_ground_06/textures/rocks_ground_06_diff_2k.jpg",
		"normal": "res://assets/textures/rocks_ground_06/textures/rocks_ground_06_nor_gl_2k.jpg",
		"roughness": "res://assets/textures/rocks_ground_06/textures/rocks_ground_06_rough_2k.jpg",
	},
	"dirt": {
		"albedo": "res://assets/textures/brown_mud/textures/brown_mud_03_diff_2k.jpg",
		"normal": "res://assets/textures/brown_mud/textures/brown_mud_03_nor_gl_2k.jpg",
		"roughness": "res://assets/textures/brown_mud/textures/brown_mud_03_spec_2k.jpg",
	},
	"sand": {
		"albedo": "res://assets/textures/playground_sand/textures/playground_sand_diff_2k.jpg",
		"normal": "res://assets/textures/playground_sand/textures/playground_sand_nor_gl_2k.jpg",
		"roughness": "res://assets/textures/playground_sand/textures/playground_sand_arm_2k.jpg",
	},
	"stone_path": {
		"albedo": "res://assets/textures/monastery_stone_floor/textures/monastery_stone_floor_diff_2k.jpg",
		"normal": "res://assets/textures/monastery_stone_floor/textures/monastery_stone_floor_nor_gl_2k.jpg",
		"roughness": "res://assets/textures/monastery_stone_floor/textures/monastery_stone_floor_arm_2k.jpg",
	},
	"coast": {
		"albedo": "res://assets/textures/coast_sand_rocks/textures/coast_sand_rocks_02_diff_2k.jpg",
		"normal": "res://assets/textures/coast_sand_rocks/textures/coast_sand_rocks_02_nor_gl_2k.jpg",
		"roughness": "res://assets/textures/coast_sand_rocks/textures/coast_sand_rocks_02_rough_2k.jpg",
	},
}

# Internal references
var _preview_terrain: Terrain3D = null
var _noise_base: FastNoiseLite
var _noise_mountains: FastNoiseLite
var _noise_detail: FastNoiseLite
var _noise_ridged: FastNoiseLite


func _ready() -> void:
	_setup_noise()


func _setup_noise() -> void:
	# Base terrain noise - gentle rolling hills
	_noise_base = FastNoiseLite.new()
	_noise_base.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_base.frequency = 0.003
	_noise_base.fractal_octaves = 3
	
	# Mountain noise - larger features
	_noise_mountains = FastNoiseLite.new()
	_noise_mountains.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_mountains.frequency = 0.002
	_noise_mountains.fractal_octaves = 4
	
	# Detail noise - small variations
	_noise_detail = FastNoiseLite.new()
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_detail.frequency = 0.02
	_noise_detail.fractal_octaves = 2
	
	# Ridged noise for mountain peaks
	_noise_ridged = FastNoiseLite.new()
	_noise_ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_ridged.frequency = 0.004
	_noise_ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED


# =============================================================================
# MAIN GENERATION
# =============================================================================

func generate_and_save() -> void:
	print("TerrainGenerator: Starting generation for ", Empire.keys()[empire])
	
	_setup_noise()
	
	# Determine save path first - Terrain3D needs data_directory set before importing
	var empire_name: String = str(Empire.keys()[empire]).to_lower()
	var save_path: String = output_directory + "/" + empire_name
	
	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(save_path)
	
	# Create terrain with data directory already set
	var terrain: Terrain3D = _create_terrain(save_path)
	
	# Generate height map
	var height_image: Image = _generate_height_map()
	
	# Import height map into terrain
	var images: Array[Image] = []
	images.resize(3)  # height, control, color
	images[0] = height_image
	
	var import_pos: Vector3 = Vector3(-TERRAIN_SIZE / 2.0, 0, -TERRAIN_SIZE / 2.0)
	terrain.data.import_images(images, import_pos, 0.0, 1.0)
	
	# Save terrain data
	terrain.data.save_directory(save_path)
	
	# Also save the assets
	var assets_path: String = output_directory + "/" + empire_name + "_assets.tres"
	ResourceSaver.save(terrain.assets, assets_path)
	
	# Export heightmap as PNG for server
	var heightmap_path: String = output_directory + "/" + empire_name + "_heightmap.png"
	height_image.save_png(heightmap_path)
	
	print("TerrainGenerator: Saved terrain to ", save_path)
	print("TerrainGenerator: Saved heightmap to ", heightmap_path)
	
	# Cleanup
	terrain.queue_free()


func _create_terrain(data_dir: String = "") -> Terrain3D:
	var terrain: Terrain3D = Terrain3D.new()
	terrain.name = "GeneratedTerrain"
	
	# Configure terrain
	terrain.region_size = REGION_SIZE
	
	# Set data directory BEFORE adding to tree (required for import_images to work)
	if not data_dir.is_empty():
		terrain.data_directory = data_dir
	
	# Set up material
	terrain.material = Terrain3DMaterial.new()
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 25)  # Angle where rock starts
	terrain.material.set_shader_param("auto_height_reduction", 0)
	terrain.material.set_shader_param("blend_sharpness", 0.87)
	
	# Set up texture assets
	terrain.assets = _create_texture_assets()
	
	# Need to add to tree temporarily for data operations
	add_child(terrain)
	
	return terrain


func _create_texture_assets() -> Terrain3DAssets:
	var assets: Terrain3DAssets = Terrain3DAssets.new()
	
	# Texture assignment varies by empire
	# UV scale: higher = more tiling = smaller texture appearance
	# Values 0.2-0.5 give reasonably sized ground textures
	match empire:
		Empire.SHINSOO:
			# Forest/mountain theme
			assets.set_texture(0, _load_texture_asset("grass", 0.25))   # Base - forest floor
			assets.set_texture(1, _load_texture_asset("rock", 0.18))    # Slopes - rock
			assets.set_texture(2, _load_texture_asset("dirt", 0.22))    # Paths - dirt
			assets.set_texture(3, _load_texture_asset("stone_path", 0.35))  # Village - stone
			
		Empire.CHUNJO:
			# Desert/plains theme
			assets.set_texture(0, _load_texture_asset("sand", 0.30))    # Base - sand
			assets.set_texture(1, _load_texture_asset("rock", 0.18))    # Slopes - rock
			assets.set_texture(2, _load_texture_asset("dirt", 0.22))    # Paths - dirt
			assets.set_texture(3, _load_texture_asset("stone_path", 0.35))  # Village - stone
			
		Empire.JINNO:
			# Coastal theme
			assets.set_texture(0, _load_texture_asset("grass", 0.25))   # Base - grass
			assets.set_texture(1, _load_texture_asset("rock", 0.18))    # Cliffs - rock
			assets.set_texture(2, _load_texture_asset("coast", 0.22))   # Beach - coastal sand
			assets.set_texture(3, _load_texture_asset("stone_path", 0.35))  # Village - stone
	
	return assets


func _load_texture_asset(texture_name: String, uv_scale: float) -> Terrain3DTextureAsset:
	var asset: Terrain3DTextureAsset = Terrain3DTextureAsset.new()
	asset.name = texture_name.capitalize()
	
	var tex_data: Dictionary = TEXTURES[texture_name]
	
	# Load albedo
	if ResourceLoader.exists(tex_data["albedo"]):
		asset.albedo_texture = load(tex_data["albedo"])
	
	# Load normal
	if ResourceLoader.exists(tex_data["normal"]):
		asset.normal_texture = load(tex_data["normal"])
	
	asset.uv_scale = uv_scale
	asset.detiling_rotation = 0.25  # Higher value breaks up repetition
	
	return asset


# =============================================================================
# HEIGHT MAP GENERATION
# =============================================================================

func _generate_height_map() -> Image:
	var size: int = HEIGHT_MAP_SIZE * 2  # Cover full terrain (2x2 regions)
	var image: Image = Image.create(size, size, false, Image.FORMAT_RF)
	
	var half_size: float = size / 2.0
	var world_scale: float = float(TERRAIN_SIZE) / float(size)
	
	for y in range(size):
		for x in range(size):
			# Convert to world coordinates (centered)
			var world_x: float = (x - half_size) * world_scale
			var world_z: float = (y - half_size) * world_scale
			
			# Generate height based on empire
			var height: float = _get_height_for_empire(world_x, world_z)
			
			# Store as single float (FORMAT_RF stores in red channel)
			image.set_pixel(x, y, Color(height, 0, 0, 1))
	
	return image


func _get_height_for_empire(x: float, z: float) -> float:
	match empire:
		Empire.SHINSOO:
			return _generate_shinsoo_height(x, z)
		Empire.CHUNJO:
			return _generate_chunjo_height(x, z)
		Empire.JINNO:
			return _generate_jinno_height(x, z)
	return 0.0


# =============================================================================
# SHINSOO - Mountains and Forest
# =============================================================================

func _generate_shinsoo_height(x: float, z: float) -> float:
	var half_size: float = TERRAIN_SIZE / 2.0
	
	# Normalize coordinates to 0-1
	var nx: float = (x + half_size) / TERRAIN_SIZE
	var nz: float = (z + half_size) / TERRAIN_SIZE
	
	# Distance from center (for village flattening)
	var dist_from_village: float = Vector2(x - village_center.x, z - village_center.y).length()
	
	# Base rolling terrain
	var base_height: float = (float(_noise_base.get_noise_2d(x, z)) + 1.0) * 0.5 * 8.0
	
	# Mountains along north edge (z < 0)
	var north_factor: float = smoothstep(0.4, 0.0, nz)  # Stronger in north
	var mountain_noise: float = (float(_noise_mountains.get_noise_2d(x, z)) + 1.0) * 0.5
	var ridged: float = absf(float(_noise_ridged.get_noise_2d(x, z)))
	var mountain_height: float = (mountain_noise * 0.6 + ridged * 0.4) * 45.0 * north_factor
	
	# Eastern hills
	var east_factor: float = smoothstep(0.5, 1.0, nx) * 0.5
	var east_height: float = (float(_noise_mountains.get_noise_2d(x + 1000, z)) + 1.0) * 0.5 * 25.0 * east_factor
	
	# Detail noise
	var detail: float = float(_noise_detail.get_noise_2d(x, z)) * 2.0
	
	# Combine heights
	var height: float = base_height + mountain_height + east_height + detail
	
	# Village plateau with raised edge
	var village_base_height: float = 3.0  # Village sits at height 3
	var inner_radius: float = village_radius * 0.7  # Flat inner area
	var rim_radius: float = village_radius  # Raised rim
	var outer_radius: float = village_radius * 2.0  # Transition zone
	
	if dist_from_village < inner_radius:
		# Completely flat inner village area
		height = village_base_height
	elif dist_from_village < rim_radius:
		# Gentle raised rim around village edge
		var rim_t: float = (dist_from_village - inner_radius) / (rim_radius - inner_radius)
		var rim_height: float = sin(rim_t * PI) * 1.5  # Subtle raised edge
		height = village_base_height + rim_height
	elif dist_from_village < outer_radius:
		# Smooth transition to natural terrain
		var transition_t: float = (dist_from_village - rim_radius) / (outer_radius - rim_radius)
		transition_t = transition_t * transition_t * (3.0 - 2.0 * transition_t)  # Smoothstep
		height = lerpf(village_base_height, height, transition_t)
	
	# River carving (from north mountains to south)
	var river_x: float = sin(z * 0.02) * 30.0 - 20.0  # Winding river path
	var river_dist: float = absf(x - river_x)
	var river_width: float = 12.0
	var river_depth: float = 4.0
	if river_dist < river_width and z < 50:  # River only in northern half
		var river_factor: float = 1.0 - (river_dist / river_width)
		river_factor = river_factor * river_factor  # Smooth falloff
		height -= river_depth * river_factor
	
	return maxf(0.0, height)


# =============================================================================
# CHUNJO - Desert and Plains
# =============================================================================

func _generate_chunjo_height(x: float, z: float) -> float:
	var half_size: float = TERRAIN_SIZE / 2.0
	
	# Normalize coordinates
	var nx: float = (x + half_size) / TERRAIN_SIZE
	var nz: float = (z + half_size) / TERRAIN_SIZE
	
	# Distance from center
	var dist_from_village: float = Vector2(x - village_center.x, z - village_center.y).length()
	
	# Gentle sand dunes
	var dune_height: float = (float(_noise_base.get_noise_2d(x * 0.8, z * 0.8)) + 1.0) * 0.5 * 6.0
	
	# Some rocky plateaus in the corners
	var corner_dist: float = minf(
		minf(Vector2(nx, nz).length(), Vector2(1.0 - nx, nz).length()),
		minf(Vector2(nx, 1.0 - nz).length(), Vector2(1.0 - nx, 1.0 - nz).length())
	)
	var plateau_factor: float = smoothstep(0.35, 0.15, corner_dist)
	var plateau_noise: float = (float(_noise_mountains.get_noise_2d(x, z)) + 1.0) * 0.5
	var plateau_height: float = plateau_noise * 20.0 * plateau_factor
	
	# Western ridge
	var west_factor: float = smoothstep(0.3, 0.0, nx)
	var west_height: float = (float(_noise_mountains.get_noise_2d(x, z + 500)) + 1.0) * 0.5 * 18.0 * west_factor
	
	# Detail
	var detail: float = float(_noise_detail.get_noise_2d(x, z)) * 1.5
	
	# Combine
	var height: float = dune_height + plateau_height + west_height + detail
	
	# Village plateau with raised edge (desert town on raised platform)
	var village_base_height: float = 2.0
	var inner_radius: float = village_radius * 0.7  # Flat inner area
	var rim_radius: float = village_radius  # Raised rim
	var outer_radius: float = village_radius * 2.0  # Transition zone
	
	if dist_from_village < inner_radius:
		# Completely flat inner village area
		height = village_base_height
	elif dist_from_village < rim_radius:
		# Gentle raised rim (like a walled desert town)
		var rim_t: float = (dist_from_village - inner_radius) / (rim_radius - inner_radius)
		var rim_height: float = sin(rim_t * PI) * 1.2  # Subtle raised edge
		height = village_base_height + rim_height
	elif dist_from_village < outer_radius:
		# Smooth transition to natural terrain
		var transition_t: float = (dist_from_village - rim_radius) / (outer_radius - rim_radius)
		transition_t = transition_t * transition_t * (3.0 - 2.0 * transition_t)  # Smoothstep
		height = lerpf(village_base_height, height, transition_t)
	
	# Oasis depression (water area) to the east
	var oasis_center: Vector2 = Vector2(80, 60)
	var oasis_dist: float = Vector2(x, z).distance_to(oasis_center)
	var oasis_radius: float = 25.0
	if oasis_dist < oasis_radius:
		var oasis_factor: float = 1.0 - (oasis_dist / oasis_radius)
		oasis_factor = oasis_factor * oasis_factor
		height -= 3.0 * oasis_factor
	
	return maxf(0.0, height)


# =============================================================================
# JINNO - Coastal
# =============================================================================

func _generate_jinno_height(x: float, z: float) -> float:
	var half_size: float = TERRAIN_SIZE / 2.0
	
	# Normalize coordinates
	var nx: float = (x + half_size) / TERRAIN_SIZE
	var nz: float = (z + half_size) / TERRAIN_SIZE
	
	# Distance from center
	var dist_from_village: float = Vector2(x - village_center.x, z - village_center.y).length()
	
	# Beach along south edge (z > 0)
	var beach_factor: float = smoothstep(0.65, 0.85, nz)
	var beach_height: float = 2.0 * (1.0 - beach_factor)  # Lower near beach
	
	# Main terrain rises inland
	var inland_height: float = (float(_noise_base.get_noise_2d(x, z)) + 1.0) * 0.5 * 10.0
	inland_height *= (1.0 - beach_factor)  # Reduce near beach
	
	# Coastal cliffs on east and west edges
	var cliff_west: float = smoothstep(0.25, 0.1, nx) * smoothstep(0.6, 0.3, nz)
	var cliff_east: float = smoothstep(0.75, 0.9, nx) * smoothstep(0.6, 0.3, nz)
	var cliff_factor: float = maxf(cliff_west, cliff_east)
	var cliff_noise: float = (float(_noise_ridged.get_noise_2d(x, z)) + 1.0) * 0.5
	var cliff_height: float = cliff_noise * 30.0 * cliff_factor
	
	# Northern hills
	var north_factor: float = smoothstep(0.4, 0.1, nz)
	var north_height: float = (float(_noise_mountains.get_noise_2d(x, z)) + 1.0) * 0.5 * 25.0 * north_factor
	
	# Detail
	var detail: float = float(_noise_detail.get_noise_2d(x, z)) * 1.5
	
	# Combine
	var height: float = beach_height + inland_height + cliff_height + north_height + detail
	
	# Village plateau with raised edge (coastal town on a hill)
	var village_base_height: float = 5.0
	var inner_radius: float = village_radius * 0.7  # Flat inner area
	var rim_radius: float = village_radius  # Raised rim
	var outer_radius: float = village_radius * 2.0  # Transition zone
	
	if dist_from_village < inner_radius:
		# Completely flat inner village area
		height = village_base_height
	elif dist_from_village < rim_radius:
		# Gentle raised rim (coastal town with defensive walls)
		var rim_t: float = (dist_from_village - inner_radius) / (rim_radius - inner_radius)
		var rim_height: float = sin(rim_t * PI) * 1.8  # Slightly higher rim for coastal defense
		height = village_base_height + rim_height
	elif dist_from_village < outer_radius:
		# Smooth transition to natural terrain
		var transition_t: float = (dist_from_village - rim_radius) / (outer_radius - rim_radius)
		transition_t = transition_t * transition_t * (3.0 - 2.0 * transition_t)  # Smoothstep
		height = lerpf(village_base_height, height, transition_t)
	
	# Harbor bay (cuts into south-east)
	var harbor_center: Vector2 = Vector2(60, 180)
	var harbor_dist: float = Vector2(x, z).distance_to(harbor_center)
	var harbor_radius: float = 40.0
	if harbor_dist < harbor_radius and z > 100:
		var harbor_factor: float = 1.0 - (harbor_dist / harbor_radius)
		harbor_factor = harbor_factor * harbor_factor
		height = lerpf(height, 0.0, harbor_factor * 0.8)
	
	return maxf(0.0, height)


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# =============================================================================
# PREVIEW
# =============================================================================

func _create_preview() -> void:
	_remove_preview()
	
	print("TerrainGenerator: Creating preview...")
	_setup_noise()
	
	# For preview, use a temporary directory
	var empire_name: String = str(Empire.keys()[empire]).to_lower()
	var preview_dir: String = "user://terrain_preview/" + empire_name
	DirAccess.make_dir_recursive_absolute(preview_dir)
	
	_preview_terrain = _create_terrain(preview_dir)
	_preview_terrain.name = "PreviewTerrain"
	
	var height_image: Image = _generate_height_map()
	var images: Array[Image] = []
	images.resize(3)
	images[0] = height_image
	
	var import_pos: Vector3 = Vector3(-TERRAIN_SIZE / 2.0, 0, -TERRAIN_SIZE / 2.0)
	_preview_terrain.data.import_images(images, import_pos, 0.0, 1.0)
	
	print("TerrainGenerator: Preview created")


func _remove_preview() -> void:
	if _preview_terrain and is_instance_valid(_preview_terrain):
		_preview_terrain.queue_free()
		_preview_terrain = null
