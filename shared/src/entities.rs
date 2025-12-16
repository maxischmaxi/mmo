//! Shared entity definitions.

use serde::{Deserialize, Serialize};

/// Stats shared between client and server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityStats {
    pub health: u32,
    pub max_health: u32,
    pub mana: u32,
    pub max_mana: u32,
    pub attack_power: u32,
    pub defense: u32,
    pub speed: f32,
}

impl Default for EntityStats {
    fn default() -> Self {
        Self {
            health: 100,
            max_health: 100,
            mana: 50,
            max_mana: 50,
            attack_power: 10,
            defense: 5,
            speed: 5.0,
        }
    }
}

/// Player data that persists
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerData {
    pub id: u64,
    pub username: String,
    pub stats: EntityStats,
    pub level: u32,
    pub experience: u64,
}

impl PlayerData {
    pub fn new(id: u64, username: String) -> Self {
        Self {
            id,
            username,
            stats: EntityStats::default(),
            level: 1,
            experience: 0,
        }
    }
}

/// Enemy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnemyConfig {
    pub name: String,
    pub stats: EntityStats,
    pub aggro_range: f32,
    pub attack_range: f32,
    pub attack_cooldown: f32,
    pub experience_reward: u64,
    pub loot_table: Vec<LootEntry>,
}

/// Loot table entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LootEntry {
    pub item_id: u32,
    pub drop_chance: f32, // 0.0 - 1.0
    pub min_quantity: u32,
    pub max_quantity: u32,
}
