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
    
    /// Level
    level: u32,
    
    /// Experience
    experience: u32,
    
    /// Inventory (20 slots)
    inventory: Vec<Option<InventorySlot>>,
    
    /// Movement direction set by camera controller (for both-button movement)
    camera_movement_direction: Option<Vector3>,
    
    /// Camera forward direction (set by camera controller each frame)
    camera_forward: Vector3,
    
    /// Camera right direction (set by camera controller each frame)
    camera_right: Vector3,

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
            current_health: 100,
            max_health: 100,
            current_mana: 50,
            max_mana: 50,
            attack_power: 10,
            defense: 5,
            level: 1,
            experience: 0,
            inventory: vec![None; 20],
            camera_movement_direction: None,
            camera_forward: Vector3::new(0.0, 0.0, -1.0),
            camera_right: Vector3::new(1.0, 0.0, 0.0),
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
        
        let gravity = 9.8_f32;
        
        // Apply gravity when not on floor
        if !self.base().is_on_floor() {
            let mut velocity = self.base().get_velocity();
            velocity.y -= gravity * delta as f32;
            self.base_mut().set_velocity(velocity);
        }

        // Only process input for local player when connected
        if self.is_local && self.is_connected_to_server() {
            self.process_input(delta);
        }
        
        // Always process network (handles login responses, etc.)
        if self.is_local {
            self.process_network();
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
    fn enemy_state_updated(id: i64, position: Vector3, rotation: f64, health: i64);
    
    /// Signal emitted when a remote player's state is updated (from WorldState)
    #[signal]
    fn player_state_updated(id: i64, position: Vector3, rotation: f64, health: i64);
    
    /// Signal emitted when local player's health changes
    #[signal]
    fn health_changed(current_health: i64, max_health: i64);

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
            // Still apply deceleration when not controlling
            let mut velocity = self.base().get_velocity();
            velocity.x = velocity.x.lerp(0.0, 0.1);
            velocity.z = velocity.z.lerp(0.0, 0.1);
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
        } else {
            // Decelerate when no input
            velocity.x = velocity.x.lerp(0.0, 0.1);
            velocity.z = velocity.z.lerp(0.0, 0.1);
            self.animation_state = AnimationState::Idle;
        }

        // Handle jump
        if input.is_action_just_pressed("jump") && self.base().is_on_floor() {
            velocity.y = self.jump_velocity;
            self.animation_state = AnimationState::Jumping;
        }

        self.base_mut().set_velocity(velocity);
        self.base_mut().move_and_slide();
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
                position,
                rotation,
                health,
                max_health,
                mana,
                max_mana,
                level,
                experience,
                attack,
                defense,
                inventory,
            } => {
                // Store character info
                self.character_id = Some(character_id);
                self.character_name = name;
                self.character_class = Some(class);
                self.character_gender = Some(gender);
                self.character_empire = Some(empire);
                
                // Use character_id as player_id for game world
                self.player_id = Some(character_id);
                
                // Store stats
                self.current_health = health;
                self.max_health = max_health;
                self.current_mana = mana;
                self.max_mana = max_mana;
                self.level = level;
                self.experience = experience;
                self.attack_power = attack;
                self.defense = defense;
                self.inventory = inventory;
                
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
            
            ServerMessage::WorldState { tick, players, enemies } => {
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
                    self.base_mut().emit_signal("player_state_updated", &[
                        (player.id as i64).to_variant(),
                        pos.to_variant(),
                        (player.rotation as f64).to_variant(),
                        (player.health as i64).to_variant(),
                    ]);
                }
                
                // Emit updates for each enemy
                for enemy in enemies {
                    let pos = Vector3::new(enemy.position[0], enemy.position[1], enemy.position[2]);
                    self.base_mut().emit_signal("enemy_state_updated", &[
                        (enemy.id as i64).to_variant(),
                        pos.to_variant(),
                        (enemy.rotation as f64).to_variant(),
                        (enemy.health as i64).to_variant(),
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
            
            ServerMessage::EnemySpawn { id, enemy_type, position, health, max_health, level } => {
                let pos = Vector3::new(position[0], position[1], position[2]);
                let enemy_type_int = match enemy_type {
                    mmo_shared::EnemyType::Goblin => 0,
                    mmo_shared::EnemyType::Skeleton => 1,
                    mmo_shared::EnemyType::Wolf => 2,
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
                self.base_mut().emit_signal("entity_died", &[
                    (entity_id as i64).to_variant(),
                    (killer_id.unwrap_or(0) as i64).to_variant(),
                ]);
            }
            
            ServerMessage::EnemyDespawn { id } => {
                self.base_mut().emit_signal("enemy_despawned", &[(id as i64).to_variant()]);
            }
            
            // Handle other messages as needed
            _ => {}
        }
    }
}
