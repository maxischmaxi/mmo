//! UDP Game Server implementation.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::UdpSocket;
use log::{info, warn, error};

use mmo_shared::{
    ClientMessage, ServerMessage, PlayerState, EnemyState, NpcState,
    AnimationState, InventorySlot, CharacterClass, Gender, Empire,
    CharacterInfo, PROTOCOL_VERSION,
};

use crate::world::GameWorld;
use crate::persistence::{PersistenceHandle, Database, PlayerStateData, InventorySlotData, CharacterEquipment};

/// Maximum packet size
const MAX_PACKET_SIZE: usize = 1200;

/// Connection timeout in seconds
const CONNECTION_TIMEOUT: f32 = 30.0;

/// Connection state - tracks whether client is in character select or in game
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionState {
    /// Authenticated but not yet selected a character
    CharacterSelect,
    /// In game with a character
    InGame {
        character_id: i64,
        character_name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
    },
}

/// Client connection state
#[derive(Debug)]
pub struct ClientConnection {
    pub addr: SocketAddr,
    pub player_id: u64,          // Runtime ID (for game world)
    pub db_player_id: i64,       // Database account ID
    pub username: String,        // Account username
    pub state: ConnectionState,  // Connection state
    pub last_seen: std::time::Instant,
    /// Outgoing message queue (reliable messages)
    pub outgoing_queue: Vec<ServerMessage>,
    /// Whether this player is an admin
    pub is_admin: bool,
    /// Last zone ID the client was in (for detecting zone changes)
    pub last_zone_id: Option<u32>,
    /// Set of NPC IDs the client already knows about (to avoid resending static NPCs)
    pub known_npcs: std::collections::HashSet<u64>,
}

impl ClientConnection {
    pub fn new(addr: SocketAddr, player_id: u64, db_player_id: i64, username: String, is_admin: bool) -> Self {
        Self {
            addr,
            player_id,
            db_player_id,
            username,
            state: ConnectionState::CharacterSelect,
            last_seen: std::time::Instant::now(),
            outgoing_queue: Vec::new(),
            is_admin,
            last_zone_id: None,
            known_npcs: std::collections::HashSet::new(),
        }
    }
    
    /// Clear known NPCs (called on zone change)
    pub fn clear_known_npcs(&mut self) {
        self.known_npcs.clear();
    }
    
    pub fn is_timed_out(&self) -> bool {
        self.last_seen.elapsed().as_secs_f32() > CONNECTION_TIMEOUT
    }
    
    /// Check if client is in game
    pub fn is_in_game(&self) -> bool {
        matches!(self.state, ConnectionState::InGame { .. })
    }
    
    /// Get character ID if in game
    pub fn character_id(&self) -> Option<i64> {
        match &self.state {
            ConnectionState::InGame { character_id, .. } => Some(*character_id),
            _ => None,
        }
    }
}

/// Game server
pub struct Server {
    socket: Arc<UdpSocket>,
    clients: HashMap<SocketAddr, ClientConnection>,
    addr_to_player: HashMap<SocketAddr, u64>,
    next_player_id: u64,
    /// Messages to broadcast to all clients
    broadcast_queue: Vec<ServerMessage>,
    /// Persistence handle (optional - server works without it)
    persistence: Option<PersistenceHandle>,
    /// Database for auth (separate from persistence handle for sync operations)
    database: Option<Database>,
}

impl Server {
    /// Create a new server listening on the given port
    pub async fn new(port: u16, persistence: Option<PersistenceHandle>) -> Result<Self, std::io::Error> {
        let addr = format!("0.0.0.0:{}", port);
        let socket = UdpSocket::bind(&addr).await?;
        socket.set_broadcast(true)?;
        
        // Connect to database for auth operations
        let database = if persistence.is_some() {
            match Database::connect("postgres://mmo:mmo_dev_password@localhost:5433/mmo").await {
                Ok(db) => Some(db),
                Err(e) => {
                    error!("Failed to connect to database for auth: {}", e);
                    None
                }
            }
        } else {
            None
        };
        
        Ok(Self {
            socket: Arc::new(socket),
            clients: HashMap::new(),
            addr_to_player: HashMap::new(),
            next_player_id: 1,
            broadcast_queue: Vec::new(),
            persistence,
            database,
        })
    }
    
    /// Process incoming network messages
    pub async fn process_incoming(&mut self, world: &mut GameWorld) {
        let mut buf = [0u8; MAX_PACKET_SIZE];
        
        // Non-blocking receive loop
        loop {
            match self.socket.try_recv_from(&mut buf) {
                Ok((len, addr)) => {
                    self.handle_packet(&buf[..len], addr, world).await;
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    break;
                }
                Err(e) => {
                    error!("Error receiving packet: {}", e);
                    break;
                }
            }
        }
        
        // Check for timed out clients
        self.check_timeouts(world);
    }
    
    /// Handle a received packet
    async fn handle_packet(&mut self, data: &[u8], addr: SocketAddr, world: &mut GameWorld) {
        let message = match ClientMessage::deserialize(data) {
            Ok(msg) => msg,
            Err(e) => {
                warn!("Failed to deserialize packet from {}: {}", addr, e);
                return;
            }
        };
        
        // Update last seen time for known clients
        if let Some(client) = self.clients.get_mut(&addr) {
            client.last_seen = std::time::Instant::now();
        }
        
        match message {
            ClientMessage::Register { username, password } => {
                self.handle_register(addr, username, password).await;
            }
            ClientMessage::Login { protocol_version, username, password } => {
                self.handle_login(addr, protocol_version, username, password).await;
            }
            ClientMessage::GetCharacterList => {
                self.handle_get_character_list(addr).await;
            }
            ClientMessage::CreateCharacter { name, class, gender, empire } => {
                self.handle_create_character(addr, name, class, gender, empire).await;
            }
            ClientMessage::SelectCharacter { character_id } => {
                self.handle_select_character(addr, character_id, world).await;
            }
            ClientMessage::DeleteCharacter { character_id, confirm_name } => {
                self.handle_delete_character(addr, character_id, confirm_name).await;
            }
            ClientMessage::Disconnect => {
                self.handle_disconnect(addr, world).await;
            }
            ClientMessage::PlayerUpdate { position, rotation, velocity, animation_state } => {
                self.handle_player_update(addr, position, rotation, velocity, animation_state, world);
            }
            ClientMessage::ChatMessage { content } => {
                self.handle_chat(addr, content, world);
            }
            ClientMessage::Attack { target_id } => {
                self.handle_attack(addr, target_id, world);
            }
            ClientMessage::PickupItem { item_entity_id } => {
                self.handle_pickup(addr, item_entity_id, world);
            }
            ClientMessage::UseItem { slot } => {
                self.handle_use_item(addr, slot, world);
            }
            ClientMessage::DropItem { slot } => {
                self.handle_drop_item(addr, slot, world);
            }
            ClientMessage::RespawnRequest { respawn_type } => {
                self.handle_respawn(addr, respawn_type, world).await;
            }
            ClientMessage::EquipItem { inventory_slot } => {
                self.handle_equip_item(addr, inventory_slot, world).await;
            }
            ClientMessage::UnequipItem { equipment_slot } => {
                self.handle_unequip_item(addr, equipment_slot, world).await;
            }
            ClientMessage::DevAddItem { item_id, quantity } => {
                self.handle_dev_add_item(addr, item_id, quantity, world).await;
            }
            ClientMessage::TeleportRequest { zone_id } => {
                self.handle_teleport_request(addr, zone_id, world).await;
            }
            ClientMessage::SwapInventorySlots { from_slot, to_slot } => {
                self.handle_swap_inventory_slots(addr, from_slot, to_slot, world).await;
            }
            ClientMessage::UseAbility { ability_id, target_id } => {
                self.handle_use_ability(addr, ability_id, target_id, world);
            }
        }
    }
    
