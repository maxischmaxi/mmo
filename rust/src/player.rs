use godot::prelude::*;
use godot::classes::{CharacterBody3D, ICharacterBody3D, Engine, Input};

use mmo_shared::{AnimationState, ServerMessage, InventorySlot, CharacterClass, Gender, Empire};
use crate::network::{NetworkClient, ConnectionState};

/// Player controller for the MMO.
/// Inherits from CharacterBody3D for physics-based movement.
/// Handles local player control and network synchronization.
#[derive(GodotClass)]
#[class(base=CharacterBody3D)]
pub struct Player {
    /// Movement speed in units per second
    #[export]
    speed: f32,
    
    /// Jump velocity
    #[export]
    jump_velocity: f32,
    
    /// Sprint speed multiplier
    #[export]
    sprint_multiplier: f32,
    
    /// Server address to connect to
    #[export]
    server_address: GString,
    
    /// Whether this is the local player (controlled by input)
    #[export]
    is_local: bool,

    /// Network client (only used by local player)
    network: Option<NetworkClient>,
    
    /// Current animation state
    animation_state: AnimationState,
    
    /// Our player ID from the server
    player_id: Option<u64>,
    
    /// Account ID (from login)
    account_id: Option<u64>,
    
    /// Current character ID (when in game)
    character_id: Option<u64>,
    
    /// Character name
    character_name: String,
    
    /// Character class
    character_class: Option<CharacterClass>,
    
    /// Character gender
    character_gender: Option<Gender>,
    
    /// Character empire
    character_empire: Option<Empire>,
    
    /// Current zone ID
    current_zone_id: u32,
    
    /// Current health
    current_health: u32,
    
    /// Maximum health
    max_health: u32,
    
    /// Current mana
    current_mana: u32,
    
    /// Maximum mana
    max_mana: u32,
    
    /// Attack power
    attack_power: u32,
    
    /// Defense
    defense: u32,
    
    /// Attack speed multiplier (1.0 = normal, higher = faster)
    attack_speed: f32,
    
    /// Level
    level: u32,
    
    /// Experience
    experience: u32,
    
    /// Experience needed to reach next level
    experience_to_next_level: u32,
    
    /// Gold currency
    gold: u64,
    
    /// Inventory (20 slots)
    inventory: Vec<Option<InventorySlot>>,
    
    /// Currently equipped weapon item ID (None = unarmed)
    equipped_weapon_id: Option<u32>,
    
    /// Currently equipped armor item ID (None = no armor)
    equipped_armor_id: Option<u32>,
    
    /// Movement direction set by camera controller (for both-button movement)
    camera_movement_direction: Option<Vector3>,
    
    /// Camera forward direction (set by camera controller each frame)
    camera_forward: Vector3,
    
    /// Camera right direction (set by camera controller each frame)
    camera_right: Vector3,
    
    /// Whether the player is dead
    is_dead: bool,
    
    /// Position where the player died (for revive-in-place)
    death_position: Option<Vector3>,
    
    /// Whether click-to-move is currently active (set by ClickMovementController)
    is_click_moving: bool,
    
    /// Whether the zone is loaded and ready (prevents falling before ground exists)
    zone_ready: bool,

    base: Base<CharacterBody3D>,
}

#[godot_api]
impl ICharacterBody3D for Player {
    fn init(base: Base<CharacterBody3D>) -> Self {
        godot_print!("Player initialized");
        
        Self {
            speed: 5.0,
            jump_velocity: 4.5,
            sprint_multiplier: 1.5,
            server_address: "127.0.0.1".into(),
            is_local: true,
            network: None,
            animation_state: AnimationState::Idle,
            player_id: None,
            account_id: None,
            character_id: None,
            character_name: String::new(),
            character_class: None,
            character_gender: None,
            character_empire: None,
            current_zone_id: 0,
            current_health: 100,
            max_health: 100,
            current_mana: 50,
            max_mana: 50,
            attack_power: 10,
            defense: 5,
            attack_speed: 1.0,
            level: 1,
            experience: 0,
            experience_to_next_level: 100,
            gold: 0,
            inventory: vec![None; 20],
            equipped_weapon_id: None,
            equipped_armor_id: None,
            camera_movement_direction: None,
            camera_forward: Vector3::new(0.0, 0.0, -1.0),
            camera_right: Vector3::new(1.0, 0.0, 0.0),
            is_dead: false,
            death_position: None,
            is_click_moving: false,
            zone_ready: false,
            base,
        }
    }

    fn ready(&mut self) {
        // Network is now initialized via login, not on ready
        // The login screen will call login() when the user submits credentials
    }

    fn physics_process(&mut self, delta: f64) {
        // Skip in editor
        if Engine::singleton().is_editor_hint() {
            return;
        }
        
        // Always process network (handles login responses, etc.)
        if self.is_local {
            self.process_network();
        }
        
        // Don't apply physics until zone is loaded (prevents falling through void)
        if !self.zone_ready {
            return;
        }
        
        let gravity = 9.8_f32;
        
        // Apply gravity when not on floor
        if !self.base().is_on_floor() {
            let mut velocity = self.base().get_velocity();
            velocity.y -= gravity * delta as f32;
            self.base_mut().set_velocity(velocity);
        }

        // Only process input for local player when connected and alive
        if self.is_local && self.is_connected_to_server() && !self.is_dead {
            self.process_input(delta);
        }
    }
}

#[godot_api]
impl Player {
    // ==========================================================================
    // Auth signals
    // ==========================================================================
    
    /// Signal emitted when registration succeeds
    #[signal]
    fn register_success(player_id: i64);
    
    /// Signal emitted when registration fails
    #[signal]
    fn register_failed(reason: GString);
    
    /// Signal emitted when login succeeds (includes full player state)
    #[signal]
    fn login_success(player_id: i64);
    
    /// Signal emitted when login fails
    #[signal]
    fn login_failed(reason: GString);
    
    // ==========================================================================
    // Character selection signals
    // ==========================================================================
    
    /// Signal emitted when character list is received
    #[signal]
    fn character_list_received(characters: Array<Dictionary>);
    
    /// Signal emitted when character is created successfully
    #[signal]
    fn character_created(character: Dictionary);
    
    /// Signal emitted when character creation fails
    #[signal]
    fn character_create_failed(reason: GString);
    
    /// Signal emitted when character is selected and game state received
    #[signal]
    fn character_selected(character_id: i64);
    
    /// Signal emitted when character selection fails
    #[signal]
    fn character_select_failed(reason: GString);
    
    /// Signal emitted when character is deleted
    #[signal]
    fn character_deleted(character_id: i64);
    
