//! Network protocol definitions shared between client and server.

use serde::{Deserialize, Serialize};

/// Protocol version for compatibility checking
pub const PROTOCOL_VERSION: u32 = 2;

/// Server tick rate in Hz
pub const SERVER_TICK_RATE: u32 = 20;

/// Default server port
pub const DEFAULT_PORT: u16 = 7777;

/// Maximum characters per account
pub const MAX_CHARACTERS_PER_ACCOUNT: usize = 4;

// =============================================================================
// Character System Types
// =============================================================================

/// Character class
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum CharacterClass {
    Ninja = 0,
    Warrior = 1,
    Sura = 2,
    Shaman = 3,
}

impl CharacterClass {
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::Ninja),
            1 => Some(Self::Warrior),
            2 => Some(Self::Sura),
            3 => Some(Self::Shaman),
            _ => None,
        }
    }
    
    pub fn as_u8(&self) -> u8 {
        *self as u8
    }
    
    pub fn name(&self) -> &'static str {
        match self {
            Self::Ninja => "Ninja",
            Self::Warrior => "Warrior",
            Self::Sura => "Sura",
            Self::Shaman => "Shaman",
        }
    }
    
    /// Get base attack speed for this class (attacks per second multiplier)
    /// 1.0 = normal speed (1.53s base animation), 1.5 = 50% faster, etc.
    pub fn base_attack_speed(&self) -> f32 {
        match self {
            Self::Ninja => 1.2,    // Ninjas attack slightly faster
            Self::Warrior => 1.0,  // Warriors have normal attack speed
            Self::Sura => 1.1,     // Suras attack slightly faster
            Self::Shaman => 0.9,   // Shamans attack slightly slower (magic focused)
        }
    }
}

/// Character gender
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum Gender {
    Male = 0,
    Female = 1,
}

impl Gender {
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::Male),
            1 => Some(Self::Female),
            _ => None,
        }
    }
    
    pub fn as_u8(&self) -> u8 {
        *self as u8
    }
}

/// Empire (faction)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum Empire {
    Red = 0,    // Shinsoo
    Yellow = 1, // Chunjo
    Blue = 2,   // Jinno
}

impl Empire {
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::Red),
            1 => Some(Self::Yellow),
            2 => Some(Self::Blue),
            _ => None,
        }
    }
    
    pub fn as_u8(&self) -> u8 {
        *self as u8
    }
    
    pub fn name(&self) -> &'static str {
        match self {
            Self::Red => "Shinsoo",
            Self::Yellow => "Chunjo",
            Self::Blue => "Jinno",
        }
    }
    
    /// Get spawn position for this empire
    pub fn spawn_position(&self) -> [f32; 3] {
        match self {
            Self::Red => [0.0, 1.0, 0.0],
            Self::Yellow => [100.0, 1.0, 0.0],
            Self::Blue => [-100.0, 1.0, 0.0],
        }
    }
}

/// Character info for character list (summary)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CharacterInfo {
    pub id: u64,
    pub name: String,
    pub class: CharacterClass,
    pub gender: Gender,
    pub empire: Empire,
    pub level: u32,
}

// =============================================================================
// Client -> Server Messages
// =============================================================================

/// Messages sent from client to server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClientMessage {
    /// Register a new account
    Register {
        username: String,
        password: String,
    },
    
    /// Login with existing account
    Login {
        protocol_version: u32,
        username: String,
        password: String,
    },
    
    /// Request character list (after login)
    GetCharacterList,
    
    /// Create a new character
    CreateCharacter {
        name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
    },
    
    /// Select a character to play
    SelectCharacter {
        character_id: u64,
    },
    
    /// Delete a character (requires confirmation)
    DeleteCharacter {
        character_id: u64,
        confirm_name: String,
    },
    
    /// Disconnect gracefully
    Disconnect,
    
    /// Player input/position update (sent frequently)
    PlayerUpdate {
        position: [f32; 3],
        rotation: f32,
        velocity: [f32; 3],
        animation_state: AnimationState,
    },
    
    /// Chat message
    ChatMessage {
        content: String,
    },
    
    /// Attack request
    Attack {
        target_id: u64,
    },
    
    /// Pick up item request
    PickupItem {
        item_entity_id: u64,
    },
    
    /// Use item from inventory
    UseItem {
        slot: u8,
    },
    
    /// Drop item from inventory
    DropItem {
        slot: u8,
    },
    
    /// Request respawn after death
    /// respawn_type: 0 = at empire spawn (full health), 1 = at death location (20% health)
    RespawnRequest {
        respawn_type: u8,
    },
    
    /// Equip an item from inventory
    EquipItem {
        inventory_slot: u8,
    },
    
    /// Unequip an item from an equipment slot
    UnequipItem {
        /// Equipment slot name: "weapon" (future: "head", "chest", etc.)
        equipment_slot: String,
    },
    
    /// Dev command: Add item to inventory (debug only)
    DevAddItem {
        item_id: u32,
        quantity: u32,
    },
}

// =============================================================================
// Server -> Client Messages
// =============================================================================

