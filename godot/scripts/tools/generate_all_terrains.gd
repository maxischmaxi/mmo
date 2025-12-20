extends SceneTree
## Command-line terrain generator
## Run with: godot --headless --script res://scripts/tools/generate_all_terrains.gd


func _init() -> void:
	print("==============================================")
	print("       MMO Terrain Generator")
	print("==============================================")
	print("")
	
	# We need to wait for the scene tree to be ready
	call_deferred("_generate_terrains")


func _generate_terrains() -> void:
	print("Generating terrains for all empires...")
	print("")
	
	# Generate each empire's terrain
	for empire_idx in range(3):
		var empire_name: String = ""
		match empire_idx:
			0: empire_name = "Shinsoo"
			1: empire_name = "Chunjo"
			2: empire_name = "Jinno"
		
		print("----------------------------------------")
		print("Generating ", empire_name, " terrain...")
		print("----------------------------------------")
		
		var generator: TerrainGenerator = TerrainGenerator.new()
		generator.empire = empire_idx
		generator.output_directory = "res://assets/terrain"
		
		# Add to tree so it can work
		root.add_child(generator)
		
		# Generate
		generator.generate_and_save()
		
		# Cleanup
		generator.queue_free()
		
		print("")
	
	print("==============================================")
	print("       All terrains generated!")
	print("==============================================")
	print("")
	print("Terrain data saved to: res://assets/terrain/")
	print("  - shinsoo/")
	print("  - chunjo/")
	print("  - jinno/")
	print("")
	print("Heightmaps exported for server:")
	print("  - shinsoo_heightmap.png")
	print("  - chunjo_heightmap.png") 
	print("  - jinno_heightmap.png")
	print("")
	
	# Exit
	quit()