    /// Signal emitted when character deletion fails
    #[signal]
    fn character_delete_failed(reason: GString);
    
    // ==========================================================================
    // Game signals
    // ==========================================================================
    
    /// Signal emitted when disconnected
    #[signal]
    fn disconnected();
    
    /// Signal emitted when connection failed
    #[signal]
    fn connection_failed(reason: GString);
    
    /// Signal emitted when a chat message is received
    #[signal]
    fn chat_received(sender_name: GString, content: GString);
    
    /// Signal emitted when another player spawns
    #[signal]
    fn player_spawned(id: i64, name: GString, class_id: i64, gender_id: i64, empire_id: i64, position: Vector3);
    
    /// Signal emitted when another player despawns
    #[signal]
    fn player_despawned(id: i64);
    
    /// Signal emitted when world state is received
    #[signal]
    fn world_state_received(tick: i64);
    
    /// Signal emitted when an enemy spawns
    #[signal]
    fn enemy_spawned(id: i64, enemy_type: i64, position: Vector3, health: i64, max_health: i64, level: i64);
    
    /// Signal emitted when damage is dealt
    #[signal]
    fn damage_dealt(attacker_id: i64, target_id: i64, damage: i64, is_critical: bool);
    
    /// Signal emitted when inventory is updated
    #[signal]
    fn inventory_updated();
    
    /// Signal emitted when an entity dies
    #[signal]
    fn entity_died(entity_id: i64, killer_id: i64);
    
    /// Signal emitted when an enemy despawns
    #[signal]
    fn enemy_despawned(id: i64);
    
    /// Signal emitted when an enemy's state is updated (from WorldState)
    #[signal]
    fn enemy_state_updated(id: i64, position: Vector3, rotation: f64, health: i64, animation_state: i64);
    
    /// Signal emitted when an NPC spawns
    #[signal]
    fn npc_spawned(id: i64, npc_type: i64, position: Vector3, rotation: f64);
    
    /// Signal emitted when an NPC's state is updated (from WorldState)
    #[signal]
    fn npc_state_updated(id: i64, position: Vector3, rotation: f64, animation_state: i64);
    
    /// Signal emitted when a remote player's state is updated (from WorldState)
    #[signal]
    fn player_state_updated(id: i64, position: Vector3, rotation: f64, health: i64, animation_state: i64, equipped_weapon_id: i64, equipped_armor_id: i64);
    
    /// Signal emitted when local player's health changes
    #[signal]
    fn health_changed(current_health: i64, max_health: i64);
    
    /// Signal emitted when the local player dies
    #[signal]
    fn player_died();
    
    /// Signal emitted when the local player respawns
    #[signal]
    fn player_respawned(position: Vector3, health: i64, max_health: i64);
    
    /// Signal emitted when another entity respawns
    #[signal]
    fn entity_respawned(entity_id: i64, position: Vector3, health: i64);
    
    /// Signal emitted when equipment changes
    /// weapon_id: equipped weapon ID (-1 if unarmed)
    /// armor_id: equipped armor ID (-1 if no armor)
    #[signal]
    fn equipment_changed(weapon_id: i64, armor_id: i64);
    
    /// Signal emitted when time sync is received from server (for day/night cycle)
    /// unix_timestamp: seconds since Unix epoch (UTC)
    /// latitude: server location latitude for solar calculations
    /// longitude: server location longitude for solar calculations
    #[signal]
    fn time_sync(unix_timestamp: i64, latitude: f64, longitude: f64);
    
    /// Signal emitted when zone changes (on character select or zone transition)
    /// zone_id: zone ID (1-99: Shinsoo, 100-199: Chunjo, 200-299: Jinno, 300+: Neutral)
    /// zone_name: display name of the zone
    /// scene_path: Godot scene path to load
    /// spawn_x, spawn_y, spawn_z: spawn position in the zone
    #[signal]
    fn zone_change(zone_id: i64, zone_name: GString, scene_path: GString, spawn_x: f64, spawn_y: f64, spawn_z: f64);
    
    /// Signal emitted when a command response is received (from /commands)
    /// success: whether the command succeeded
    /// message: response message to display
    #[signal]
    fn command_response(success: bool, message: GString);
    
    /// Signal emitted when stats are updated (from /lvl or other stat-changing commands)
    /// Includes all stats that can be changed by commands
    #[signal]
    fn stats_updated(level: i64, max_health: i64, max_mana: i64, attack: i64, defense: i64, gold: i64, health: i64, mana: i64);
    
    /// Signal emitted when gold changes
    #[signal]
    fn gold_updated(gold: i64);
    
    /// Signal emitted when experience is gained
    /// amount: XP gained, current_xp: total XP, xp_to_next: XP needed for next level
    #[signal]
    fn experience_gained(amount: i64, current_xp: i64, xp_to_next: i64);
    
    /// Signal emitted when player levels up
    #[signal]
    fn level_up(new_level: i64, max_health: i64, max_mana: i64, attack: i64, defense: i64);
    
    // ==========================================================================
    // Ability signals
    // ==========================================================================
    
    /// Signal emitted when ability is used successfully
    /// caster_id: who used the ability, ability_id: which ability, target_id: target (0 if none)
    #[signal]
    fn ability_used(caster_id: i64, ability_id: i64, target_id: i64);
    
    /// Signal emitted when ability fails (only sent to caster)
    #[signal]
    fn ability_failed(ability_id: i64, reason: GString);
    
    /// Signal emitted when ability cooldown starts or updates
    #[signal]
    fn ability_cooldown(ability_id: i64, remaining: f64, total: f64);
    
    /// Signal emitted when a buff/debuff is applied
    #[signal]
    fn buff_applied(target_id: i64, buff_id: i64, ability_id: i64, duration: f64, is_debuff: bool);
    
    /// Signal emitted when a buff/debuff is removed
    #[signal]
    fn buff_removed(target_id: i64, buff_id: i64);
    
    /// Signal emitted when healing occurs
    #[signal]
    fn heal_received(healer_id: i64, target_id: i64, amount: i64, new_health: i64);
    
    /// Signal emitted when action bar is received (on character select)
    /// slots: Array of 8 ability IDs (-1 for empty)
    #[signal]
    fn action_bar_received(slots: Array<i64>);

    // ==========================================================================
    // Auth methods
    // ==========================================================================
    
    /// Register a new account
    #[func]
    fn register(&mut self, username: GString, password: GString) {
        let mut network = NetworkClient::new();
        let server_addr = self.server_address.to_string();
        
        match network.register(&server_addr, &username.to_string(), &password.to_string()) {
            Ok(()) => {
                godot_print!("Registering account '{}'...", username);
                self.network = Some(network);
            }
            Err(e) => {
                godot_error!("Failed to register: {}", e);
                self.base_mut().emit_signal("register_failed", &[GString::from(&e).to_variant()]);
            }
        }
    }
    
