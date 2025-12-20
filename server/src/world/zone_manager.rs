//! Zone management system.
//!
//! Zone ID structure:
//!   1-99:    Shinsoo (empire 0)
//!   100-199: Chunjo (empire 1)
//!   200-299: Jinno (empire 2)
//!   300+:    Neutral/Dungeons (future)

use std::collections::HashMap;
use log::{info, warn};
use mmo_shared::{Empire, EnemyType, NpcType};

/// Zone definition loaded from database
#[derive(Debug, Clone)]
pub struct ZoneDefinition {
    pub id: u32,
    pub name: String,
    pub empire: Option<Empire>,
    pub scene_path: String,
    pub is_default_spawn: bool,
}

/// Spawn point within a zone
#[derive(Debug, Clone)]
pub struct ZoneSpawnPoint {
    pub id: i32,
    pub zone_id: u32,
    pub name: String,
    pub position: [f32; 3],
    pub is_default: bool,
}

/// Enemy spawn definition within a zone
#[derive(Debug, Clone)]
pub struct ZoneEnemySpawn {
    pub id: i32,
    pub zone_id: u32,
    pub enemy_type: EnemyType,
    pub position: [f32; 3],
    pub respawn_time_secs: u32,
}

/// NPC spawn definition within a zone
#[derive(Debug, Clone)]
pub struct ZoneNpcSpawn {
    pub id: i32,
    pub zone_id: u32,
    pub npc_type: NpcType,
    pub position: [f32; 3],
    pub rotation: f32,
}

/// Manages zone definitions and provides zone-related queries
#[derive(Debug)]
pub struct ZoneManager {
    /// All zone definitions, keyed by zone ID
    zones: HashMap<u32, ZoneDefinition>,
    /// Spawn points per zone
    spawn_points: HashMap<u32, Vec<ZoneSpawnPoint>>,
    /// Enemy spawns per zone
    enemy_spawns: HashMap<u32, Vec<ZoneEnemySpawn>>,
    /// NPC spawns per zone
    npc_spawns: HashMap<u32, Vec<ZoneNpcSpawn>>,
    /// Default zone for each empire
    default_zones: HashMap<Empire, u32>,
}

impl ZoneManager {
    /// Create a new zone manager with empty data
    pub fn new() -> Self {
        Self {
            zones: HashMap::new(),
            spawn_points: HashMap::new(),
            enemy_spawns: HashMap::new(),
            npc_spawns: HashMap::new(),
            default_zones: HashMap::new(),
        }
    }
    