/// Messages sent from server to client
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ServerMessage {
    /// Registration successful
    RegisterSuccess {
        player_id: u64,
    },
    
    /// Registration failed
    RegisterFailed {
        reason: String,
    },
    
    /// Login successful - now request character list
    LoginSuccess {
        player_id: u64,
    },
    
    /// Login failed
    LoginFailed {
        reason: String,
    },
    
    /// Character list response
    CharacterList {
        characters: Vec<CharacterInfo>,
    },
    
    /// Character created successfully
    CharacterCreated {
        character: CharacterInfo,
    },
    
    /// Character creation failed
    CharacterCreateFailed {
        reason: String,
    },
    
    /// Character selected - enter game with full state
    CharacterSelected {
        character_id: u64,
        name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
        position: [f32; 3],
        rotation: f32,
        health: u32,
        max_health: u32,
        mana: u32,
        max_mana: u32,
        level: u32,
        experience: u32,
        attack: u32,
        defense: u32,
        attack_speed: f32,
        inventory: Vec<Option<InventorySlot>>,
        /// Currently equipped weapon item ID (None = unarmed)
        equipped_weapon_id: Option<u32>,
    },
    
    /// Character selection failed
    CharacterSelectFailed {
        reason: String,
    },
    
    /// Character deleted successfully
    CharacterDeleted {
        character_id: u64,
    },
    
    /// Character deletion failed
    CharacterDeleteFailed {
        reason: String,
    },
    
    /// Another player joined
    PlayerSpawn {
        id: u64,
        name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
        position: [f32; 3],
        rotation: f32,
    },
    
    /// Another player left
    PlayerDespawn {
        id: u64,
    },
    
    /// World state update (sent every server tick)
    WorldState {
        tick: u64,
        players: Vec<PlayerState>,
        enemies: Vec<EnemyState>,
    },
    
    /// Chat message broadcast
    ChatBroadcast {
        sender_id: u64,
        sender_name: String,
        content: String,
    },
    
    /// Damage was dealt
    DamageEvent {
        attacker_id: u64,
        target_id: u64,
        damage: u32,
        target_new_health: u32,
        is_critical: bool,
    },
    
    /// Entity died
    EntityDeath {
        entity_id: u64,
        killer_id: Option<u64>,
    },
    
    /// Entity respawned (for other entities)
    EntityRespawn {
        entity_id: u64,
        position: [f32; 3],
        health: u32,
    },
    
    /// Player respawn response (for local player)
    PlayerRespawned {
        position: [f32; 3],
        health: u32,
        max_health: u32,
    },
    
    /// Item spawned in world
    ItemSpawn {
        entity_id: u64,
        item_id: u32,
        position: [f32; 3],
    },
    
    /// Item was picked up (removed from world)
    ItemDespawn {
        entity_id: u64,
    },
    
    /// Inventory update for the client
    InventoryUpdate {
        slots: Vec<Option<InventorySlot>>,
    },
    
    /// Enemy spawned
    EnemySpawn {
        id: u64,
        enemy_type: EnemyType,
        position: [f32; 3],
        health: u32,
        max_health: u32,
        level: u8,
    },
    
    /// Enemy despawned
    EnemyDespawn {
        id: u64,
    },
    
    /// Equipment update (weapon equipped/unequipped)
    EquipmentUpdate {
        /// Currently equipped weapon item ID (None = unarmed)
        equipped_weapon_id: Option<u32>,
    },
    
    /// Time synchronization for day/night cycle
    /// Sent on character select and every 60 seconds
    TimeSync {
        /// Unix timestamp in seconds (server's current UTC time)
        unix_timestamp: i64,
        /// Server latitude for solar calculations (e.g., 52.5 for Berlin)
        latitude: f32,
        /// Server longitude for solar calculations (e.g., 13.4 for Berlin)
        longitude: f32,
    },
}

// =============================================================================
// State Types
// =============================================================================

/// Player state for world updates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerState {
    pub id: u64,
    pub position: [f32; 3],
    pub rotation: f32,
    pub velocity: [f32; 3],
    pub health: u32,
    pub max_health: u32,
    pub animation_state: AnimationState,
}

/// Enemy state for world updates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnemyState {
    pub id: u64,
    pub enemy_type: EnemyType,
    pub position: [f32; 3],
    pub rotation: f32,
    pub health: u32,
    pub max_health: u32,
    pub level: u8,
    pub animation_state: AnimationState,
    pub target_id: Option<u64>,
}

/// Animation state enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum AnimationState {
    #[default]
    Idle,
    Walking,
    Running,
    Jumping,
    Attacking,
    TakingDamage,
    Dying,
    Dead,
}

/// Enemy type enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EnemyType {
    Goblin,
    Skeleton,
    Wolf,
}

/// Inventory slot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InventorySlot {
    pub item_id: u32,
    pub quantity: u32,
}

// =============================================================================
// Network Channels
// =============================================================================

/// Channel IDs for different message types
pub mod channels {
    /// Reliable ordered - chat, inventory, important events
    pub const RELIABLE_ORDERED: u8 = 0;
    
    /// Reliable unordered - player spawn/despawn
    pub const RELIABLE_UNORDERED: u8 = 1;
    
    /// Unreliable - position updates, frequent state
    pub const UNRELIABLE: u8 = 2;
}

// =============================================================================
// Serialization helpers
// =============================================================================

impl ClientMessage {
    pub fn serialize(&self) -> Vec<u8> {
        bincode::serialize(self).expect("Failed to serialize ClientMessage")
    }
    
    pub fn deserialize(data: &[u8]) -> Result<Self, bincode::Error> {
        bincode::deserialize(data)
    }
}

impl ServerMessage {
    pub fn serialize(&self) -> Vec<u8> {
        bincode::serialize(self).expect("Failed to serialize ServerMessage")
    }
    
    pub fn deserialize(data: &[u8]) -> Result<Self, bincode::Error> {
        bincode::deserialize(data)
    }
}
