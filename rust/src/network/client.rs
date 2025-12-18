//! UDP Network Client for the MMO.
//! 
//! This is a simple non-blocking UDP client that can be polled from the Godot main loop.

use std::net::{UdpSocket, SocketAddr};
use std::io::ErrorKind;
use std::time::{Instant, Duration};

use mmo_shared::{
    ClientMessage, ServerMessage, AnimationState,
    CharacterClass, Gender, Empire,
    PROTOCOL_VERSION, DEFAULT_PORT,
};

/// Maximum packet size
const MAX_PACKET_SIZE: usize = 1200;

/// Connection timeout duration
const CONNECTION_TIMEOUT: Duration = Duration::from_secs(10);

/// Heartbeat interval (send position update to keep connection alive)
const HEARTBEAT_INTERVAL: Duration = Duration::from_millis(50); // 20 Hz

/// Connection state
#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Failed(String),
}

/// Network client for communicating with the game server
pub struct NetworkClient {
    socket: Option<UdpSocket>,
    server_addr: Option<SocketAddr>,
    state: ConnectionState,
    player_id: Option<u64>,
    connect_time: Option<Instant>,
    last_send_time: Instant,
    
    /// Received messages waiting to be processed
    incoming_messages: Vec<ServerMessage>,
}

impl NetworkClient {
    /// Create a new network client
    pub fn new() -> Self {
        Self {
            socket: None,
            server_addr: None,
            state: ConnectionState::Disconnected,
            player_id: None,
            connect_time: None,
            last_send_time: Instant::now(),
            incoming_messages: Vec::new(),
        }
    }
    
    /// Initialize socket for auth operations (before login)
    pub fn init_socket(&mut self, server_ip: &str) -> Result<(), String> {
        // Create socket bound to any available port
        let socket = UdpSocket::bind("0.0.0.0:0")
            .map_err(|e| format!("Failed to create socket: {}", e))?;
        
        // Set non-blocking mode
        socket.set_nonblocking(true)
            .map_err(|e| format!("Failed to set non-blocking: {}", e))?;
        
        // Parse server address
        let server_addr: SocketAddr = format!("{}:{}", server_ip, DEFAULT_PORT)
            .parse()
            .map_err(|e| format!("Invalid server address: {}", e))?;
        
        self.socket = Some(socket);
        self.server_addr = Some(server_addr);
        
        Ok(())
    }
    
    /// Register a new account
    pub fn register(&mut self, server_ip: &str, username: &str, password: &str) -> Result<(), String> {
        // Initialize socket if not already
        if self.socket.is_none() {
            self.init_socket(server_ip)?;
        }
        
        let msg = ClientMessage::Register {
            username: username.to_string(),
            password: password.to_string(),
        };
        self.send_message(&msg)?;
        
        Ok(())
    }
    
    /// Login with existing account
    pub fn login(&mut self, server_ip: &str, username: &str, password: &str) -> Result<(), String> {
        // Initialize socket if not already
        if self.socket.is_none() {
            self.init_socket(server_ip)?;
        }
        
        self.state = ConnectionState::Connecting;
        self.connect_time = Some(Instant::now());
        
        let msg = ClientMessage::Login {
            protocol_version: PROTOCOL_VERSION,
            username: username.to_string(),
            password: password.to_string(),
        };
        self.send_message(&msg)?;
        
        Ok(())
    }
    
    /// Disconnect from the server
    pub fn disconnect(&mut self) {
        if self.is_connected() {
            let _ = self.send_message(&ClientMessage::Disconnect);
        }
        
        self.socket = None;
        self.server_addr = None;
        self.state = ConnectionState::Disconnected;
        self.player_id = None;
        self.connect_time = None;
        self.incoming_messages.clear();
    }
    
    /// Check if connected
    pub fn is_connected(&self) -> bool {
        matches!(self.state, ConnectionState::Connected)
    }
    
    /// Get connection state
    pub fn get_state(&self) -> &ConnectionState {
        &self.state
    }
    