    /// Create a zone manager with hardcoded default data
    /// Used when database is not available
    pub fn with_defaults() -> Self {
        let mut manager = Self::new();
        
        // Add default zones
        manager.zones.insert(1, ZoneDefinition {
            id: 1,
            name: "Shinsoo Village".to_string(),
            empire: Some(Empire::Red),
            scene_path: "res://scenes/world/shinsoo/village.tscn".to_string(),
            is_default_spawn: true,
        });
        manager.zones.insert(100, ZoneDefinition {
            id: 100,
            name: "Chunjo Village".to_string(),
            empire: Some(Empire::Yellow),
            scene_path: "res://scenes/world/chunjo/village.tscn".to_string(),
            is_default_spawn: true,
        });
        manager.zones.insert(200, ZoneDefinition {
            id: 200,
            name: "Jinno Village".to_string(),
            empire: Some(Empire::Blue),
            scene_path: "res://scenes/world/jinno/village.tscn".to_string(),
            is_default_spawn: true,
        });
        
        // Set default zones
        manager.default_zones.insert(Empire::Red, 1);
        manager.default_zones.insert(Empire::Yellow, 100);
        manager.default_zones.insert(Empire::Blue, 200);
        
        // Add default spawn points
        manager.spawn_points.insert(1, vec![ZoneSpawnPoint {
            id: 1,
            zone_id: 1,
            name: "default".to_string(),
            position: [0.0, 1.0, 0.0],
            is_default: true,
        }]);
        manager.spawn_points.insert(100, vec![ZoneSpawnPoint {
            id: 2,
            zone_id: 100,
            name: "default".to_string(),
            position: [0.0, 1.0, 0.0],
            is_default: true,
        }]);
        manager.spawn_points.insert(200, vec![ZoneSpawnPoint {
            id: 3,
            zone_id: 200,
            name: "default".to_string(),
            position: [0.0, 1.0, 0.0],
            is_default: true,
        }]);
        
        // Add default enemy spawns (positioned away from spawn point and NPC at 5,0,5)
        manager.enemy_spawns.insert(1, vec![
            ZoneEnemySpawn { id: 1, zone_id: 1, enemy_type: EnemyType::Goblin, position: [25.0, 0.0, 25.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 2, zone_id: 1, enemy_type: EnemyType::Goblin, position: [-25.0, 0.0, 15.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 3, zone_id: 1, enemy_type: EnemyType::Goblin, position: [30.0, 0.0, -20.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 4, zone_id: 1, enemy_type: EnemyType::Mutant, position: [0.0, 0.0, 35.0], respawn_time_secs: 90 },
            ZoneEnemySpawn { id: 5, zone_id: 1, enemy_type: EnemyType::Skeleton, position: [-30.0, 0.0, -30.0], respawn_time_secs: 120 },
            ZoneEnemySpawn { id: 14, zone_id: 1, enemy_type: EnemyType::Wolf, position: [20.0, 0.0, -15.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 15, zone_id: 1, enemy_type: EnemyType::Wolf, position: [25.0, 0.0, -20.0], respawn_time_secs: 60 },
        ]);
        manager.enemy_spawns.insert(100, vec![
            ZoneEnemySpawn { id: 6, zone_id: 100, enemy_type: EnemyType::Goblin, position: [25.0, 0.0, 25.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 7, zone_id: 100, enemy_type: EnemyType::Goblin, position: [-25.0, 0.0, 20.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 8, zone_id: 100, enemy_type: EnemyType::Skeleton, position: [35.0, 0.0, 15.0], respawn_time_secs: 120 },
            ZoneEnemySpawn { id: 9, zone_id: 100, enemy_type: EnemyType::Mutant, position: [-20.0, 0.0, 30.0], respawn_time_secs: 90 },
            ZoneEnemySpawn { id: 16, zone_id: 100, enemy_type: EnemyType::Wolf, position: [30.0, 0.0, -20.0], respawn_time_secs: 60 },
        ]);
        manager.enemy_spawns.insert(200, vec![
            ZoneEnemySpawn { id: 10, zone_id: 200, enemy_type: EnemyType::Mutant, position: [20.0, 0.0, 30.0], respawn_time_secs: 90 },
            ZoneEnemySpawn { id: 11, zone_id: 200, enemy_type: EnemyType::Mutant, position: [-25.0, 0.0, 25.0], respawn_time_secs: 90 },
            ZoneEnemySpawn { id: 12, zone_id: 200, enemy_type: EnemyType::Goblin, position: [35.0, 0.0, -15.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 13, zone_id: 200, enemy_type: EnemyType::Skeleton, position: [-35.0, 0.0, 10.0], respawn_time_secs: 120 },
            ZoneEnemySpawn { id: 17, zone_id: 200, enemy_type: EnemyType::Wolf, position: [-25.0, 0.0, -20.0], respawn_time_secs: 60 },
        ]);
        
        // Add default NPC spawns - one Old Man per empire zone
        // Positioned near the spawn point but offset so they're visible
        manager.npc_spawns.insert(1, vec![
            ZoneNpcSpawn { id: 1, zone_id: 1, npc_type: NpcType::OldMan, position: [5.0, 0.0, 5.0], rotation: 0.0 },
        ]);
        manager.npc_spawns.insert(100, vec![
            ZoneNpcSpawn { id: 2, zone_id: 100, npc_type: NpcType::OldMan, position: [5.0, 0.0, 5.0], rotation: 0.0 },
        ]);
        manager.npc_spawns.insert(200, vec![
            ZoneNpcSpawn { id: 3, zone_id: 200, npc_type: NpcType::OldMan, position: [5.0, 0.0, 5.0], rotation: 0.0 },
        ]);
        
        info!("ZoneManager initialized with {} zones (hardcoded defaults)", manager.zones.len());
        
        manager
    }
    
    /// Load zone data from database rows
    pub fn load_zones(&mut self, zones: Vec<(i32, String, Option<i16>, String, bool)>) {
        self.zones.clear();
        self.default_zones.clear();
        
        for (id, name, empire, scene_path, is_default_spawn) in zones {
            let empire = empire.and_then(|e| Empire::from_u8(e as u8));
            let zone_id = id as u32;
            
            let zone = ZoneDefinition {
                id: zone_id,
                name,
                empire,
                scene_path,
                is_default_spawn,
            };
            
            if is_default_spawn {
                if let Some(emp) = empire {
                    self.default_zones.insert(emp, zone_id);
                }
            }
            
            self.zones.insert(zone_id, zone);
        }
        
        info!("Loaded {} zones from database", self.zones.len());
    }
    
    /// Load spawn points from database rows
    pub fn load_spawn_points(&mut self, spawn_points: Vec<(i32, i32, String, f32, f32, f32, bool)>) {
        self.spawn_points.clear();
        
        for (id, zone_id, name, x, y, z, is_default) in spawn_points {
            let zone_id = zone_id as u32;
            let spawn_point = ZoneSpawnPoint {
                id,
                zone_id,
                name,
                position: [x, y, z],
                is_default,
            };
            
            self.spawn_points
                .entry(zone_id)
                .or_insert_with(Vec::new)
                .push(spawn_point);
        }
        
        info!("Loaded spawn points for {} zones", self.spawn_points.len());
    }
    
    /// Load enemy spawns from database rows
    pub fn load_enemy_spawns(&mut self, enemy_spawns: Vec<(i32, i32, i16, f32, f32, f32, i32)>) {
        self.enemy_spawns.clear();
        
        for (id, zone_id, enemy_type, x, y, z, respawn_time) in enemy_spawns {
            let zone_id = zone_id as u32;
            let enemy_type = match enemy_type {
                0 => EnemyType::Goblin,
                1 => EnemyType::Skeleton,
                2 => EnemyType::Mutant,
                3 => EnemyType::Wolf,
                _ => {
                    warn!("Unknown enemy type {} in spawn {}, defaulting to Goblin", enemy_type, id);
                    EnemyType::Goblin
                }
            };
            
            let spawn = ZoneEnemySpawn {
                id,
                zone_id,
                enemy_type,
                position: [x, y, z],
                respawn_time_secs: respawn_time as u32,
            };
            
            self.enemy_spawns
                .entry(zone_id)
                .or_insert_with(Vec::new)
                .push(spawn);
        }
        
        let total_spawns: usize = self.enemy_spawns.values().map(|v| v.len()).sum();
        info!("Loaded {} enemy spawns across {} zones", total_spawns, self.enemy_spawns.len());
    }
    
    /// Load NPC spawns from database rows
    pub fn load_npc_spawns(&mut self, npc_spawns: Vec<(i32, i32, i16, f32, f32, f32, f32)>) {
        self.npc_spawns.clear();
        
        for (id, zone_id, npc_type, x, y, z, rotation) in npc_spawns {
            let zone_id = zone_id as u32;
            let npc_type = match npc_type {
                0 => NpcType::OldMan,
                _ => {
                    warn!("Unknown NPC type {} in spawn {}, defaulting to OldMan", npc_type, id);
                    NpcType::OldMan
                }
            };
            
            let spawn = ZoneNpcSpawn {
                id,
                zone_id,
                npc_type,
                position: [x, y, z],
                rotation,
            };
            
            self.npc_spawns
                .entry(zone_id)
                .or_insert_with(Vec::new)
                .push(spawn);
        }
        
        let total_spawns: usize = self.npc_spawns.values().map(|v| v.len()).sum();
        info!("Loaded {} NPC spawns across {} zones", total_spawns, self.npc_spawns.len());
    }
    
    /// Get a zone definition by ID
    pub fn get_zone(&self, zone_id: u32) -> Option<&ZoneDefinition> {
        self.zones.get(&zone_id)
    }
    
    /// Get all zone IDs
    pub fn get_zone_ids(&self) -> Vec<u32> {
        self.zones.keys().copied().collect()
    }
    
    /// Get the default zone ID for an empire
    pub fn get_default_zone_for_empire(&self, empire: Empire) -> u32 {
        self.default_zones.get(&empire).copied().unwrap_or_else(|| {
            // Fallback based on empire
            match empire {
                Empire::Red => 1,
                Empire::Yellow => 100,
                Empire::Blue => 200,
            }
        })
    }
    
    /// Get the default spawn position for a zone
    pub fn get_default_spawn_point(&self, zone_id: u32) -> [f32; 3] {
        if let Some(spawns) = self.spawn_points.get(&zone_id) {
            if let Some(default) = spawns.iter().find(|s| s.is_default) {
                return default.position;
            }
            if let Some(first) = spawns.first() {
                return first.position;
            }
        }
        
        // Default fallback
        [0.0, 1.0, 0.0]
    }
    
    /// Get all spawn points for a zone
    pub fn get_spawn_points(&self, zone_id: u32) -> &[ZoneSpawnPoint] {
        self.spawn_points.get(&zone_id).map(|v| v.as_slice()).unwrap_or(&[])
    }
    
    /// Get enemy spawns for a zone
    pub fn get_enemy_spawns(&self, zone_id: u32) -> &[ZoneEnemySpawn] {
        self.enemy_spawns.get(&zone_id).map(|v| v.as_slice()).unwrap_or(&[])
    }
    
    /// Get NPC spawns for a zone
    pub fn get_npc_spawns(&self, zone_id: u32) -> &[ZoneNpcSpawn] {
        self.npc_spawns.get(&zone_id).map(|v| v.as_slice()).unwrap_or(&[])
    }
    
    /// Check if a zone exists
    pub fn zone_exists(&self, zone_id: u32) -> bool {
        self.zones.contains_key(&zone_id)
    }
}

impl Default for ZoneManager {
    fn default() -> Self {
        Self::new()
    }
}
