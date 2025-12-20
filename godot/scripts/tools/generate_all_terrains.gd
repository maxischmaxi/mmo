@tool
extends EditorScript
## Editor script to generate all empire terrains
##
## Right-click this file in the FileSystem dock and select "Run" to execute.
##
## NOTE: You may see "Resource file not found: res://" errors during generation.
## These are benign warnings from the Terrain3D addon and can be safely ignored.


func _run() -> void:
	print("")
	print("==============================================")
	print("       MMO Terrain Generator")
	print("==============================================")
	print("")
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
		
		# Add to edited scene root so it can work
		var scene_root := get_scene()
		if scene_root:
			scene_root.add_child(generator)
		else:
			# Fallback: add to editor interface
			get_editor_interface().get_base_control().add_child(generator)
		
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
	print("  - shinsoo_heightmap.json + .bin")
	print("  - chunjo_heightmap.json + .bin") 
	print("  - jinno_heightmap.json + .bin")
	print("")
	print("Run 'copy_heightmaps_to_server.gd' to copy files to server/heightmaps/")
	print("")