    /// Get player ID (only valid when connected)
    pub fn get_player_id(&self) -> Option<u64> {
        self.player_id
    }
    
    /// Poll for incoming messages (should be called every frame)
    pub fn poll(&mut self) -> Vec<ServerMessage> {
        self.receive_packets();
        
        // Check for connection timeout
        if matches!(self.state, ConnectionState::Connecting) {
            if let Some(connect_time) = self.connect_time {
                if connect_time.elapsed() > CONNECTION_TIMEOUT {
                    self.state = ConnectionState::Failed("Connection timed out".to_string());
                }
            }
        }
        
        std::mem::take(&mut self.incoming_messages)
    }
    
    /// Receive all pending packets
    fn receive_packets(&mut self) {
        let socket = match &self.socket {
            Some(s) => s,
            None => return,
        };
        
        let mut buf = [0u8; MAX_PACKET_SIZE];
        let mut received_packets: Vec<Vec<u8>> = Vec::new();
        
        // First, collect all packets without borrowing self mutably
        loop {
            match socket.recv_from(&mut buf) {
                Ok((len, _addr)) => {
                    received_packets.push(buf[..len].to_vec());
                }
                Err(ref e) if e.kind() == ErrorKind::WouldBlock => {
                    break;
                }
                Err(e) => {
                    godot::prelude::godot_error!("Network receive error: {}", e);
                    break;
                }
            }
        }
        
        // Now process all received packets
        for packet_data in received_packets {
            self.process_packet(&packet_data);
        }
    }
    
    /// Process a received packet
    fn process_packet(&mut self, data: &[u8]) {
        let message = match ServerMessage::deserialize(data) {
            Ok(msg) => msg,
            Err(e) => {
                godot::prelude::godot_warn!("Failed to deserialize server message: {}", e);
                return;
            }
        };
        
        // Handle connection state messages
        match &message {
            ServerMessage::LoginSuccess { player_id, .. } => {
                self.player_id = Some(*player_id);
                self.state = ConnectionState::Connected;
                godot::prelude::godot_print!("Logged in with player ID: {}", player_id);
            }
            ServerMessage::LoginFailed { reason } => {
                self.state = ConnectionState::Failed(reason.clone());
                godot::prelude::godot_error!("Login failed: {}", reason);
            }
            ServerMessage::RegisterSuccess { player_id } => {
                godot::prelude::godot_print!("Registered successfully with player ID: {}", player_id);
            }
            ServerMessage::RegisterFailed { reason } => {
                godot::prelude::godot_error!("Registration failed: {}", reason);
            }
            _ => {}
        }
        
        self.incoming_messages.push(message);
    }
    
    /// Send a message to the server
    pub fn send_message(&mut self, msg: &ClientMessage) -> Result<(), String> {
        let socket = self.socket.as_ref()
            .ok_or("Not connected")?;
        let server_addr = self.server_addr
            .ok_or("No server address")?;
        
        let data = msg.serialize();
        socket.send_to(&data, server_addr)
            .map_err(|e| format!("Failed to send: {}", e))?;
        
        self.last_send_time = Instant::now();
        
        Ok(())
    }
    
    /// Send player state update to server
    pub fn send_player_update(
        &mut self,
        position: [f32; 3],
        rotation: f32,
        velocity: [f32; 3],
        animation_state: AnimationState,
    ) {
        let msg = ClientMessage::PlayerUpdate {
            position,
            rotation,
            velocity,
            animation_state,
        };
        let _ = self.send_message(&msg);
    }
    
    /// Send a chat message
    pub fn send_chat(&mut self, content: &str) {
        let msg = ClientMessage::ChatMessage {
            content: content.to_string(),
        };
        let _ = self.send_message(&msg);
    }
    
    /// Send an attack request
    pub fn send_attack(&mut self, target_id: u64) {
        let msg = ClientMessage::Attack { target_id };
        let _ = self.send_message(&msg);
    }
    