    /// Login with existing account
    #[func]
    fn login(&mut self, username: GString, password: GString) {
        let mut network = NetworkClient::new();
        let server_addr = self.server_address.to_string();
        
        match network.login(&server_addr, &username.to_string(), &password.to_string()) {
            Ok(()) => {
                godot_print!("Logging in as '{}'...", username);
                self.network = Some(network);
            }
            Err(e) => {
                godot_error!("Failed to login: {}", e);
                self.base_mut().emit_signal("login_failed", &[GString::from(&e).to_variant()]);
            }
        }
    }
    
    /// Disconnect from the server
    #[func]
    fn disconnect_from_server(&mut self) {
        if let Some(ref mut network) = self.network {
            network.disconnect();
        }
        self.network = None;
        self.player_id = None;
        self.account_id = None;
        self.character_id = None;
        self.character_name = String::new();
        self.character_class = None;
        self.character_gender = None;
        self.character_empire = None;
        // Reset zone state - ensures zone will be properly loaded on next login
        self.current_zone_id = 0;
        self.zone_ready = false;
        self.base_mut().emit_signal("disconnected", &[]);
    }
    
    // ==========================================================================
    // Character selection methods
    // ==========================================================================
    
    /// Request character list from server
    #[func]
    fn get_character_list(&mut self) {
        if let Some(ref mut network) = self.network {
            network.send_get_character_list();
        }
    }
    
    /// Create a new character
    /// class_id: 0=Ninja, 1=Warrior, 2=Sura, 3=Shaman
    /// gender_id: 0=Male, 1=Female
    /// empire_id: 0=Red(Shinsoo), 1=Yellow(Chunjo), 2=Blue(Jinno)
    #[func]
    fn create_character(&mut self, name: GString, class_id: i64, gender_id: i64, empire_id: i64) {
        let class = match class_id {
            0 => CharacterClass::Ninja,
            1 => CharacterClass::Warrior,
            2 => CharacterClass::Sura,
            3 => CharacterClass::Shaman,
            _ => CharacterClass::Warrior,
        };
        let gender = match gender_id {
            0 => Gender::Male,
            1 => Gender::Female,
            _ => Gender::Male,
        };
        let empire = match empire_id {
            0 => Empire::Red,
            1 => Empire::Yellow,
            2 => Empire::Blue,
            _ => Empire::Red,
        };
        
        if let Some(ref mut network) = self.network {
            network.send_create_character(&name.to_string(), class, gender, empire);
        }
    }
    
    /// Select a character to play
    #[func]
    fn select_character(&mut self, character_id: i64) {
        if let Some(ref mut network) = self.network {
            network.send_select_character(character_id as u64);
        }
    }
    
    /// Delete a character (requires typing name to confirm)
    #[func]
    fn delete_character(&mut self, character_id: i64, confirm_name: GString) {
        if let Some(ref mut network) = self.network {
            network.send_delete_character(character_id as u64, &confirm_name.to_string());
        }
    }
    
    /// Check if we have selected a character (are in game)
    #[func]
    fn is_in_game(&self) -> bool {
        self.character_id.is_some()
    }
    
    /// Get current character ID
    #[func]
    fn get_character_id(&self) -> i64 {
        self.character_id.unwrap_or(0) as i64
    }
    
    /// Get character name
    #[func]
    fn get_character_name(&self) -> GString {
        GString::from(&self.character_name)
    }
    
    /// Get character class (0=Ninja, 1=Warrior, 2=Sura, 3=Shaman)
    #[func]
    fn get_character_class(&self) -> i64 {
        self.character_class.map(|c| c.as_u8() as i64).unwrap_or(-1)
    }
    
    /// Get character gender (0=Male, 1=Female)
    #[func]
    fn get_character_gender(&self) -> i64 {
        self.character_gender.map(|g| g.as_u8() as i64).unwrap_or(-1)
    }
    
    /// Get character empire (0=Red, 1=Yellow, 2=Blue)
    #[func]
    fn get_character_empire(&self) -> i64 {
        self.character_empire.map(|e| e.as_u8() as i64).unwrap_or(-1)
    }
    
    /// Get current zone ID
    #[func]
    fn get_current_zone_id(&self) -> i64 {
        self.current_zone_id as i64
    }
    
    // ==========================================================================
    // Game methods
    // ==========================================================================
    
    /// Send a chat message
    #[func]
    fn send_chat(&mut self, message: GString) {
        if let Some(ref mut network) = self.network {
            network.send_chat(&message.to_string());
        }
    }
    
    /// Attack a target by ID
    #[func]
    fn attack_target(&mut self, target_id: i64) {
        if let Some(ref mut network) = self.network {
            network.send_attack(target_id as u64);
        }
    }
    
    /// Pick up an item by entity ID
    #[func]
    fn pickup_item(&mut self, item_entity_id: i64) {
        if let Some(ref mut network) = self.network {
            network.send_pickup(item_entity_id as u64);
        }
    }
    
    /// Use an item in inventory slot
    #[func]
    fn use_item(&mut self, slot: i64) {
        if let Some(ref mut network) = self.network {
            network.send_use_item(slot as u8);
        }
    }
    
    /// Request teleportation to a zone (via Teleport Ring)
    #[func]
    fn send_teleport_request(&mut self, zone_id: i64) {
        if let Some(ref mut network) = self.network {
            network.send_teleport_request(zone_id as u32);
            godot_print!("Sent teleport request to zone {}", zone_id);
        }
    }
    
    /// Swap two inventory slots (for drag & drop rearranging)
    #[func]
    fn swap_inventory_slots(&mut self, from_slot: i64, to_slot: i64) {
        if let Some(ref mut network) = self.network {
            network.send_swap_inventory_slots(from_slot as u8, to_slot as u8);
        }
    }
    
    /// Drop an item from inventory onto the ground
    #[func]
    fn drop_item(&mut self, slot: i64) {
        if let Some(ref mut network) = self.network {
            network.send_drop_item(slot as u8);
        }
    }
    
    /// Check if connected to server
    #[func]
    fn is_connected_to_server(&self) -> bool {
        self.network.as_ref().map(|n| n.is_connected()).unwrap_or(false)
    }
    
    /// Get our player ID
    #[func]
    fn get_player_id(&self) -> i64 {
        self.player_id.unwrap_or(0) as i64
    }
    
    /// Get current health
    #[func]
    fn get_health(&self) -> i64 {
        self.current_health as i64
    }
    
