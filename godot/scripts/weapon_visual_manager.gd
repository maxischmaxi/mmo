extends Node3D
## Manages weapon visual attachment to character skeleton.
## Handles loading weapon meshes and attaching them to hand bones.

## Weapon visual types (matches WeaponVisualType enum in Rust)
enum WeaponVisualType {
	ONE_HANDED_SWORD = 0,
	DAGGER = 1,
	TWO_HANDED_SWORD = 2,
	ONE_HANDED_AXE = 3,
	TWO_HANDED_AXE = 4,
	HAMMER = 5,
	STAFF = 6,
	BOW = 7,
	SPEAR = 8,
}

## Weapon data: item_id -> { mesh_name, visual_type }
## This maps game item IDs to their visual representation
const WEAPON_DATA := {
	# Universal Weapons
	4: { "mesh": "Arming_Sword", "type": WeaponVisualType.ONE_HANDED_SWORD },
	5: { "mesh": "Cutlass", "type": WeaponVisualType.ONE_HANDED_SWORD },
	# Ninja Weapons (Daggers)
	10: { "mesh": "Dagger", "type": WeaponVisualType.DAGGER },
	11: { "mesh": "Bone_Shiv", "type": WeaponVisualType.DAGGER },
	# Warrior Weapons (Two-handed)
	12: { "mesh": "Great_Sword", "type": WeaponVisualType.TWO_HANDED_SWORD },
	13: { "mesh": "Double_Axe", "type": WeaponVisualType.TWO_HANDED_AXE },
	# Sura Weapons (One-handed swords)
	14: { "mesh": "Scimitar", "type": WeaponVisualType.ONE_HANDED_SWORD },
	15: { "mesh": "Kopesh", "type": WeaponVisualType.ONE_HANDED_SWORD },
	# Shaman Weapons (Staffs)
	16: { "mesh": "Wizard_Staff", "type": WeaponVisualType.STAFF },
	17: { "mesh": "Wizard_Staff", "type": WeaponVisualType.STAFF },
}

## Grip presets: visual_type -> { offset: Vector3, rotation: Vector3 (degrees) }
## These define how the weapon is held in the hand
## Rotation is applied to orient the weapon properly relative to the hand bone.
## Weapons are typically modeled with blade along +Y (up), handle at origin.
## The hand bone has fingers pointing forward, palm facing inward.
## We rotate to make the blade extend perpendicular to the arm (natural sword grip).
const GRIP_PRESETS := {
	WeaponVisualType.ONE_HANDED_SWORD: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 90),  # Blade extends upward from grip, perpendicular to arm
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	WeaponVisualType.DAGGER: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 90),  # Same grip as sword
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	WeaponVisualType.TWO_HANDED_SWORD: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 90),  # Same grip as one-handed sword
		"scale": Vector3(1.2, 1.2, 1.2)
	},
	WeaponVisualType.ONE_HANDED_AXE: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 90),  # Axe head extends upward from grip
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	WeaponVisualType.TWO_HANDED_AXE: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 90),  # Same grip as one-handed axe
		"scale": Vector3(1.2, 1.2, 1.2)
	},
	WeaponVisualType.HAMMER: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 90),  # Hammer head extends upward from grip
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	WeaponVisualType.STAFF: { 
		"offset": Vector3(0.0, 0.1, 0.0), 
		"rotation": Vector3(-90, 0, 45),  # Staff held at diagonal angle
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	WeaponVisualType.BOW: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(0, -90, 0),  # Bow held vertically, string toward body
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	WeaponVisualType.SPEAR: { 
		"offset": Vector3(0.0, 0.0, 0.0), 
		"rotation": Vector3(-90, 0, 45),  # Spear held at angle, point forward-up
		"scale": Vector3(1.0, 1.0, 1.0)
	},
}

## Base path to weapon meshes
const WEAPON_MESH_PATH := "res://assets/low_poly_weapon_pack/Weapons for Itch with image texture.fbx_%s.fbx"

## Reference to the right hand bone attachment
var right_hand_attachment: BoneAttachment3D = null

## Reference to the left hand bone attachment (for two-handed weapons)
var left_hand_attachment: BoneAttachment3D = null

## Currently equipped weapon mesh instance
var current_weapon_mesh: Node3D = null

## Currently equipped weapon item ID (-1 = unarmed)
var current_weapon_id: int = -1

## Cache of loaded weapon scenes
var weapon_cache: Dictionary = {}


func _ready() -> void:
	# Find bone attachments in the character model
	_find_bone_attachments()
	
	# Try to connect to player's equipment_changed signal
	_connect_to_player()


## Find or create the bone attachment nodes
func _find_bone_attachments() -> void:
	# Look for the skeleton in the character model
	var parent = get_parent()
	if not parent:
		return
	
	# Find the Skeleton3D node
	var skeleton: Skeleton3D = _find_skeleton(parent)
	if not skeleton:
		push_warning("WeaponVisualManager: Could not find Skeleton3D node")
		return
	
	# Check if bone attachments already exist, otherwise create them
	right_hand_attachment = skeleton.get_node_or_null("RightHandAttachment")
	if not right_hand_attachment:
		right_hand_attachment = _create_bone_attachment(skeleton, "DEF-hand.R", "RightHandAttachment")
	
	left_hand_attachment = skeleton.get_node_or_null("LeftHandAttachment")
	if not left_hand_attachment:
		left_hand_attachment = _create_bone_attachment(skeleton, "DEF-hand.L", "LeftHandAttachment")


