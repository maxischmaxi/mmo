@tool
extends EditorScript
## Editor script to copy heightmaps to server directory
## 
## Right-click this file in the FileSystem dock and select "Run" to execute.
## 
## Copies generated heightmaps from res://assets/terrain/ to server/heightmaps/


const EMPIRES: Array[String] = ["shinsoo", "chunjo", "jinno"]
const SOURCE_DIR: String = "res://assets/terrain"


func _run() -> void:
	print("")
	print("==============================================")
	print("       Heightmap Copier")
	print("==============================================")
	print("")
	print("Copying heightmaps to server directory...")
	print("")
	
	# Get the absolute path to the server/heightmaps directory
	var project_path: String = ProjectSettings.globalize_path("res://")
	var server_heightmaps_path: String = project_path.path_join("../server/heightmaps")
	
	# Ensure target directory exists
	if not DirAccess.dir_exists_absolute(server_heightmaps_path):
		var err := DirAccess.make_dir_recursive_absolute(server_heightmaps_path)
		if err != OK:
			push_error("Failed to create directory: ", server_heightmaps_path)
			return
		print("Created directory: ", server_heightmaps_path)
	
	var success_count: int = 0
	var expected_count: int = EMPIRES.size() * 2  # .json and .bin for each empire
	
	for empire in EMPIRES:
		print("----------------------------------------")
		print("Copying ", empire, " heightmap files...")
		print("----------------------------------------")
		
		# Copy JSON file
		var json_source := SOURCE_DIR + "/" + empire + "_heightmap.json"
		var json_target := server_heightmaps_path.path_join(empire + "_heightmap.json")
		
		if _copy_file(json_source, json_target):
			success_count += 1
		
		# Copy BIN file
		var bin_source := SOURCE_DIR + "/" + empire + "_heightmap.bin"
		var bin_target := server_heightmaps_path.path_join(empire + "_heightmap.bin")
		
		if _copy_file(bin_source, bin_target):
			success_count += 1
		
		print("")
	
	print("==============================================")
	if success_count == expected_count:
		print("       All heightmaps copied successfully!")
	else:
		print("       Copied ", success_count, "/", expected_count, " files")
		print("       Some files may be missing - run terrain generator first")
	print("==============================================")
	print("")
	print("Files copied to: ", server_heightmaps_path)
	print("")


func _copy_file(source_path: String, target_path: String) -> bool:
	# Check if source exists
	if not FileAccess.file_exists(source_path):
		push_error("Source file not found: ", source_path)
		print("  [SKIP] ", source_path.get_file(), " (not found)")
		return false
	
	# Read source file
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		push_error("Failed to open source: ", source_path, " - ", FileAccess.get_open_error())
		print("  [FAIL] ", source_path.get_file(), " (read error)")
		return false
	
	var content := source_file.get_buffer(source_file.get_length())
	source_file.close()
	
	# Write to target
	var target_file := FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		push_error("Failed to open target: ", target_path, " - ", FileAccess.get_open_error())
		print("  [FAIL] ", target_path.get_file(), " (write error)")
		return false
	
	target_file.store_buffer(content)
	target_file.close()
	
	print("  [OK] ", source_path.get_file(), " -> ", target_path)
	return true