    /// Get max health
    #[func]
    fn get_max_health(&self) -> i64 {
        self.max_health as i64
    }
    
    /// Get current mana
    #[func]
    fn get_mana(&self) -> i64 {
        self.current_mana as i64
    }
    
    /// Get max mana
    #[func]
    fn get_max_mana(&self) -> i64 {
        self.max_mana as i64
    }
    
    /// Get level
    #[func]
    fn get_level(&self) -> i64 {
        self.level as i64
    }
    
    /// Get experience
    #[func]
    fn get_experience(&self) -> i64 {
        self.experience as i64
    }
    
    /// Get experience needed to reach next level
    #[func]
    fn get_experience_to_next_level(&self) -> i64 {
        self.experience_to_next_level as i64
    }
    
    /// Get gold
    #[func]
    fn get_gold(&self) -> i64 {
        self.gold as i64
    }
    
    /// Get attack power
    #[func]
    fn get_attack_power(&self) -> i64 {
        self.attack_power as i64
    }
    
    /// Get defense
    #[func]
    fn get_defense(&self) -> i64 {
        self.defense as i64
    }
    
    /// Get attack speed multiplier (1.0 = normal, higher = faster)
    #[func]
    fn get_attack_speed(&self) -> f64 {
        self.attack_speed as f64
    }
    
    /// Get the current animation state as integer
    /// 0=Idle, 1=Walking, 2=Running, 3=Jumping, 4=Attacking, 5=TakingDamage, 6=Dying, 7=Dead
    #[func]
    fn get_animation_state(&self) -> i64 {
        match self.animation_state {
            AnimationState::Idle => 0,
            AnimationState::Walking => 1,
            AnimationState::Running => 2,
            AnimationState::Jumping => 3,
            AnimationState::Attacking => 4,
            AnimationState::TakingDamage => 5,
            AnimationState::Dying => 6,
            AnimationState::Dead => 7,
        }
    }
    
    /// Set the animation state (called from GDScript when attacking, etc.)
    #[func]
    fn set_animation_state(&mut self, state: i64) {
        self.animation_state = match state {
            0 => AnimationState::Idle,
            1 => AnimationState::Walking,
            2 => AnimationState::Running,
            3 => AnimationState::Jumping,
            4 => AnimationState::Attacking,
            5 => AnimationState::TakingDamage,
            6 => AnimationState::Dying,
            7 => AnimationState::Dead,
            _ => AnimationState::Idle,
        };
    }
    
    /// Get inventory slot data (item_id, quantity) - returns Dictionary
    #[func]
    fn get_inventory_slot(&self, slot: i64) -> Dictionary {
        let mut dict = Dictionary::new();
        if let Some(Some(inv_slot)) = self.inventory.get(slot as usize) {
            dict.set("item_id", inv_slot.item_id as i64);
            dict.set("quantity", inv_slot.quantity as i64);
        }
        dict
    }
    
    /// Set movement direction from camera controller (for both-button forward movement)
    #[func]
    fn set_movement_direction(&mut self, direction: Vector3) {
        self.camera_movement_direction = Some(direction);
    }
    
    /// Clear the camera movement direction
    #[func]
    fn clear_movement_direction(&mut self) {
        self.camera_movement_direction = None;
    }
    
    /// Set camera directions for camera-relative movement (called by camera controller each frame)
    #[func]
    fn set_camera_directions(&mut self, forward: Vector3, right: Vector3) {
        self.camera_forward = forward;
        self.camera_right = right;
    }
    
    /// Check if the player is dead
    #[func]
    fn is_player_dead(&self) -> bool {
        self.is_dead
    }
    
    /// Request respawn from server
    /// respawn_type: 0 = at empire spawn (full health), 1 = at death location (20% health)
    #[func]
    fn request_respawn(&mut self, respawn_type: i64) {
        if let Some(ref mut network) = self.network {
            network.send_respawn_request(respawn_type as u8);
        }
    }
    
    /// Set whether click-to-move is active (called by ClickMovementController)
    #[func]
    fn set_click_moving(&mut self, active: bool) {
        self.is_click_moving = active;
    }
    
    /// Check if click-to-move is active
    #[func]
    fn is_click_moving(&self) -> bool {
        self.is_click_moving
    }
    
    // ==========================================================================
    // Equipment methods
    // ==========================================================================
    
    /// Get currently equipped weapon item ID (-1 if unarmed)
    #[func]
    fn get_equipped_weapon_id(&self) -> i64 {
        self.equipped_weapon_id.map(|id| id as i64).unwrap_or(-1)
    }
    
    /// Get currently equipped armor item ID (-1 if no armor)
    #[func]
    fn get_equipped_armor_id(&self) -> i64 {
        self.equipped_armor_id.map(|id| id as i64).unwrap_or(-1)
    }
    
    /// Equip item from inventory slot
    #[func]
    fn equip_item(&mut self, inventory_slot: i64) {
        if let Some(ref mut network) = self.network {
            network.send_equip_item(inventory_slot as u8);
        }
    }
    
    /// Unequip item from equipment slot
    /// equipment_slot: "weapon" (future: "head", "chest", etc.)
    #[func]
    fn unequip_item(&mut self, equipment_slot: GString) {
        if let Some(ref mut network) = self.network {
            network.send_unequip_item(&equipment_slot.to_string());
        }
    }
    
    /// Dev command: Add item to inventory (debug only)
    #[func]
    fn dev_add_item(&mut self, item_id: i64, quantity: i64) {
        if let Some(ref mut network) = self.network {
            network.send_dev_add_item(item_id as u32, quantity as u32);
        }
    }
    
    // ==========================================================================
    // Ability methods
    // ==========================================================================
    
    /// Use an ability
    /// ability_id: ID of the ability to use
    /// target_id: Target entity ID (-1 for no target/self)
    #[func]
    fn use_ability(&mut self, ability_id: i64, target_id: i64) {
        if let Some(ref mut network) = self.network {
            let target = if target_id < 0 { None } else { Some(target_id as u64) };
            network.send_use_ability(ability_id as u32, target);
        }
    }
    
    /// Called by ZoneManager when zone is fully loaded and ready
    /// This enables physics/gravity - prevents falling through void before ground exists
    #[func]
    fn set_zone_ready(&mut self, ready: bool) {
        self.zone_ready = ready;
        godot_print!("Player: zone_ready set to {}", ready);
    }
    
    /// Check if zone is ready
    #[func]
    fn is_zone_ready(&self) -> bool {
        self.zone_ready
    }
    
    // ==========================================================================
    // Network Statistics (for F3 debug overlay)
    // ==========================================================================
    