## Find the Skeleton3D node in the hierarchy
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null


## Create a BoneAttachment3D for the specified bone
func _create_bone_attachment(skeleton: Skeleton3D, bone_name: String, attachment_name: String) -> BoneAttachment3D:
	# Check if the bone exists
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		push_warning("WeaponVisualManager: Bone '%s' not found in skeleton" % bone_name)
		return null
	
	# Create the bone attachment
	var attachment = BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	
	return attachment


## Recursively find a node by name
func _find_node_recursive(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found = _find_node_recursive(child, name)
		if found:
			return found
	return null


## Try to connect to the player node's equipment_changed signal
func _connect_to_player() -> void:
	# Find the player node (could be local player or we're on remote player)
	var player = _find_player_node()
	if player and player.has_signal("equipment_changed"):
		if not player.equipment_changed.is_connected(_on_equipment_changed):
			player.equipment_changed.connect(_on_equipment_changed)
			
			# Check if player already has a weapon equipped
			if player.has_method("get_equipped_weapon_id"):
				var weapon_id = player.get_equipped_weapon_id()
				if weapon_id >= 0:
					equip_weapon(weapon_id)


## Find the player node in the hierarchy
func _find_player_node() -> Node:
	# Walk up the tree to find the Player or RemotePlayer node
	# Note: Player is a Rust GDExtension class, so we check by signal presence
	var node = get_parent()
	while node:
		# Check if this node has the equipment_changed signal (Player class)
		if node.has_signal("equipment_changed"):
			return node
		# Also check by class name for CharacterBody3D types
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


## Handle equipment changed signal from player
func _on_equipment_changed(weapon_id: int) -> void:
	if weapon_id < 0:
		unequip_weapon()
	else:
		equip_weapon(weapon_id)


## Equip a weapon by item ID
func equip_weapon(item_id: int) -> void:
	# Don't re-equip the same weapon
	if item_id == current_weapon_id:
		return
	
	# Unequip current weapon first
	unequip_weapon()
	
	# Check if we have data for this weapon
	if not WEAPON_DATA.has(item_id):
		push_warning("WeaponVisualManager: Unknown weapon ID %d" % item_id)
		return
	
	var weapon_info = WEAPON_DATA[item_id]
	var mesh_name: String = weapon_info["mesh"]
	var visual_type: int = weapon_info["type"]
	
	# Load the weapon mesh
	var weapon_mesh = _load_weapon_mesh(mesh_name)
	if not weapon_mesh:
		push_error("WeaponVisualManager: Failed to load weapon mesh '%s'" % mesh_name)
		return
	
	# Apply grip preset
	if not _apply_grip(weapon_mesh, visual_type):
		weapon_mesh.queue_free()
		return
	
	current_weapon_mesh = weapon_mesh
	current_weapon_id = item_id
	
	print("WeaponVisualManager: Equipped weapon ID %d (%s)" % [item_id, mesh_name])


## Unequip the current weapon
func unequip_weapon() -> void:
	if current_weapon_mesh:
		current_weapon_mesh.queue_free()
		current_weapon_mesh = null
	current_weapon_id = -1


## Load a weapon mesh from the weapon pack
func _load_weapon_mesh(mesh_name: String) -> Node3D:
	# Check cache first
	if weapon_cache.has(mesh_name):
		var cached_scene: PackedScene = weapon_cache[mesh_name]
		if cached_scene:
			return cached_scene.instantiate()
	
	# Build the path
	var path = WEAPON_MESH_PATH % mesh_name
	
	# Check if the resource exists
	if not ResourceLoader.exists(path):
		push_error("WeaponVisualManager: Weapon mesh not found at '%s'" % path)
		return null
	
	# Load the scene
	var scene = load(path) as PackedScene
	if not scene:
		push_error("WeaponVisualManager: Failed to load weapon scene '%s'" % path)
		return null
	
	# Cache it
	weapon_cache[mesh_name] = scene
	
	# Instantiate and return
	return scene.instantiate()


## Apply grip preset and attach to hand
func _apply_grip(weapon_mesh: Node3D, visual_type: int) -> bool:
	if not right_hand_attachment:
		push_error("WeaponVisualManager: No right hand attachment available")
		return false
	
	# Get grip preset
	var grip = GRIP_PRESETS.get(visual_type, GRIP_PRESETS[WeaponVisualType.ONE_HANDED_SWORD])
	
	# Set transform
	weapon_mesh.position = grip["offset"]
	weapon_mesh.rotation_degrees = grip["rotation"]
	weapon_mesh.scale = grip["scale"]
	
	# Attach to right hand
	right_hand_attachment.add_child(weapon_mesh)
	
	return true


## Get the currently equipped weapon ID (-1 if unarmed)
func get_current_weapon_id() -> int:
	return current_weapon_id


## Check if a weapon is currently equipped
func has_weapon_equipped() -> bool:
	return current_weapon_id >= 0