    /// Send pickup item request
    pub fn send_pickup(&mut self, item_entity_id: u64) {
        let msg = ClientMessage::PickupItem { item_entity_id };
        let _ = self.send_message(&msg);
    }
    
    /// Send use item request
    pub fn send_use_item(&mut self, slot: u8) {
        let msg = ClientMessage::UseItem { slot };
        let _ = self.send_message(&msg);
    }
    
    /// Check if we should send a heartbeat
    pub fn should_send_heartbeat(&self) -> bool {
        self.is_connected() && self.last_send_time.elapsed() > HEARTBEAT_INTERVAL
    }
    
    // =========================================================================
    // Character Selection Methods
    // =========================================================================
    
    /// Request character list from server
    pub fn send_get_character_list(&mut self) {
        let msg = ClientMessage::GetCharacterList;
        let _ = self.send_message(&msg);
    }
    
    /// Create a new character
    pub fn send_create_character(
        &mut self,
        name: &str,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
    ) {
        let msg = ClientMessage::CreateCharacter {
            name: name.to_string(),
            class,
            gender,
            empire,
        };
        let _ = self.send_message(&msg);
    }
    
    /// Select a character to play
    pub fn send_select_character(&mut self, character_id: u64) {
        let msg = ClientMessage::SelectCharacter { character_id };
        let _ = self.send_message(&msg);
    }
    
    /// Delete a character (requires typing the name for confirmation)
    pub fn send_delete_character(&mut self, character_id: u64, confirm_name: &str) {
        let msg = ClientMessage::DeleteCharacter {
            character_id,
            confirm_name: confirm_name.to_string(),
        };
        let _ = self.send_message(&msg);
    }
    
    /// Send respawn request after death
    /// respawn_type: 0 = at empire spawn (full health), 1 = at death location (20% health)
    pub fn send_respawn_request(&mut self, respawn_type: u8) {
        let msg = ClientMessage::RespawnRequest { respawn_type };
        let _ = self.send_message(&msg);
    }
    
    // =========================================================================
    // Equipment Methods
    // =========================================================================
    
    /// Send equip item request
    pub fn send_equip_item(&mut self, inventory_slot: u8) {
        let msg = ClientMessage::EquipItem { inventory_slot };
        let _ = self.send_message(&msg);
    }
    
    /// Send unequip item request
    pub fn send_unequip_item(&mut self, equipment_slot: &str) {
        let msg = ClientMessage::UnequipItem {
            equipment_slot: equipment_slot.to_string(),
        };
        let _ = self.send_message(&msg);
    }
    
    /// Send dev add item command (debug only)
    pub fn send_dev_add_item(&mut self, item_id: u32, quantity: u32) {
        let msg = ClientMessage::DevAddItem { item_id, quantity };
        let _ = self.send_message(&msg);
    }
    
    /// Send teleport request (via Teleport Ring)
    pub fn send_teleport_request(&mut self, zone_id: u32) {
        let msg = ClientMessage::TeleportRequest { zone_id };
        let _ = self.send_message(&msg);
    }
    
    /// Send inventory swap request (drag & drop)
    pub fn send_swap_inventory_slots(&mut self, from_slot: u8, to_slot: u8) {
        let msg = ClientMessage::SwapInventorySlots { from_slot, to_slot };
        let _ = self.send_message(&msg);
    }
    
    /// Send drop item request
    pub fn send_drop_item(&mut self, slot: u8) {
        let msg = ClientMessage::DropItem { slot };
        let _ = self.send_message(&msg);
    }
    
    // =========================================================================
    // Ability Methods
    // =========================================================================
    
    /// Send use ability request
    pub fn send_use_ability(&mut self, ability_id: u32, target_id: Option<u64>) {
        let msg = ClientMessage::UseAbility { ability_id, target_id };
        let _ = self.send_message(&msg);
    }
}

impl Default for NetworkClient {
    fn default() -> Self {
        Self::new()
    }
}