    /// Get current ping in milliseconds (-1 if not yet measured)
    #[func]
    fn get_ping_ms(&self) -> i64 {
        self.network.as_ref()
            .map(|n| n.get_ping_ms())
            .unwrap_or(-1)
    }
    
    /// Get total packets sent
    #[func]
    fn get_packets_sent(&self) -> i64 {
        self.network.as_ref()
            .map(|n| n.get_packets_sent() as i64)
            .unwrap_or(0)
    }
    
    /// Get total packets received
    #[func]
    fn get_packets_received(&self) -> i64 {
        self.network.as_ref()
            .map(|n| n.get_packets_received() as i64)
            .unwrap_or(0)
    }
}

impl Player {
    /// Get camera forward and right directions for camera-relative movement
    fn get_camera_directions(&self) -> (Vector3, Vector3) {
        // Try to get camera controller node
        if let Some(camera_controller) = self.base().get_node_or_null("CameraController") {
            if let Ok(node) = camera_controller.try_cast::<godot::classes::Node3D>() {
                // Get the camera controller's global transform basis
                let basis = node.get_global_transform().basis;
                
                // Forward is -Z in Godot (the direction the camera looks)
                let mut forward = -basis.col_c(); // -Z axis
                forward.y = 0.0;
                let forward = forward.normalized();
                
                // Right is +X
                let mut right = basis.col_a(); // X axis
                right.y = 0.0;
                let right = right.normalized();
                
                return (forward, right);
            }
        }
        
        // Fallback to stored values if camera not found
        (self.camera_forward, self.camera_right)
    }
    
    /// Check if any UI element (like chat) is capturing input
    fn is_ui_capturing_input(&self) -> bool {
        // Check if chat UI is focused
        if let Some(mut tree) = self.base().get_tree() {
            let chat_nodes = tree.get_nodes_in_group("chat_ui");
            for i in 0..chat_nodes.len() {
                if let Some(chat_node) = chat_nodes.get(i) {
                    if let Ok(mut chat) = chat_node.try_cast::<godot::classes::Node>() {
                        if chat.has_method("is_input_focused") {
                            let result = chat.call("is_input_focused", &[]);
                            if result.try_to::<bool>().unwrap_or(false) {
                                return true;
                            }
                        }
                    }
                }
            }
        }
        false
    }
    
    /// Process local player input - camera-relative controls
    fn process_input(&mut self, delta: f64) {
        // Skip input processing if UI is capturing input (e.g., chat is focused)
        if self.is_ui_capturing_input() {
            // Stop immediately when UI is capturing input
            let mut velocity = self.base().get_velocity();
            velocity.x = 0.0;
            velocity.z = 0.0;
            self.base_mut().set_velocity(velocity);
            self.base_mut().move_and_slide();
            self.animation_state = AnimationState::Idle;
            return;
        }
        
        let input = Input::singleton();
        
        // Get camera directions fresh each frame
        let (cam_forward, cam_right) = self.get_camera_directions();
        
        // Get movement inputs
        let forward_back = input.get_axis("move_forward", "move_back"); // W/S
        let left_right = input.get_axis("move_left", "move_right");     // A/D
        let strafe_input = input.get_axis("strafe_left", "strafe_right"); // Q/E
        
        // Calculate movement direction relative to CAMERA
        let direction = if let Some(camera_move) = self.camera_movement_direction.take() {
            // Both mouse buttons held - move in camera direction (legacy support)
            camera_move
        } else {
            let mut dir = Vector3::ZERO;
            
            // Forward/backward (W/S) - relative to camera facing
            dir += cam_forward * -forward_back;
            
            // Left/right (A/D) - strafe relative to camera
            dir += cam_right * left_right;
            
            // Q/E also strafe
            dir += cam_right * strafe_input;
            
            if dir.length_squared() > 0.01 {
                dir.normalized()
            } else {
                Vector3::ZERO
            }
        };
        
        let mut velocity = self.base().get_velocity();
        
        if direction != Vector3::ZERO {
            // WASD input cancels click-to-move
            if self.is_click_moving {
                self.is_click_moving = false;
            }
            
            // Check for sprint (shift key)
            let is_sprinting = input.is_action_pressed("sprint");
            let move_speed = if is_sprinting {
                self.speed * self.sprint_multiplier
            } else {
                self.speed
            };
            
            velocity.x = direction.x * move_speed;
            velocity.z = direction.z * move_speed;
            self.animation_state = if is_sprinting {
                AnimationState::Running
            } else {
                AnimationState::Walking
            };
            
            // Rotate character to face movement direction
            let target_yaw = direction.x.atan2(direction.z);
            let current_rot = self.base().get_rotation();
            let new_yaw = Self::lerp_angle(current_rot.y, target_yaw, 10.0 * delta as f32);
            self.base_mut().set_rotation(Vector3::new(current_rot.x, new_yaw, current_rot.z));
        } else if self.is_click_moving {
            // Click-to-move is active - don't reset velocity, let ClickMovementController handle it
            // ClickMovementController will set velocity and call move_and_slide
            // Just keep animation state as running (will be updated by AnimationController based on velocity)
            self.animation_state = AnimationState::Running;
        } else {
            // No WASD input and no click-to-move - stop immediately
            velocity.x = 0.0;
            velocity.z = 0.0;
            self.animation_state = AnimationState::Idle;
        }

        // Handle jump
        if input.is_action_just_pressed("jump") && self.base().is_on_floor() {
            velocity.y = self.jump_velocity;
            self.animation_state = AnimationState::Jumping;
        }

        // Only call move_and_slide if not click-moving
        // (ClickMovementController handles movement when click-to-move is active)
        if !self.is_click_moving {
            self.base_mut().set_velocity(velocity);
            self.base_mut().move_and_slide();
        }
    }
    
    /// Lerp between two angles (handles wraparound)
    fn lerp_angle(from: f32, to: f32, weight: f32) -> f32 {
        let mut diff = (to - from) % (2.0 * std::f32::consts::PI);
        if diff > std::f32::consts::PI {
            diff -= 2.0 * std::f32::consts::PI;
        } else if diff < -std::f32::consts::PI {
            diff += 2.0 * std::f32::consts::PI;
        }
        from + diff * weight
    }
    