    /// Handle registration request
    async fn handle_register(&mut self, addr: SocketAddr, username: String, password: String) {
        let db = match &self.database {
            Some(db) => db,
            None => {
                let msg = ServerMessage::RegisterFailed {
                    reason: "Server persistence not available".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        // Validate username
        if username.len() < 3 || username.len() > 32 {
            let msg = ServerMessage::RegisterFailed {
                reason: "Username must be 3-32 characters".to_string(),
            };
            self.send_to(addr, &msg).await;
            return;
        }
        
        // Validate password
        if password.len() < 4 {
            let msg = ServerMessage::RegisterFailed {
                reason: "Password must be at least 4 characters".to_string(),
            };
            self.send_to(addr, &msg).await;
            return;
        }
        
        // Register in database
        match db.register_player(&username, &password).await {
            Ok(player_id) => {
                info!("New player registered: {} (ID: {})", username, player_id);
                let msg = ServerMessage::RegisterSuccess {
                    player_id: player_id as u64,
                };
                self.send_to(addr, &msg).await;
            }
            Err(e) => {
                warn!("Registration failed for {}: {}", username, e);
                let msg = ServerMessage::RegisterFailed {
                    reason: e.to_string(),
                };
                self.send_to(addr, &msg).await;
            }
        }
    }
    
    /// Handle login request - only authenticates, does not spawn player
    async fn handle_login(
        &mut self,
        addr: SocketAddr,
        protocol_version: u32,
        username: String,
        password: String,
    ) {
        // Check protocol version
        if protocol_version != PROTOCOL_VERSION {
            let msg = ServerMessage::LoginFailed {
                reason: format!("Protocol version mismatch. Server: {}, Client: {}", 
                    PROTOCOL_VERSION, protocol_version),
            };
            self.send_to(addr, &msg).await;
            return;
        }
        
        // Check if already connected from this address
        if self.clients.contains_key(&addr) {
            warn!("Client {} already connected, ignoring", addr);
            return;
        }
        
        // Authenticate with database
        let db = match &self.database {
            Some(db) => db,
            None => {
                let msg = ServerMessage::LoginFailed {
                    reason: "Server persistence not available".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        let db_player_id = match db.authenticate_player(&username, &password).await {
            Ok(id) => id,
            Err(e) => {
                warn!("Login failed for {}: {}", username, e);
                let msg = ServerMessage::LoginFailed {
                    reason: "Invalid username or password".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        // Check if account is already connected - kick the old connection
        let existing_addr: Option<SocketAddr> = self.clients
            .iter()
            .find(|(_, c)| c.db_player_id == db_player_id)
            .map(|(a, _)| *a);
        
        if let Some(old_addr) = existing_addr {
            info!("Kicking existing connection for account {} (reconnecting)", db_player_id);
            // We'll let the old connection timeout or send disconnect
            // For now just remove it (state will be saved when disconnect is processed)
            self.clients.remove(&old_addr);
            self.addr_to_player.remove(&old_addr);
        }
        
        // Assign runtime player ID (for potential future in-game use)
        let player_id = self.next_player_id;
        self.next_player_id += 1;
        
        // Check if player is admin
        let is_admin = match db.is_player_admin(db_player_id).await {
            Ok(admin) => admin,
            Err(e) => {
                warn!("Failed to check admin status for {}: {}", db_player_id, e);
                false
            }
        };
        
        // Create connection in CharacterSelect state
        let connection = ClientConnection::new(addr, player_id, db_player_id, username.clone(), is_admin);
        self.clients.insert(addr, connection);
        self.addr_to_player.insert(addr, player_id);
        
        // Update last login timestamp
        if let Some(ref persistence) = self.persistence {
            persistence.update_last_login(db_player_id);
        }
        
        let admin_str = if is_admin { " [ADMIN]" } else { "" };
        info!("Account '{}' (DB: {}){} authenticated from {}", username, db_player_id, admin_str, addr);
        
        // Send login success - client should now request character list
        let msg = ServerMessage::LoginSuccess {
            player_id: db_player_id as u64,
        };
        self.send_to(addr, &msg).await;
    }
    
    /// Handle get character list request
    async fn handle_get_character_list(&mut self, addr: SocketAddr) {
        let client = match self.clients.get(&addr) {
            Some(c) => c,
            None => {
                warn!("GetCharacterList from unknown client {}", addr);
                return;
            }
        };
        
        let db = match &self.database {
            Some(db) => db,
            None => {
                warn!("No database available for character list");
                return;
            }
        };
        
        let db_player_id = client.db_player_id;
        
        match db.get_characters(db_player_id).await {
            Ok(characters) => {
                let msg = ServerMessage::CharacterList { characters };
                self.send_to(addr, &msg).await;
            }
            Err(e) => {
                error!("Failed to get character list for {}: {}", db_player_id, e);
            }
        }
    }
    
    /// Handle create character request
    async fn handle_create_character(
        &mut self,
        addr: SocketAddr,
        name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
    ) {
        let client = match self.clients.get(&addr) {
            Some(c) => c,
            None => {
                warn!("CreateCharacter from unknown client {}", addr);
                return;
            }
        };
        
        let db = match &self.database {
            Some(db) => db,
            None => {
                let msg = ServerMessage::CharacterCreateFailed {
                    reason: "Server persistence not available".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        let db_player_id = client.db_player_id;
        
        match db.create_character(db_player_id, &name, class, gender, empire).await {
            Ok(character) => {
                info!("Character '{}' created for account {}", name, db_player_id);
                let msg = ServerMessage::CharacterCreated { character };
                self.send_to(addr, &msg).await;
            }
            Err(e) => {
                warn!("Failed to create character for {}: {}", db_player_id, e);
                let msg = ServerMessage::CharacterCreateFailed {
                    reason: e.to_string(),
                };
                self.send_to(addr, &msg).await;
            }
        }
    }
    
    /// Handle select character request - spawns player into game
    async fn handle_select_character(
        &mut self,
        addr: SocketAddr,
        character_id: u64,
        world: &mut GameWorld,
    ) {
        let (db_player_id, player_id, username) = {
            let client = match self.clients.get(&addr) {
                Some(c) => c,
                None => {
                    warn!("SelectCharacter from unknown client {}", addr);
                    return;
                }
            };
            
            // Check if already in game
            if client.is_in_game() {
                let msg = ServerMessage::CharacterSelectFailed {
                    reason: "Already in game".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
            
            (client.db_player_id, client.player_id, client.username.clone())
        };
        
        let db = match &self.database {
            Some(db) => db,
            None => {
                let msg = ServerMessage::CharacterSelectFailed {
                    reason: "Server persistence not available".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        // Load character data
        let character = match db.get_character(character_id as i64, db_player_id).await {
            Ok(Some(c)) => c,
            Ok(None) => {
                let msg = ServerMessage::CharacterSelectFailed {
                    reason: "Character not found".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
            Err(e) => {
                error!("Failed to load character {}: {}", character_id, e);
                let msg = ServerMessage::CharacterSelectFailed {
                    reason: "Database error".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        // Load character state, inventory, and equipment
        let (player_state, inventory_data, equipment) = match (
            db.load_character_state(character_id as i64).await,
            db.load_character_inventory(character_id as i64).await,
            db.load_character_equipment(character_id as i64).await,
        ) {
            (Ok(Some(state)), Ok(inv), Ok(equip)) => (state, inv, equip),
            (Ok(None), Ok(inv), Ok(equip)) => {
                // No state yet - use default for class
                (PlayerStateData::new_for_class(character.class, character.empire), inv, equip)
            }
            (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => {
                error!("Failed to load character state for {}: {}", character_id, e);
                let msg = ServerMessage::CharacterSelectFailed {
                    reason: "Failed to load character state".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        // Update connection state to InGame
        if let Some(client) = self.clients.get_mut(&addr) {
            client.state = ConnectionState::InGame {
                character_id: character.id,
                character_name: character.name.clone(),
                class: character.class,
                gender: character.gender,
                empire: character.empire,
            };
        }
        
        // Determine zone_id - use saved zone or fallback to empire default
        let zone_id = if player_state.zone_id > 0 && world.zone_manager.zone_exists(player_state.zone_id as u32) {
            player_state.zone_id as u32
        } else {
            world.zone_manager.get_default_zone_for_empire(character.empire)
        };
        
        // If player has 0 health (died and logged out), respawn them at zone spawn with 20% HP
        // Also reset players who fell through the world (Y < -50)
        let (spawn_position, spawn_health) = if player_state.health <= 0 {
            let zone_spawn = world.zone_manager.get_default_spawn_point(zone_id);
            let respawn_health = (player_state.max_health as f32 * 0.2).max(1.0) as i32;
            info!("Character '{}' was dead, respawning at zone {} spawn with {} HP", character.name, zone_id, respawn_health);
            (zone_spawn, respawn_health)
        } else if player_state.position_y < -50.0 {
            // Player fell through the world - reset to zone spawn
            let zone_spawn = world.zone_manager.get_default_spawn_point(zone_id);
            info!("Character '{}' was below world (Y={}), resetting to zone {} spawn", 
                  character.name, player_state.position_y, zone_id);
            (zone_spawn, player_state.health)
        } else {
            ([player_state.position_x, player_state.position_y, player_state.position_z], player_state.health)
        };
        
        // Spawn player in world
        world.spawn_player_with_state(
            player_id,
            character.name.clone(),
            character.class,
            character.gender,
            character.empire,
            zone_id,
            spawn_position,
            player_state.rotation,
            spawn_health as u32,
            player_state.max_health as u32,
            player_state.mana as u32,
            player_state.max_mana as u32,
            player_state.attack as u32,
            player_state.defense as u32,
            &inventory_data,
            equipment.weapon_id,
            equipment.armor_id,
            player_state.level as u32,
            player_state.experience as u32,
            player_state.gold as u64,
        );
        
        info!("Character '{}' (ID: {}) entered game for account '{}'", 
              character.name, character_id, username);
        
        // Convert inventory for protocol
        let inventory_slots = inventory_data_to_slots(&inventory_data);
        
        // Calculate attack speed from class and weapon
        let attack_speed = if let Some(player) = world.get_player(player_id) {
            player.get_attack_speed(&world.items)
        } else {
            character.class.base_attack_speed()
        };
        
        // Calculate XP to next level
        let experience_to_next_level = ServerPlayer::experience_to_next_level(player_state.level as u32);
        
        // Send character selected with full state
        let msg = ServerMessage::CharacterSelected {
            character_id,
            name: character.name.clone(),
            class: character.class,
            gender: character.gender,
            empire: character.empire,
            zone_id,
            position: spawn_position,
            rotation: player_state.rotation,
            health: spawn_health as u32,
            max_health: player_state.max_health as u32,
            mana: player_state.mana as u32,
            max_mana: player_state.max_mana as u32,
            level: player_state.level as u32,
            experience: player_state.experience as u32,
            experience_to_next_level,
            attack: player_state.attack as u32,
            defense: player_state.defense as u32,
            attack_speed,
            inventory: inventory_slots,
            equipped_weapon_id: equipment.weapon_id,
            equipped_armor_id: equipment.armor_id,
            gold: player_state.gold as u64,
        };
        self.send_to(addr, &msg).await;
        
        // Send ZoneChange message with zone info
        if let Some(zone) = world.zone_manager.get_zone(zone_id) {
            let zone_change_msg = ServerMessage::ZoneChange {
                zone_id,
                zone_name: zone.name.clone(),
                scene_path: zone.scene_path.clone(),
                spawn_position,
            };
            self.send_to(addr, &zone_change_msg).await;
        }
        
        // Send action bar (abilities assigned to slots)
        if let Some(action_bar) = world.get_player_action_bar(player_id) {
            let action_bar_msg = ServerMessage::ActionBarUpdate { slots: action_bar };
            self.send_to(addr, &action_bar_msg).await;
        }
        
        // Send time sync for day/night cycle (Berlin, Germany coordinates)
        let time_sync_msg = ServerMessage::TimeSync {
            unix_timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64,
            latitude: 52.5,   // Berlin latitude
            longitude: 13.4,  // Berlin longitude
        };
        self.send_to(addr, &time_sync_msg).await;
        
        // Notify other players in the SAME ZONE (only those in game)
        let spawn_msg = ServerMessage::PlayerSpawn {
            id: player_id,
            name: character.name.clone(),
            class: character.class,
            gender: character.gender,
            empire: character.empire,
            zone_id,
            position: spawn_position,
            rotation: player_state.rotation,
        };
        self.broadcast_to_zone_except(addr, zone_id, spawn_msg, world);
        
        // Send existing players and enemies IN THE SAME ZONE to new client
        let mut messages_for_new_client: Vec<ServerMessage> = Vec::new();
        
        for (other_addr, other_client) in &self.clients {
            if *other_addr != addr {
                if let ConnectionState::InGame { character_name, class, gender, empire, .. } = &other_client.state {
                    if let Some(player) = world.get_player(other_client.player_id) {
                        // Only send players in the same zone
                        if player.zone_id == zone_id {
                            messages_for_new_client.push(ServerMessage::PlayerSpawn {
                                id: other_client.player_id,
                                name: character_name.clone(),
                                class: *class,
                                gender: *gender,
                                empire: *empire,
                                zone_id: player.zone_id,
                                position: player.position,
                                rotation: player.rotation,
                            });
                        }
                    }
                }
            }
        }
        
        // Only send enemies in the same zone
        for enemy in world.get_enemies_in_zone(zone_id) {
            messages_for_new_client.push(ServerMessage::EnemySpawn {
                id: enemy.id,
                zone_id: enemy.zone_id,
                enemy_type: enemy.enemy_type,
                position: enemy.position,
                health: enemy.health,
                max_health: enemy.max_health,
                level: enemy.level,
            });
        }
        
        if let Some(client) = self.clients.get_mut(&addr) {
            client.outgoing_queue.extend(messages_for_new_client);
        }
    }
    
    /// Handle delete character request
    async fn handle_delete_character(
        &mut self,
        addr: SocketAddr,
        character_id: u64,
        confirm_name: String,
    ) {
        let client = match self.clients.get(&addr) {
            Some(c) => c,
            None => {
                warn!("DeleteCharacter from unknown client {}", addr);
                return;
            }
        };
        
        // Can't delete while in game
        if client.is_in_game() {
            let msg = ServerMessage::CharacterDeleteFailed {
                reason: "Cannot delete while in game".to_string(),
            };
            self.send_to(addr, &msg).await;
            return;
        }
        
        let db = match &self.database {
            Some(db) => db,
            None => {
                let msg = ServerMessage::CharacterDeleteFailed {
                    reason: "Server persistence not available".to_string(),
                };
                self.send_to(addr, &msg).await;
                return;
            }
        };
        
        let db_player_id = client.db_player_id;
        
        match db.delete_character(character_id as i64, db_player_id, &confirm_name).await {
            Ok(()) => {
                info!("Character {} deleted for account {}", character_id, db_player_id);
                let msg = ServerMessage::CharacterDeleted { character_id };
                self.send_to(addr, &msg).await;
            }
            Err(e) => {
                warn!("Failed to delete character {}: {}", character_id, e);
                let msg = ServerMessage::CharacterDeleteFailed {
                    reason: e.to_string(),
                };
                self.send_to(addr, &msg).await;
            }
        }
    }
    
    /// Handle disconnect
    async fn handle_disconnect(&mut self, addr: SocketAddr, world: &mut GameWorld) {
        if let Some(connection) = self.clients.remove(&addr) {
            self.addr_to_player.remove(&addr);
            
            // Only save and despawn if player was in game
            if let ConnectionState::InGame { character_id, character_name, .. } = &connection.state {
                // Save character state before removing
                if let (Some(persistence), Some(player)) = (&self.persistence, world.get_player(connection.player_id)) {
                    let state = player_to_state_data(player);
                    let inventory = player_inventory_to_data(player);
                    persistence.save_character(*character_id, state, inventory);
                    info!("Saved character '{}' state on disconnect", character_name);
                }
                
                world.despawn_player(connection.player_id);
                
                info!("Character '{}' (player ID: {}) disconnected", character_name, connection.player_id);
                
                // Notify other players in game
                let msg = ServerMessage::PlayerDespawn {
                    id: connection.player_id,
                };
                self.broadcast_to_ingame(msg);
            } else {
                info!("Account '{}' disconnected (was in character select)", connection.username);
            }
        }
    }
    
    /// Handle player position/state update
    fn handle_player_update(
        &mut self,
        addr: SocketAddr,
        position: [f32; 3],
        rotation: f32,
        velocity: [f32; 3],
        animation_state: AnimationState,
        world: &mut GameWorld,
    ) {
        // Only process if client is in game
        let client = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c,
            _ => return,
        };
        
        world.update_player_state(client.player_id, position, rotation, velocity, animation_state);
    }
    
    /// Handle chat message
    fn handle_chat(&mut self, addr: SocketAddr, content: String, world: &mut GameWorld) {
        let (player_id, is_admin, sender_name) = {
            let connection = match self.clients.get(&addr) {
                Some(c) => c,
                None => return,
            };
            
            // Get character name if in game, otherwise reject
            let sender_name = match &connection.state {
                ConnectionState::InGame { character_name, .. } => character_name.clone(),
                ConnectionState::CharacterSelect => return, // Can't chat from char select
            };
            
            (connection.player_id, connection.is_admin, sender_name)
        };
        
        // Check if it's a command
        if content.starts_with('/') {
            // Parse and execute command
            if let Some(result) = crate::commands::parse_and_execute(&content, player_id, is_admin, world) {
                // Send command response to the player
                let response_msg = ServerMessage::CommandResponse {
                    success: result.success,
                    message: result.message,
                };
                if let Some(client) = self.clients.get_mut(&addr) {
                    client.outgoing_queue.push(response_msg);
                    
                    // Send stats update if present
                    if let Some(stats_msg) = result.stats_update {
                        client.outgoing_queue.push(stats_msg);
                    }
                    
                    // Send gold update if present
                    if let Some(gold_msg) = result.gold_update {
                        client.outgoing_queue.push(gold_msg);
                    }
                    
                    // Send inventory update if present
                    if let Some(inv_msg) = result.inventory_update {
                        client.outgoing_queue.push(inv_msg);
                    }
                    
                    // Send teleport if present
                    if let Some(teleport_msg) = result.teleport {
                        client.outgoing_queue.push(teleport_msg);
                    }
                }
            }
            return; // Don't broadcast commands to chat
        }
        
        // Regular chat message - broadcast to all
        let msg = ServerMessage::ChatBroadcast {
            sender_id: player_id,
            sender_name,
            content,
        };
        self.broadcast_to_ingame(msg);
    }
    
    /// Handle attack request
    fn handle_attack(&mut self, addr: SocketAddr, target_id: u64, world: &mut GameWorld) {
        let client = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c,
            _ => return,
        };
        
        if let Some(damage_event) = world.process_attack(client.player_id, target_id) {
            self.broadcast_to_ingame(damage_event);
        }
    }
    
    /// Handle ability use request
    fn handle_use_ability(&mut self, addr: SocketAddr, ability_id: u32, target_id: Option<u64>, world: &mut GameWorld) {
        let player_id = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c.player_id,
            _ => return,
        };
        
        let (caster_msgs, broadcast_msgs) = world.process_ability(player_id, ability_id, target_id);
        
        // Send caster-specific messages
        if let Some(client) = self.clients.get_mut(&addr) {
            client.outgoing_queue.extend(caster_msgs);
        }
        
        // Broadcast to all players in game
        for msg in broadcast_msgs {
            self.broadcast_to_ingame(msg);
        }
    }
    
    /// Handle item pickup
    fn handle_pickup(&mut self, addr: SocketAddr, item_entity_id: u64, world: &mut GameWorld) {
        let player_id = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c.player_id,
            _ => return,
        };
        
        if let Some((despawn_msg, inv_msg)) = world.pickup_item(player_id, item_entity_id) {
            self.broadcast_to_ingame(despawn_msg);
            // Send inventory update only to the player who picked up
            if let Some(client) = self.clients.get_mut(&addr) {
                client.outgoing_queue.push(inv_msg);
            }
        }
    }
    
    /// Handle use item
    fn handle_use_item(&mut self, addr: SocketAddr, slot: u8, world: &mut GameWorld) {
        let player_id = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c.player_id,
            _ => return,
        };
        
        if let Some(inv_msg) = world.use_item(player_id, slot) {
            if let Some(client) = self.clients.get_mut(&addr) {
                client.outgoing_queue.push(inv_msg);
            }
        }
    }
    
    /// Handle drop item
    fn handle_drop_item(&mut self, addr: SocketAddr, slot: u8, world: &mut GameWorld) {
        let player_id = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c.player_id,
            _ => return,
        };
        
        if let Some((spawn_msg, inv_msg)) = world.drop_item(player_id, slot) {
            self.broadcast_to_ingame(spawn_msg);
            if let Some(client) = self.clients.get_mut(&addr) {
                client.outgoing_queue.push(inv_msg);
            }
        }
    }
    
    /// Handle respawn request
    /// respawn_type: 0 = at empire spawn (full health), 1 = at death location (20% health)
    async fn handle_respawn(&mut self, addr: SocketAddr, respawn_type: u8, world: &mut GameWorld) {
        let (player_id, empire) = match self.clients.get(&addr) {
            Some(c) => {
                if let ConnectionState::InGame { empire, .. } = &c.state {
                    (c.player_id, *empire)
                } else {
                    return;
                }
            }
            _ => return,
        };
        
        // Get player's current (death) position and max health
        let (death_position, max_health) = match world.get_player(player_id) {
            Some(p) => (p.position, p.max_health),
            None => return,
        };
        
        // Calculate respawn position and health based on respawn type
        let (respawn_position, respawn_health) = if respawn_type == 0 {
            // Respawn at empire spawn with full health
            (empire.spawn_position(), max_health)
        } else {
            // Respawn at death location with 20% health
            let health_20_percent = (max_health as f32 * 0.2).max(1.0) as u32;
            (death_position, health_20_percent)
        };
        
        // Respawn the player in the world
        world.respawn_player(player_id, respawn_position, respawn_health);
        
        info!("Player {} respawned (type: {}) at {:?} with {} health", 
              player_id, respawn_type, respawn_position, respawn_health);
        
        // Send respawn response to the player
        let respawn_msg = ServerMessage::PlayerRespawned {
            position: respawn_position,
            health: respawn_health,
            max_health,
        };
        if let Some(client) = self.clients.get_mut(&addr) {
            client.outgoing_queue.push(respawn_msg);
        }
        
        // Broadcast entity respawn to other players
        let broadcast_msg = ServerMessage::EntityRespawn {
            entity_id: player_id,
            position: respawn_position,
            health: respawn_health,
        };
        self.broadcast_to_ingame_except(addr, broadcast_msg);
    }
    
    /// Handle equip item request
    async fn handle_equip_item(&mut self, addr: SocketAddr, inventory_slot: u8, world: &mut GameWorld) {
        let (player_id, character_id) = match self.clients.get(&addr) {
            Some(c) => {
                if let ConnectionState::InGame { character_id, .. } = &c.state {
                    (c.player_id, *character_id)
                } else {
                    return;
                }
            }
            _ => return,
        };
        
        // Try to equip the item
        let result = world.equip_item(player_id, inventory_slot);
        
        match result {
            Ok(equip_result) => {
                // Get current equipment state
                let (weapon_id, armor_id) = if let Some(player) = world.get_player(player_id) {
                    (player.equipped_weapon_id, player.equipped_armor_id)
                } else {
                    (None, None)
                };
                
                // Save equipment to database based on what was equipped
                if let Some(ref db) = self.database {
                    match equip_result {
                        crate::world::EquipResult::Weapon(_) => {
                            if let Err(e) = db.save_character_weapon(character_id, weapon_id).await {
                                error!("Failed to save weapon for character {}: {}", character_id, e);
                            }
                        }
                        crate::world::EquipResult::Armor(_) => {
                            if let Err(e) = db.save_character_armor(character_id, armor_id).await {
                                error!("Failed to save armor for character {}: {}", character_id, e);
                            }
                        }
                    }
                }
                
                // Send equipment update to client
                let equip_msg = ServerMessage::EquipmentUpdate {
                    equipped_weapon_id: weapon_id,
                    equipped_armor_id: armor_id,
                };
                
                // Send inventory update (item was removed/swapped)
                let inv_msg = if let Some(player) = world.get_player(player_id) {
                    Some(ServerMessage::InventoryUpdate {
                        slots: player.get_inventory_slots(),
                    })
                } else {
                    None
                };
                
                if let Some(client) = self.clients.get_mut(&addr) {
                    client.outgoing_queue.push(equip_msg);
                    if let Some(inv) = inv_msg {
                        client.outgoing_queue.push(inv);
                    }
                }
                
                match equip_result {
                    crate::world::EquipResult::Weapon(id) => info!("Player {} equipped weapon {:?}", player_id, id),
                    crate::world::EquipResult::Armor(id) => info!("Player {} equipped armor {:?}", player_id, id),
                }
            }
            Err(reason) => {
                warn!("Player {} failed to equip item from slot {}: {}", player_id, inventory_slot, reason);
                // Send error message to client
                if let Some(client) = self.clients.get_mut(&addr) {
                    client.outgoing_queue.push(ServerMessage::CommandResponse {
                        success: false,
                        message: format!("Cannot equip: {}", reason),
                    });
                }
            }
        }
    }
    
    /// Handle unequip item request
    async fn handle_unequip_item(&mut self, addr: SocketAddr, equipment_slot: String, world: &mut GameWorld) {
        let (player_id, character_id) = match self.clients.get(&addr) {
            Some(c) => {
                if let ConnectionState::InGame { character_id, .. } = &c.state {
                    (c.player_id, *character_id)
                } else {
                    return;
                }
            }
            _ => return,
        };
        
        match equipment_slot.as_str() {
            "weapon" => {
                // Unequip the weapon (puts it back in inventory)
                let old_weapon = world.unequip_weapon(player_id);
                
                if old_weapon.is_none() {
                    warn!("Player {} could not unequip weapon (none equipped or no space)", player_id);
                    return;
                }
                
                // Save equipment to database
                if let Some(ref db) = self.database {
                    if let Err(e) = db.save_character_weapon(character_id, None).await {
                        error!("Failed to save weapon for character {}: {}", character_id, e);
                    }
                }
                
                info!("Player {} unequipped weapon {:?}", player_id, old_weapon);
            }
            "armor" => {
                // Unequip the armor (puts it back in inventory)
                let old_armor = world.unequip_armor(player_id);
                
                if old_armor.is_none() {
                    warn!("Player {} could not unequip armor (none equipped or no space)", player_id);
                    return;
                }
                
                // Save equipment to database
                if let Some(ref db) = self.database {
                    if let Err(e) = db.save_character_armor(character_id, None).await {
                        error!("Failed to save armor for character {}: {}", character_id, e);
                    }
                }
                
                info!("Player {} unequipped armor {:?}", player_id, old_armor);
            }
            _ => {
                warn!("Unknown equipment slot: {}", equipment_slot);
                return;
            }
        }
        
        // Get current equipment state
        let (weapon_id, armor_id) = if let Some(player) = world.get_player(player_id) {
            (player.equipped_weapon_id, player.equipped_armor_id)
        } else {
            (None, None)
        };
        
        // Send equipment update to client
        let equip_msg = ServerMessage::EquipmentUpdate {
            equipped_weapon_id: weapon_id,
            equipped_armor_id: armor_id,
        };
        
        // Send inventory update (item was added back)
        let inv_msg = if let Some(player) = world.get_player(player_id) {
            Some(ServerMessage::InventoryUpdate {
                slots: player.get_inventory_slots(),
            })
        } else {
            None
        };
        
        if let Some(client) = self.clients.get_mut(&addr) {
            client.outgoing_queue.push(equip_msg);
            if let Some(inv) = inv_msg {
                client.outgoing_queue.push(inv);
            }
        }
    }
    
    /// Handle dev add item command (debug only)
    async fn handle_dev_add_item(&mut self, addr: SocketAddr, item_id: u32, quantity: u32, world: &mut GameWorld) {
        let player_id = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c.player_id,
            _ => return,
        };
        
        // Verify item exists
        if !world.items.contains_key(&item_id) {
            warn!("Dev add item: unknown item ID {}", item_id);
            return;
        }
        
        // Add item to player's inventory
        if let Some(inv_msg) = world.add_item_to_player(player_id, item_id, quantity) {
            if let Some(client) = self.clients.get_mut(&addr) {
                client.outgoing_queue.push(inv_msg);
            }
            info!("Dev: Added {}x item {} to player {}", quantity, item_id, player_id);
        }
    }
    
    /// Handle teleport request via Teleport Ring
    async fn handle_teleport_request(&mut self, addr: SocketAddr, zone_id: u32, world: &mut GameWorld) {
        let (player_id, current_zone_id) = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => {
                let pid = c.player_id;
                let zone = world.get_player(pid).map(|p| p.zone_id).unwrap_or(0);
                (pid, zone)
            },
            _ => return,
        };
        
        // Check if target zone exists
        if !world.zone_manager.zone_exists(zone_id) {
            warn!("Teleport request to non-existent zone {} from player {}", zone_id, player_id);
            // Could send TeleportFailed message here
            return;
        }
        
        // Don't teleport to the same zone
        if current_zone_id == zone_id {
            info!("Player {} already in zone {}, ignoring teleport request", player_id, zone_id);
            return;
        }
        
        // Get spawn point for target zone
        let spawn_position = world.zone_manager.get_default_spawn_point(zone_id);
        
        // Get zone info
        let (zone_name, scene_path) = match world.zone_manager.get_zone(zone_id) {
            Some(zone) => (zone.name.clone(), zone.scene_path.clone()),
            None => {
                warn!("Zone {} not found in zone_manager", zone_id);
                return;
            }
        };
        
        info!("Player {} teleporting from zone {} to zone {} ({})", 
              player_id, current_zone_id, zone_id, zone_name);
        
        // Update player's zone and position
        if let Some(player) = world.get_player_mut(player_id) {
            player.zone_id = zone_id;
            player.position = spawn_position;
        }
        
        // Broadcast PlayerDespawn to OLD zone players
        let despawn_msg = ServerMessage::PlayerDespawn { id: player_id };
        self.broadcast_to_zone_except(addr, current_zone_id, despawn_msg, world);
        
        // Send ZoneChange to the teleporting player
        let zone_change_msg = ServerMessage::ZoneChange {
            zone_id,
            zone_name: zone_name.clone(),
            scene_path,
            spawn_position,
        };
        if let Some(client) = self.clients.get_mut(&addr) {
            client.outgoing_queue.push(zone_change_msg);
        }
        
        // Broadcast PlayerSpawn to NEW zone players (get fresh player data)
        if let Some(player) = world.get_player(player_id) {
            let spawn_msg = ServerMessage::PlayerSpawn {
                id: player_id,
                name: player.name.clone(),
                class: player.class,
                gender: player.gender,
                empire: player.empire,
                position: spawn_position,
                rotation: player.rotation,
                zone_id,
            };
            self.broadcast_to_zone_except(addr, zone_id, spawn_msg, world);
            
            // Send existing players in new zone to the teleporting player
            for other_player in world.get_players_in_zone(zone_id) {
                if other_player.id != player_id {
                    let other_spawn_msg = ServerMessage::PlayerSpawn {
                        id: other_player.id,
                        name: other_player.name.clone(),
                        class: other_player.class,
                        gender: other_player.gender,
                        empire: other_player.empire,
                        position: other_player.position,
                        rotation: other_player.rotation,
                        zone_id: other_player.zone_id,
                    };
                    if let Some(client) = self.clients.get_mut(&addr) {
                        client.outgoing_queue.push(other_spawn_msg);
                    }
                }
            }
            
            // Send existing enemies in new zone to the teleporting player
            for enemy in world.get_enemies_in_zone(zone_id) {
                let enemy_spawn_msg = ServerMessage::EnemySpawn {
                    id: enemy.id,
                    enemy_type: enemy.enemy_type,
                    position: enemy.position,
                    health: enemy.health as u32,
                    max_health: enemy.max_health as u32,
                    level: enemy.level,
                    zone_id: enemy.zone_id,
                };
                if let Some(client) = self.clients.get_mut(&addr) {
                    client.outgoing_queue.push(enemy_spawn_msg);
                }
            }
        }
        
        info!("Player {} teleported to {} successfully", player_id, zone_name);
    }
    
    /// Handle inventory slot swap (drag & drop)
    async fn handle_swap_inventory_slots(&mut self, addr: SocketAddr, from_slot: u8, to_slot: u8, world: &mut GameWorld) {
        let player_id = match self.clients.get(&addr) {
            Some(c) if c.is_in_game() => c.player_id,
            _ => return,
        };
        
        // Validate slot indices
        if from_slot >= 20 || to_slot >= 20 {
            warn!("Invalid slot indices for swap: {} -> {}", from_slot, to_slot);
            return;
        }
        
        // Same slot - nothing to do
        if from_slot == to_slot {
            return;
        }
        
        if let Some(inv_msg) = world.swap_inventory_slots(player_id, from_slot, to_slot) {
            if let Some(client) = self.clients.get_mut(&addr) {
                client.outgoing_queue.push(inv_msg);
            }
            info!("Player {} swapped inventory slots {} <-> {}", player_id, from_slot, to_slot);
        }
    }
    
    /// Check for timed out connections
    fn check_timeouts(&mut self, world: &mut GameWorld) {
        let timed_out: Vec<(SocketAddr, ClientConnection)> = self.clients
            .iter()
            .filter(|(_, c)| c.is_timed_out())
            .map(|(addr, c)| (*addr, ClientConnection {
                addr: c.addr,
                player_id: c.player_id,
                db_player_id: c.db_player_id,
                username: c.username.clone(),
                state: c.state.clone(),
                last_seen: c.last_seen,
                outgoing_queue: Vec::new(),
                is_admin: c.is_admin,
                last_zone_id: c.last_zone_id,
                known_npcs: c.known_npcs.clone(),
            }))
            .collect();
        
        for (addr, connection) in timed_out {
            // Save character state before removing if in game
            if let ConnectionState::InGame { character_id, character_name, .. } = &connection.state {
                if let (Some(persistence), Some(player)) = (&self.persistence, world.get_player(connection.player_id)) {
                    let state = player_to_state_data(player);
                    let inventory = player_inventory_to_data(player);
                    persistence.save_character(*character_id, state, inventory);
                    info!("Saved character '{}' state on timeout", character_name);
                }
                
                world.despawn_player(connection.player_id);
                
                warn!("Character '{}' timed out", character_name);
                
                let msg = ServerMessage::PlayerDespawn { id: connection.player_id };
                self.broadcast_to_ingame(msg);
            } else {
                warn!("Account '{}' timed out (was in character select)", connection.username);
            }
            
            self.clients.remove(&addr);
            self.addr_to_player.remove(&addr);
        }
    }
    
    /// Broadcast time sync to all connected in-game clients
    /// Called periodically (every 60 seconds) to keep client time synchronized
    pub async fn broadcast_time_sync(&self) {
        let time_sync_msg = ServerMessage::TimeSync {
            unix_timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64,
            latitude: 52.5,   // Berlin latitude
            longitude: 13.4,  // Berlin longitude
        };
        
        let data = time_sync_msg.serialize();
        
        // Only send to clients that are in-game
        for (addr, client) in &self.clients {
            if client.is_in_game() {
                if let Err(e) = self.socket.send_to(&data, addr).await {
                    error!("Failed to send time sync to {}: {}", addr, e);
                }
            }
        }
    }
    
    /// Broadcast world state to all connected clients (zone-filtered)
    /// Each client only receives players and enemies in their current zone
    /// NPCs are only sent once per zone (they're static)
    pub async fn broadcast_world_state(&mut self, world: &GameWorld, tick: u64) {
        // Collect data for each client first to avoid borrow issues
        let mut client_updates: Vec<(SocketAddr, ServerMessage, Vec<u64>)> = Vec::new();
        
        for (addr, client) in &self.clients {
            // Only send to in-game clients
            if !client.is_in_game() {
                continue;
            }
            
            // Get the player's current zone
            let player_zone_id = match world.get_player(client.player_id) {
                Some(p) => p.zone_id,
                None => continue, // Player not in world, skip
            };
            
            // Check if zone changed - if so, we need to send NPCs
            let zone_changed = client.last_zone_id != Some(player_zone_id);
            
            // Get players in the same zone
            let players: Vec<PlayerState> = world.get_players_in_zone(player_zone_id)
                .iter()
                .map(|p| PlayerState {
                    id: p.id,
                    zone_id: p.zone_id,
                    position: p.position,
                    rotation: p.rotation,
                    velocity: p.velocity,
                    health: p.health,
                    max_health: p.max_health,
                    animation_state: p.animation_state,
                    equipped_weapon_id: p.equipped_weapon_id,
                    equipped_armor_id: p.equipped_armor_id,
                })
                .collect();
            
            // Get enemies in the same zone
            let enemies: Vec<EnemyState> = world.get_enemies_in_zone(player_zone_id)
                .iter()
                .map(|e| EnemyState {
                    id: e.id,
                    zone_id: e.zone_id,
                    enemy_type: e.enemy_type,
                    position: e.position,
                    rotation: e.rotation,
                    health: e.health,
                    max_health: e.max_health,
                    level: e.level,
                    animation_state: e.animation_state,
                    target_id: e.target_id,
                })
                .collect();
            
            // Only include NPCs that the client doesn't know about yet
            // (NPCs are static, so we only need to send them once per zone)
            let mut new_npc_ids: Vec<u64> = Vec::new();
            let npcs: Vec<NpcState> = if zone_changed {
                // Zone changed - send all NPCs in new zone
                world.get_npcs_in_zone(player_zone_id)
                    .iter()
                    .map(|n| {
                        new_npc_ids.push(n.id);
                        NpcState {
                            id: n.id,
                            zone_id: n.zone_id,
                            npc_type: n.npc_type,
                            position: n.position,
                            rotation: n.rotation,
                            animation_state: n.animation_state,
                        }
                    })
                    .collect()
            } else {
                // Same zone - only send NPCs client doesn't know about
                world.get_npcs_in_zone(player_zone_id)
                    .iter()
                    .filter(|n| !client.known_npcs.contains(&n.id))
                    .map(|n| {
                        new_npc_ids.push(n.id);
                        NpcState {
                            id: n.id,
                            zone_id: n.zone_id,
                            npc_type: n.npc_type,
                            position: n.position,
                            rotation: n.rotation,
                            animation_state: n.animation_state,
                        }
                    })
                    .collect()
            };
            
            // Log when sending NPCs to a new zone
            if !npcs.is_empty() {
                info!("Sending {} NPCs to player {} in zone {}", npcs.len(), client.player_id, player_zone_id);
            }
            
            let msg = ServerMessage::WorldState {
                tick,
                players,
                enemies,
                npcs,
            };
            
            client_updates.push((*addr, msg, new_npc_ids));
        }
        
        // Now send messages and update client state
        for (addr, msg, new_npc_ids) in client_updates {
            let data = msg.serialize();
            
            if let Err(e) = self.socket.send_to(&data, &addr).await {
                error!("Failed to send world state to {}: {}", addr, e);
            }
            
            // Update client's known NPCs and zone
            if let Some(client) = self.clients.get_mut(&addr) {
                // Update last zone
                if let Some(player) = world.get_player(client.player_id) {
                    if client.last_zone_id != Some(player.zone_id) {
                        // Zone changed - clear old NPCs
                        client.clear_known_npcs();
                        client.last_zone_id = Some(player.zone_id);
                    }
                }
                
                // Add new NPCs to known set
                for npc_id in new_npc_ids {
                    client.known_npcs.insert(npc_id);
                }
            }
        }
    }
    
    /// Process outgoing message queues
    pub async fn process_outgoing(&mut self, _world: &GameWorld) {
        // Send broadcast messages
        for msg in self.broadcast_queue.drain(..) {
            let data = msg.serialize();
            for (addr, _) in &self.clients {
                if let Err(e) = self.socket.send_to(&data, addr).await {
                    error!("Failed to broadcast to {}: {}", addr, e);
                }
            }
        }
        
        // Send individual client queues
        for (addr, client) in &mut self.clients {
            for msg in client.outgoing_queue.drain(..) {
                let data = msg.serialize();
                if let Err(e) = self.socket.send_to(&data, addr).await {
                    error!("Failed to send to {}: {}", addr, e);
                }
            }
        }
    }
    
    /// Send a message to a specific address
    async fn send_to(&self, addr: SocketAddr, msg: &ServerMessage) {
        let data = msg.serialize();
        if let Err(e) = self.socket.send_to(&data, addr).await {
            error!("Failed to send to {}: {}", addr, e);
        }
    }
    
    /// Queue a message to broadcast to all except one address (only to in-game clients)
    fn broadcast_to_ingame_except(&mut self, except: SocketAddr, msg: ServerMessage) {
        for (addr, client) in &mut self.clients {
            if *addr != except && client.is_in_game() {
                client.outgoing_queue.push(msg.clone());
            }
        }
    }
    
    /// Queue a message to broadcast to all in-game clients in a specific zone, except one
    fn broadcast_to_zone_except(&mut self, except: SocketAddr, zone_id: u32, msg: ServerMessage, world: &GameWorld) {
        for (addr, client) in &mut self.clients {
            if *addr != except && client.is_in_game() {
                // Check if this client is in the same zone
                if let Some(player) = world.get_player(client.player_id) {
                    if player.zone_id == zone_id {
                        client.outgoing_queue.push(msg.clone());
                    }
                }
            }
        }
    }
    
    /// Queue a message to broadcast to all in-game clients in a specific zone
    fn broadcast_to_zone(&mut self, zone_id: u32, msg: ServerMessage, world: &GameWorld) {
        for client in self.clients.values_mut() {
            if client.is_in_game() {
                if let Some(player) = world.get_player(client.player_id) {
                    if player.zone_id == zone_id {
                        client.outgoing_queue.push(msg.clone());
                    }
                }
            }
        }
    }
    
    /// Queue a message to broadcast to all in-game clients
    fn broadcast_to_ingame(&mut self, msg: ServerMessage) {
        for client in self.clients.values_mut() {
            if client.is_in_game() {
                client.outgoing_queue.push(msg.clone());
            }
        }
    }
    
    /// Queue messages to broadcast to all clients (in game only)
    pub fn queue_broadcasts(&mut self, messages: Vec<ServerMessage>) {
        for msg in messages {
            self.broadcast_to_ingame(msg);
        }
    }
    
    /// Queue messages for a specific player
    pub fn queue_messages_for_player(&mut self, player_id: u64, messages: Vec<ServerMessage>) {
        // Find client by player_id
        for client in self.clients.values_mut() {
            if client.player_id == player_id && client.is_in_game() {
                client.outgoing_queue.extend(messages);
                return;
            }
        }
    }
    
    /// Queue player-specific messages from ability updates
    pub fn queue_player_ability_updates(&mut self, updates: Vec<(u64, Vec<ServerMessage>)>) {
        for (player_id, messages) in updates {
            self.queue_messages_for_player(player_id, messages);
        }
    }
    
    /// Save all connected players that are in game (called periodically)
    pub fn save_all_players(&self, world: &GameWorld, persistence: &PersistenceHandle) {
        for client in self.clients.values() {
            if let ConnectionState::InGame { character_id, .. } = &client.state {
                if let Some(player) = world.get_player(client.player_id) {
                    let state = player_to_state_data(player);
                    let inventory = player_inventory_to_data(player);
                    persistence.save_character(*character_id, state, inventory);
                }
            }
        }
    }
}

// =============================================================================
// Helper functions for data conversion
// =============================================================================

use crate::entities::ServerPlayer;

fn player_to_state_data(player: &ServerPlayer) -> PlayerStateData {
    PlayerStateData {
        zone_id: player.zone_id as i32,
        position_x: player.position[0],
        position_y: player.position[1],
        position_z: player.position[2],
        rotation: player.rotation,
        health: player.health as i32,
        max_health: player.max_health as i32,
        mana: player.mana as i32,
        max_mana: player.max_mana as i32,
        level: player.level as i32,
        experience: player.experience as i32,
        attack: player.attack_power as i32,
        defense: player.defense as i32,
        gold: player.gold as i64,
    }
}

fn player_inventory_to_data(player: &ServerPlayer) -> Vec<InventorySlotData> {
    player.inventory
        .iter()
        .enumerate()
        .filter_map(|(slot, opt)| {
            opt.as_ref().map(|inv| InventorySlotData {
                slot: slot as i16,
                item_id: inv.item_id as i32,
                quantity: inv.quantity as i32,
            })
        })
        .collect()
}

fn inventory_data_to_slots(data: &[InventorySlotData]) -> Vec<Option<InventorySlot>> {
    let mut slots: Vec<Option<InventorySlot>> = vec![None; 20];
    for item in data {
        if (item.slot as usize) < slots.len() {
            slots[item.slot as usize] = Some(InventorySlot {
                item_id: item.item_id as u32,
                quantity: item.quantity as u32,
            });
        }
    }
    slots
}