    /// Process network messages
    fn process_network(&mut self) {
        // First, gather data we need before borrowing network
        let pos = self.base().get_position();
        let vel = self.base().get_velocity();
        let rot = self.base().get_rotation();
        let anim_state = self.animation_state;
        
        let network = match self.network.as_mut() {
            Some(n) => n,
            None => return,
        };
        
        // Check connection state
        match network.get_state() {
            ConnectionState::Failed(reason) => {
                let reason_clone = reason.clone();
                let _ = network; // End the borrow before modifying self.network
                self.network = None;
                self.base_mut().emit_signal("connection_failed", &[GString::from(&reason_clone).to_variant()]);
                return;
            }
            _ => {}
        }
        
        // Send position update if connected
        if network.is_connected() {
            network.send_player_update(
                [pos.x, pos.y, pos.z],
                rot.y,
                [vel.x, vel.y, vel.z],
                anim_state,
            );
        }
        
        // Process incoming messages
        let messages = network.poll();
        for msg in messages {
            self.handle_server_message(msg);
        }
    }
    
    /// Handle a message from the server
    fn handle_server_message(&mut self, msg: ServerMessage) {
        match msg {
            ServerMessage::RegisterSuccess { player_id } => {
                self.base_mut().emit_signal("register_success", &[(player_id as i64).to_variant()]);
            }
            
            ServerMessage::RegisterFailed { reason } => {
                self.base_mut().emit_signal("register_failed", &[GString::from(&reason).to_variant()]);
            }
            
            ServerMessage::LoginSuccess { player_id } => {
                // Login success now only returns account ID
                // Client should request character list next
                self.account_id = Some(player_id);
                self.base_mut().emit_signal("login_success", &[(player_id as i64).to_variant()]);
            }
            
            ServerMessage::CharacterList { characters } => {
                let mut char_array = Array::new();
                for c in characters {
                    let mut dict = Dictionary::new();
                    dict.set("id", c.id as i64);
                    dict.set("name", GString::from(&c.name));
                    dict.set("class", c.class.as_u8() as i64);
                    dict.set("gender", c.gender.as_u8() as i64);
                    dict.set("empire", c.empire.as_u8() as i64);
                    dict.set("level", c.level as i64);
                    char_array.push(&dict);
                }
                self.base_mut().emit_signal("character_list_received", &[char_array.to_variant()]);
            }
            
            ServerMessage::CharacterCreated { character } => {
                let mut dict = Dictionary::new();
                dict.set("id", character.id as i64);
                dict.set("name", GString::from(&character.name));
                dict.set("class", character.class.as_u8() as i64);
                dict.set("gender", character.gender.as_u8() as i64);
                dict.set("empire", character.empire.as_u8() as i64);
                dict.set("level", character.level as i64);
                self.base_mut().emit_signal("character_created", &[dict.to_variant()]);
            }
            
            ServerMessage::CharacterCreateFailed { reason } => {
                self.base_mut().emit_signal("character_create_failed", &[GString::from(&reason).to_variant()]);
            }
            
            ServerMessage::CharacterSelected {
                character_id,
                name,
                class,
                gender,
                empire,
                zone_id,
                position,
                rotation,
                health,
                max_health,
                mana,
                max_mana,
                level,
                experience,
                experience_to_next_level,
                attack,
                defense,
                attack_speed,
                inventory,
                equipped_weapon_id,
                equipped_armor_id,
                gold,
            } => {
                // Store character info
                self.character_id = Some(character_id);
                self.character_name = name;
                self.character_class = Some(class);
                self.character_gender = Some(gender);
                self.character_empire = Some(empire);
                self.current_zone_id = zone_id;
                
                // Use character_id as player_id for game world
                self.player_id = Some(character_id);
                
                // Store stats
                self.current_health = health;
                self.max_health = max_health;
                self.current_mana = mana;
                self.max_mana = max_mana;
                self.level = level;
                self.experience = experience;
                self.experience_to_next_level = experience_to_next_level;
                self.gold = gold;
                self.attack_power = attack;
                self.defense = defense;
                self.attack_speed = attack_speed;
                self.inventory = inventory;
                self.equipped_weapon_id = equipped_weapon_id;
                self.equipped_armor_id = equipped_armor_id;
                
                // Teleport to position
                let pos = Vector3::new(position[0], position[1], position[2]);
                self.base_mut().set_position(pos);
                self.base_mut().set_rotation(Vector3::new(0.0, rotation, 0.0));
                
                self.base_mut().emit_signal("character_selected", &[(character_id as i64).to_variant()]);
                
                // Also emit health and inventory signals
                self.base_mut().emit_signal("health_changed", &[
                    (health as i64).to_variant(),
                    (max_health as i64).to_variant(),
                ]);
                self.base_mut().emit_signal("inventory_updated", &[]);
                
                // Emit equipment changed signal
                self.base_mut().emit_signal("equipment_changed", &[
                    equipped_weapon_id.map(|id| id as i64).unwrap_or(-1).to_variant(),
                    equipped_armor_id.map(|id| id as i64).unwrap_or(-1).to_variant(),
                ]);
            }
            
            ServerMessage::CharacterSelectFailed { reason } => {
                self.base_mut().emit_signal("character_select_failed", &[GString::from(&reason).to_variant()]);
            }
            
            ServerMessage::CharacterDeleted { character_id } => {
                self.base_mut().emit_signal("character_deleted", &[(character_id as i64).to_variant()]);
            }
            
            ServerMessage::CharacterDeleteFailed { reason } => {
                self.base_mut().emit_signal("character_delete_failed", &[GString::from(&reason).to_variant()]);
            }
            
            ServerMessage::LoginFailed { reason } => {
                self.base_mut().emit_signal("login_failed", &[GString::from(&reason).to_variant()]);
            }
            
            ServerMessage::PlayerSpawn { id, name, class, gender, empire, position, .. } => {
                let pos = Vector3::new(position[0], position[1], position[2]);
                self.base_mut().emit_signal("player_spawned", &[
                    (id as i64).to_variant(),
                    GString::from(&name).to_variant(),
                    (class.as_u8() as i64).to_variant(),
                    (gender.as_u8() as i64).to_variant(),
                    (empire.as_u8() as i64).to_variant(),
                    pos.to_variant(),
                ]);
            }
            
            ServerMessage::PlayerDespawn { id } => {
                self.base_mut().emit_signal("player_despawned", &[(id as i64).to_variant()]);
            }
            
            ServerMessage::WorldState { tick, players, enemies, npcs } => {
                // Emit tick signal
                self.base_mut().emit_signal("world_state_received", &[(tick as i64).to_variant()]);
                
                // Emit updates for each remote player
                let my_id = self.player_id.unwrap_or(0);
                for player in players {
                    // Skip our own player
                    if player.id == my_id {
                        continue;
                    }
                    let pos = Vector3::new(player.position[0], player.position[1], player.position[2]);
                    // Convert animation state to integer
                    let anim_state: i64 = match player.animation_state {
                        AnimationState::Idle => 0,
                        AnimationState::Walking => 1,
                        AnimationState::Running => 2,
                        AnimationState::Jumping => 3,
                        AnimationState::Attacking => 4,
                        AnimationState::TakingDamage => 5,
                        AnimationState::Dying => 6,
                        AnimationState::Dead => 7,
                    };
                    // Convert equipped weapon ID (-1 for unarmed)
                    let weapon_id: i64 = player.equipped_weapon_id.map(|id| id as i64).unwrap_or(-1);
                    // Convert equipped armor ID (-1 for no armor)
                    let armor_id: i64 = player.equipped_armor_id.map(|id| id as i64).unwrap_or(-1);
                    self.base_mut().emit_signal("player_state_updated", &[
                        (player.id as i64).to_variant(),
                        pos.to_variant(),
                        (player.rotation as f64).to_variant(),
                        (player.health as i64).to_variant(),
                        anim_state.to_variant(),
                        weapon_id.to_variant(),
                        armor_id.to_variant(),
                    ]);
                }
                
                // Emit updates for each enemy
                for enemy in enemies {
                    let pos = Vector3::new(enemy.position[0], enemy.position[1], enemy.position[2]);
                    let anim_state = match enemy.animation_state {
                        mmo_shared::AnimationState::Idle => 0i64,
                        mmo_shared::AnimationState::Walking => 1i64,
                        mmo_shared::AnimationState::Running => 2i64,
                        mmo_shared::AnimationState::Jumping => 3i64,
                        mmo_shared::AnimationState::Attacking => 4i64,
                        mmo_shared::AnimationState::TakingDamage => 5i64,
                        mmo_shared::AnimationState::Dying => 6i64,
                        mmo_shared::AnimationState::Dead => 7i64,
                    };
                    self.base_mut().emit_signal("enemy_state_updated", &[
                        (enemy.id as i64).to_variant(),
                        pos.to_variant(),
                        (enemy.rotation as f64).to_variant(),
                        (enemy.health as i64).to_variant(),
                        anim_state.to_variant(),
                    ]);
                }
                
                // Emit updates for each NPC
                for npc in npcs {
                    let pos = Vector3::new(npc.position[0], npc.position[1], npc.position[2]);
                    let anim_state = match npc.animation_state {
                        mmo_shared::AnimationState::Idle => 0i64,
                        mmo_shared::AnimationState::Walking => 1i64,
                        mmo_shared::AnimationState::Running => 2i64,
                        mmo_shared::AnimationState::Jumping => 3i64,
                        mmo_shared::AnimationState::Attacking => 4i64,
                        mmo_shared::AnimationState::TakingDamage => 5i64,
                        mmo_shared::AnimationState::Dying => 6i64,
                        mmo_shared::AnimationState::Dead => 7i64,
                    };
                    self.base_mut().emit_signal("npc_state_updated", &[
                        (npc.id as i64).to_variant(),
                        pos.to_variant(),
                        (npc.rotation as f64).to_variant(),
                        anim_state.to_variant(),
                    ]);
                }
            }
            
            ServerMessage::ChatBroadcast { sender_name, content, .. } => {
                self.base_mut().emit_signal("chat_received", &[
                    GString::from(&sender_name).to_variant(),
                    GString::from(&content).to_variant(),
                ]);
            }
            
            ServerMessage::DamageEvent { attacker_id, target_id, damage, target_new_health, is_critical } => {
                self.base_mut().emit_signal("damage_dealt", &[
                    (attacker_id as i64).to_variant(),
                    (target_id as i64).to_variant(),
                    (damage as i64).to_variant(),
                    is_critical.to_variant(),
                ]);
                
                // If we were the target, update our health
                if let Some(my_id) = self.player_id {
                    if target_id == my_id {
                        self.current_health = target_new_health;
                        let max_hp = self.max_health;
                        self.base_mut().emit_signal("health_changed", &[
                            (target_new_health as i64).to_variant(),
                            (max_hp as i64).to_variant(),
                        ]);
                    }
                }
            }
            
            ServerMessage::EnemySpawn { id, zone_id: _, enemy_type, position, health, max_health, level } => {
                let pos = Vector3::new(position[0], position[1], position[2]);
                let enemy_type_int = match enemy_type {
                    mmo_shared::EnemyType::Goblin => 0,
                    mmo_shared::EnemyType::Skeleton => 1,
                    mmo_shared::EnemyType::Mutant => 2,
                    mmo_shared::EnemyType::Wolf => 3,
                };
                self.base_mut().emit_signal("enemy_spawned", &[
                    (id as i64).to_variant(),
                    enemy_type_int.to_variant(),
                    pos.to_variant(),
                    (health as i64).to_variant(),
                    (max_health as i64).to_variant(),
                    (level as i64).to_variant(),
                ]);
            }
            
            ServerMessage::InventoryUpdate { slots } => {
                self.inventory = slots;
                self.base_mut().emit_signal("inventory_updated", &[]);
            }
            
            ServerMessage::EntityDeath { entity_id, killer_id } => {
                // Check if this is the local player dying
                if let Some(my_id) = self.player_id {
                    if entity_id == my_id {
                        self.is_dead = true;
                        self.death_position = Some(self.base().get_position());
                        self.animation_state = AnimationState::Dead;
                        self.base_mut().emit_signal("player_died", &[]);
                    }
                }
                
                self.base_mut().emit_signal("entity_died", &[
                    (entity_id as i64).to_variant(),
                    (killer_id.unwrap_or(0) as i64).to_variant(),
                ]);
            }
            
            ServerMessage::EnemyDespawn { id } => {
                self.base_mut().emit_signal("enemy_despawned", &[(id as i64).to_variant()]);
            }
            
            ServerMessage::PlayerRespawned { position, health, max_health } => {
                // Local player respawned
                self.is_dead = false;
                self.death_position = None;
                self.current_health = health;
                self.max_health = max_health;
                self.animation_state = AnimationState::Idle;
                
                let pos = Vector3::new(position[0], position[1], position[2]);
                self.base_mut().set_position(pos);
                
                self.base_mut().emit_signal("player_respawned", &[
                    pos.to_variant(),
                    (health as i64).to_variant(),
                    (max_health as i64).to_variant(),
                ]);
                
                // Also emit health_changed for UI update
                self.base_mut().emit_signal("health_changed", &[
                    (health as i64).to_variant(),
                    (max_health as i64).to_variant(),
                ]);
            }
            
            ServerMessage::EntityRespawn { entity_id, position, health } => {
                let pos = Vector3::new(position[0], position[1], position[2]);
                self.base_mut().emit_signal("entity_respawned", &[
                    (entity_id as i64).to_variant(),
                    pos.to_variant(),
                    (health as i64).to_variant(),
                ]);
            }
            
            ServerMessage::EquipmentUpdate { equipped_weapon_id, equipped_armor_id } => {
                self.equipped_weapon_id = equipped_weapon_id;
                self.equipped_armor_id = equipped_armor_id;
                self.base_mut().emit_signal("equipment_changed", &[
                    equipped_weapon_id.map(|id| id as i64).unwrap_or(-1).to_variant(),
                    equipped_armor_id.map(|id| id as i64).unwrap_or(-1).to_variant(),
                ]);
            }
            
            ServerMessage::TimeSync { unix_timestamp, latitude, longitude } => {
                // Emit signal for day/night controller
                self.base_mut().emit_signal("time_sync", &[
                    unix_timestamp.to_variant(),
                    (latitude as f64).to_variant(),
                    (longitude as f64).to_variant(),
                ]);
            }
            
            ServerMessage::ZoneChange { zone_id, zone_name, scene_path, spawn_position } => {
                // Update current zone
                self.current_zone_id = zone_id;
                
                // Emit zone change signal for ZoneManager to handle scene loading
                self.base_mut().emit_signal("zone_change", &[
                    (zone_id as i64).to_variant(),
                    GString::from(&zone_name).to_variant(),
                    GString::from(&scene_path).to_variant(),
                    (spawn_position[0] as f64).to_variant(),
                    (spawn_position[1] as f64).to_variant(),
                    (spawn_position[2] as f64).to_variant(),
                ]);
            }
            
            ServerMessage::CommandResponse { success, message } => {
                self.base_mut().emit_signal("command_response", &[
                    success.to_variant(),
                    GString::from(&message).to_variant(),
                ]);
            }
            
            ServerMessage::StatsUpdate { level, experience, experience_to_next_level, max_health, max_mana, attack, defense, gold, health, mana } => {
                // Update local state
                self.level = level;
                self.experience = experience;
                self.experience_to_next_level = experience_to_next_level;
                self.max_health = max_health;
                self.max_mana = max_mana;
                self.attack_power = attack;
                self.defense = defense;
                self.gold = gold;
                self.current_health = health;
                self.current_mana = mana;
                
                // Emit stats updated signal
                self.base_mut().emit_signal("stats_updated", &[
                    (level as i64).to_variant(),
                    (max_health as i64).to_variant(),
                    (max_mana as i64).to_variant(),
                    (attack as i64).to_variant(),
                    (defense as i64).to_variant(),
                    (gold as i64).to_variant(),
                    (health as i64).to_variant(),
                    (mana as i64).to_variant(),
                ]);
                
                // Also emit health_changed for UI update
                self.base_mut().emit_signal("health_changed", &[
                    (health as i64).to_variant(),
                    (max_health as i64).to_variant(),
                ]);
            }
            
            ServerMessage::GoldUpdate { gold } => {
                self.gold = gold;
                self.base_mut().emit_signal("gold_updated", &[(gold as i64).to_variant()]);
            }
            
            ServerMessage::ExperienceGained { amount, current_experience, experience_to_next_level } => {
                self.experience = current_experience;
                self.experience_to_next_level = experience_to_next_level;
                self.base_mut().emit_signal("experience_gained", &[
                    (amount as i64).to_variant(),
                    (current_experience as i64).to_variant(),
                    (experience_to_next_level as i64).to_variant(),
                ]);
            }
            
            ServerMessage::LevelUp { new_level, max_health, max_mana, attack, defense } => {
                self.level = new_level;
                self.max_health = max_health;
                self.max_mana = max_mana;
                self.attack_power = attack;
                self.defense = defense;
                // Level up heals to full
                self.current_health = max_health;
                self.current_mana = max_mana;
                
                self.base_mut().emit_signal("level_up", &[
                    (new_level as i64).to_variant(),
                    (max_health as i64).to_variant(),
                    (max_mana as i64).to_variant(),
                    (attack as i64).to_variant(),
                    (defense as i64).to_variant(),
                ]);
                
                // Also emit health_changed for UI update
                self.base_mut().emit_signal("health_changed", &[
                    (max_health as i64).to_variant(),
                    (max_health as i64).to_variant(),
                ]);
            }
            
            ServerMessage::AbilityUsed { caster_id, ability_id, target_id } => {
                self.base_mut().emit_signal("ability_used", &[
                    (caster_id as i64).to_variant(),
                    (ability_id as i64).to_variant(),
                    (target_id.unwrap_or(0) as i64).to_variant(),
                ]);
            }
            
            ServerMessage::AbilityFailed { ability_id, reason } => {
                self.base_mut().emit_signal("ability_failed", &[
                    (ability_id as i64).to_variant(),
                    GString::from(&reason).to_variant(),
                ]);
            }
            
            ServerMessage::AbilityCooldown { ability_id, remaining, total } => {
                self.base_mut().emit_signal("ability_cooldown", &[
                    (ability_id as i64).to_variant(),
                    (remaining as f64).to_variant(),
                    (total as f64).to_variant(),
                ]);
            }
            
            ServerMessage::BuffApplied { target_id, buff_id, ability_id, duration, is_debuff } => {
                self.base_mut().emit_signal("buff_applied", &[
                    (target_id as i64).to_variant(),
                    (buff_id as i64).to_variant(),
                    (ability_id as i64).to_variant(),
                    (duration as f64).to_variant(),
                    is_debuff.to_variant(),
                ]);
            }
            
            ServerMessage::BuffRemoved { target_id, buff_id } => {
                self.base_mut().emit_signal("buff_removed", &[
                    (target_id as i64).to_variant(),
                    (buff_id as i64).to_variant(),
                ]);
            }
            
            ServerMessage::HealEvent { healer_id, target_id, amount, target_new_health } => {
                // If we were the target, update our health
                if let Some(my_id) = self.player_id {
                    if target_id == my_id {
                        self.current_health = target_new_health;
                        let max_hp = self.max_health;
                        self.base_mut().emit_signal("health_changed", &[
                            (target_new_health as i64).to_variant(),
                            (max_hp as i64).to_variant(),
                        ]);
                    }
                }
                
                self.base_mut().emit_signal("heal_received", &[
                    (healer_id as i64).to_variant(),
                    (target_id as i64).to_variant(),
                    (amount as i64).to_variant(),
                    (target_new_health as i64).to_variant(),
                ]);
            }
            
            ServerMessage::ActionBarUpdate { slots } => {
                let mut arr = Array::new();
                for slot in slots.iter() {
                    arr.push(slot.map(|id| id as i64).unwrap_or(-1));
                }
                self.base_mut().emit_signal("action_bar_received", &[arr.to_variant()]);
            }
            
            // Handle other messages as needed
            _ => {}
        }
    }
}
