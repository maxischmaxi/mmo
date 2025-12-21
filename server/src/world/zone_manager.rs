//! Zone management system.
//!
//! Zone ID structure:
//!   1-99:    Shinsoo (empire 0)
//!   100-199: Chunjo (empire 1)
//!   200-299: Jinno (empire 2)
//!   300+:    Neutral/Dungeons (future)

use std::collections::HashMap;
use std::path::Path;
use log::{info, warn, error, debug};
use mmo_shared::{Empire, EnemyType, NpcType};

use crate::navigation::{Obstacle, CircleObstacle, BoxObstacle};
use super::heightmap::Heightmap;

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
    /// Obstacles per zone (for enemy navigation)
    obstacles: HashMap<u32, Vec<Obstacle>>,
    /// Heightmaps per zone (for terrain height queries)
    heightmaps: HashMap<u32, Heightmap>,
}

impl std::fmt::Debug for ZoneManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ZoneManager")
            .field("zones", &self.zones)
            .field("spawn_points", &self.spawn_points)
            .field("enemy_spawns", &self.enemy_spawns)
            .field("npc_spawns", &self.npc_spawns)
            .field("default_zones", &self.default_zones)
            .field("obstacles", &self.obstacles.keys().collect::<Vec<_>>())
            .field("heightmaps", &self.heightmaps.keys().collect::<Vec<_>>())
            .finish()
    }
}

impl ZoneManager {
    /// Create a new zone manager with empty data
    pub fn new() -> Self {
        let mut manager = Self {
            zones: HashMap::new(),
            spawn_points: HashMap::new(),
            enemy_spawns: HashMap::new(),
            npc_spawns: HashMap::new(),
            default_zones: HashMap::new(),
            obstacles: HashMap::new(),
            heightmaps: HashMap::new(),
        };
        
        // Always initialize hardcoded spawn points
        // Y values match terrain village plateau heights from terrain_generator.gd
        manager.init_spawn_points();
        
        manager
    }
    
    /// Initialize spawn points for all zones
    /// First tries to load from spawn_points.json (exported from Godot).
    /// Falls back to hardcoded spawn points if the file doesn't exist.
    fn init_spawn_points(&mut self) {
        // Try to load from JSON file first
        if self.load_spawn_points_from_json("spawn_points.json") {
            return;
        }
        
        info!("No spawn_points.json found, using hardcoded fallback spawn points");
        self.init_hardcoded_spawn_points();
    }
    
    /// Load spawn points from a JSON file exported by Godot
    /// Returns true if successful, false if file not found or parse error
    fn load_spawn_points_from_json<P: AsRef<Path>>(&mut self, path: P) -> bool {
        let path = path.as_ref();
        
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(e) => {
                if e.kind() != std::io::ErrorKind::NotFound {
                    warn!("Failed to read spawn points file {:?}: {}", path, e);
                }
                return false;
            }
        };
        
        let json: serde_json::Value = match serde_json::from_str(&content) {
            Ok(v) => v,
            Err(e) => {
                error!("Failed to parse spawn_points.json: {}", e);
                return false;
            }
        };
        
        let obj = match json.as_object() {
            Some(o) => o,
            None => {
                error!("spawn_points.json root is not an object");
                return false;
            }
        };
        
        let mut spawn_id_counter = 1;
        
        for (zone_id_str, spawn_points_array) in obj {
            let zone_id: u32 = match zone_id_str.parse() {
                Ok(id) => id,
                Err(_) => {
                    warn!("Invalid zone ID in spawn_points.json: {}", zone_id_str);
                    continue;
                }
            };
            
            let spawn_points = match spawn_points_array.as_array() {
                Some(arr) => arr,
                None => {
                    warn!("Zone {} spawn_points is not an array", zone_id);
                    continue;
                }
            };
            
            let mut zone_spawn_points = Vec::new();
            
            for sp in spawn_points {
                if let Some(spawn_point) = self.parse_spawn_point(sp, zone_id, spawn_id_counter) {
                    zone_spawn_points.push(spawn_point);
                    spawn_id_counter += 1;
                }
            }
            
            if !zone_spawn_points.is_empty() {
                self.spawn_points.insert(zone_id, zone_spawn_points);
            }
        }
        
        let total_spawns: usize = self.spawn_points.values().map(|v| v.len()).sum();
        info!("Loaded {} spawn points from {:?} across {} zones", 
            total_spawns, path, self.spawn_points.len());
        
        // Log each zone's spawn points
        for (zone_id, spawns) in &self.spawn_points {
            for sp in spawns {
                let default_str = if sp.is_default { " (default)" } else { "" };
                info!("  Zone {}: {} at ({:.1}, {:.1}, {:.1}){}",
                    zone_id, sp.name, sp.position[0], sp.position[1], sp.position[2], default_str);
            }
        }
        
        true
    }
    
    /// Parse a single spawn point from JSON
    fn parse_spawn_point(&self, value: &serde_json::Value, zone_id: u32, id: i32) -> Option<ZoneSpawnPoint> {
        let obj = value.as_object()?;
        
        let name = obj.get("name")?.as_str()?.to_string();
        let x = obj.get("x")?.as_f64()? as f32;
        let y = obj.get("y")?.as_f64()? as f32;
        let z = obj.get("z")?.as_f64()? as f32;
        let is_default = obj.get("is_default").and_then(|v| v.as_bool()).unwrap_or(false);
        
        Some(ZoneSpawnPoint {
            id,
            zone_id,
            name,
            position: [x, y, z],
            is_default,
        })
    }
    
    /// Fallback: hardcoded spawn points for all zones
    fn init_hardcoded_spawn_points(&mut self) {
        self.spawn_points.insert(1, vec![ZoneSpawnPoint {
            id: 1,
            zone_id: 1,
            name: "default".to_string(),
            position: [0.0, 5.0, 0.0],  // Shinsoo village_height=3.0 + buffer
            is_default: true,
        }]);
        self.spawn_points.insert(100, vec![ZoneSpawnPoint {
            id: 2,
            zone_id: 100,
            name: "default".to_string(),
            position: [0.0, 5.0, 0.0],  // Chunjo village_height=2.0 + buffer
            is_default: true,
        }]);
        self.spawn_points.insert(200, vec![ZoneSpawnPoint {
            id: 3,
            zone_id: 200,
            name: "default".to_string(),
            position: [0.0, 12.0, 0.0],  // Jinno village_height=5.0, scene SpawnPoint at y=12
            is_default: true,
        }]);
        
        info!("Initialized hardcoded spawn points for {} zones", self.spawn_points.len());
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
        
        // Spawn points are already initialized in new() via init_spawn_points()
        
        // Add default enemy spawns (positioned away from spawn point and NPC at 5,0,5)
        manager.enemy_spawns.insert(1, vec![
            ZoneEnemySpawn { id: 1, zone_id: 1, enemy_type: EnemyType::Goblin, position: [25.0, 0.0, 25.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 2, zone_id: 1, enemy_type: EnemyType::Goblin, position: [-25.0, 0.0, 15.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 3, zone_id: 1, enemy_type: EnemyType::Goblin, position: [30.0, 0.0, -20.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 4, zone_id: 1, enemy_type: EnemyType::Mutant, position: [0.0, 0.0, 35.0], respawn_time_secs: 90 },
            ZoneEnemySpawn { id: 5, zone_id: 1, enemy_type: EnemyType::Skeleton, position: [-30.0, 0.0, -30.0], respawn_time_secs: 120 },
            ZoneEnemySpawn { id: 14, zone_id: 1, enemy_type: EnemyType::Wolf, position: [20.0, 0.0, -15.0], respawn_time_secs: 60 },
            ZoneEnemySpawn { id: 15, zone_id: 1, enemy_type: EnemyType::Wolf, position: [25.0, 0.0, -20.0], respawn_time_secs: 60 },
            // TEST: Wolf behind main building - must go around to reach spawn at (0,0)
            ZoneEnemySpawn { id: 20, zone_id: 1, enemy_type: EnemyType::Wolf, position: [18.0, 0.0, -8.0], respawn_time_secs: 30 },
            // TEST: Goblin behind market stall
            ZoneEnemySpawn { id: 21, zone_id: 1, enemy_type: EnemyType::Goblin, position: [-8.0, 0.0, -12.0], respawn_time_secs: 30 },
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
            // TEST: Wolf behind main building (10, -8) - must go around to reach spawn at (0,0)
            // Building is Box (6,-13) to (14,-3), so spawn at (18, -8) to force pathing
            ZoneEnemySpawn { id: 18, zone_id: 200, enemy_type: EnemyType::Wolf, position: [18.0, 0.0, -8.0], respawn_time_secs: 30 },
            // TEST: Goblin behind market stall (-8, -5) - must go around
            // Stall is Box (-10,-8) to (-6,-2), so spawn at (-8, -12)
            ZoneEnemySpawn { id: 19, zone_id: 200, enemy_type: EnemyType::Goblin, position: [-8.0, 0.0, -12.0], respawn_time_secs: 30 },
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
        
        // Add obstacles for each zone
        // Based on shinsoo/village.tscn decorations (4 pillars at corners)
        // Each pillar is a cylinder with radius 1.0
        let village_obstacles = vec![
            // Decorative pillars at corners of the central area
            Obstacle::Circle(CircleObstacle::new(-15.0, -15.0, 1.5)),
            Obstacle::Circle(CircleObstacle::new(15.0, -15.0, 1.5)),
            Obstacle::Circle(CircleObstacle::new(-15.0, 15.0, 1.5)),
            Obstacle::Circle(CircleObstacle::new(15.0, 15.0, 1.5)),
            // Example buildings (boxes) - these match typical village layouts
            // Main building near spawn
            Obstacle::Box(BoxObstacle::from_center(10.0, -8.0, 4.0, 5.0)),
            // Secondary building
            Obstacle::Box(BoxObstacle::from_center(-12.0, 8.0, 3.0, 4.0)),
            // Market stall area
            Obstacle::Box(BoxObstacle::from_center(-8.0, -5.0, 2.0, 3.0)),
        ];
        
        manager.obstacles.insert(1, village_obstacles.clone());
        manager.obstacles.insert(100, village_obstacles.clone());
        manager.obstacles.insert(200, village_obstacles);
        
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
    
    // Spawn points are hardcoded in with_defaults() to match terrain heights
    // from godot/scripts/tools/terrain_generator.gd
    
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
    
    /// Get obstacles for a zone (for enemy pathfinding)
    pub fn get_obstacles(&self, zone_id: u32) -> &[Obstacle] {
        self.obstacles.get(&zone_id).map(|v| v.as_slice()).unwrap_or(&[])
    }
    
    /// Get terrain height at a world position in a zone
    /// Returns the Y coordinate for the terrain surface at (x, z)
    /// Falls back to 0.0 if no heightmap is loaded for the zone
    pub fn get_terrain_height(&self, zone_id: u32, x: f32, z: f32) -> f32 {
        if let Some(heightmap) = self.heightmaps.get(&zone_id) {
            heightmap.get_height(x, z)
        } else {
            // Fallback: use hardcoded village heights from terrain_generator.gd
            match zone_id {
                1 => 3.0,      // Shinsoo village_height
                100 => 2.0,   // Chunjo village_height
                200 => 5.0,   // Jinno village_height
                _ => 0.0,
            }
        }
    }
    
    /// Check if a heightmap is loaded for a zone
    pub fn has_heightmap(&self, zone_id: u32) -> bool {
        self.heightmaps.contains_key(&zone_id)
    }
    
    /// Initialize heightmaps for all zones
    /// Looks for heightmap files in the heightmaps/ directory
    pub fn init_heightmaps(&mut self) {
        self.heightmaps.clear();
        
        // Map zone IDs to empire names for file lookup
        let zone_empire_map: Vec<(u32, &str)> = vec![
            (1, "shinsoo"),
            (100, "chunjo"),
            (200, "jinno"),
        ];
        
        for (zone_id, empire_name) in zone_empire_map {
            let json_path = format!("heightmaps/{}_heightmap.json", empire_name);
            
            match Heightmap::load(&json_path) {
                Ok(heightmap) => {
                    info!("Loaded heightmap for zone {} ({})", zone_id, empire_name);
                    self.heightmaps.insert(zone_id, heightmap);
                }
                Err(e) => {
                    warn!("Could not load heightmap for zone {} ({}): {}", zone_id, empire_name, e);
                    debug!("Looking for: {}", json_path);
                }
            }
        }
        
        info!("Loaded {} heightmaps", self.heightmaps.len());
    }
    
    /// Initialize obstacles for all zones
    /// 
    /// First tries to load from obstacles.json (exported from Godot).
    /// Falls back to hardcoded obstacles if the file doesn't exist.
    pub fn init_obstacles(&mut self) {
        // Clear any existing obstacles
        self.obstacles.clear();
        
        // Try to load from JSON file first
        if self.load_obstacles_from_json("obstacles.json") {
            return;
        }
        
        info!("No obstacles.json found, using hardcoded fallback obstacles");
        self.init_hardcoded_obstacles();
    }
    
    /// Load obstacles from a JSON file exported by Godot
    /// Returns true if successful, false if file not found or parse error
    fn load_obstacles_from_json<P: AsRef<Path>>(&mut self, path: P) -> bool {
        let path = path.as_ref();
        
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(e) => {
                if e.kind() != std::io::ErrorKind::NotFound {
                    warn!("Failed to read obstacles file {:?}: {}", path, e);
                }
                return false;
            }
        };
        
        let json: serde_json::Value = match serde_json::from_str(&content) {
            Ok(v) => v,
            Err(e) => {
                error!("Failed to parse obstacles.json: {}", e);
                return false;
            }
        };
        
        let obj = match json.as_object() {
            Some(o) => o,
            None => {
                error!("obstacles.json root is not an object");
                return false;
            }
        };
        
        for (zone_id_str, obstacles_array) in obj {
            let zone_id: u32 = match zone_id_str.parse() {
                Ok(id) => id,
                Err(_) => {
                    warn!("Invalid zone ID in obstacles.json: {}", zone_id_str);
                    continue;
                }
            };
            
            let obstacles = match obstacles_array.as_array() {
                Some(arr) => arr,
                None => {
                    warn!("Zone {} obstacles is not an array", zone_id);
                    continue;
                }
            };
            
            let mut zone_obstacles = Vec::new();
            
            for obs in obstacles {
                if let Some(obstacle) = self.parse_obstacle(obs) {
                    zone_obstacles.push(obstacle);
                }
            }
            
            if !zone_obstacles.is_empty() {
                self.obstacles.insert(zone_id, zone_obstacles);
            }
        }
        
        let total_obstacles: usize = self.obstacles.values().map(|v| v.len()).sum();
        info!("Loaded {} obstacles from {:?} across {} zones", 
            total_obstacles, path, self.obstacles.len());
        
        // Log each zone's obstacles
        for (zone_id, obs) in &self.obstacles {
            info!("  Zone {}: {} obstacles", zone_id, obs.len());
        }
        
        true
    }
    
    /// Parse a single obstacle from JSON
    fn parse_obstacle(&self, value: &serde_json::Value) -> Option<Obstacle> {
        let obj = value.as_object()?;
        let obstacle_type = obj.get("type")?.as_str()?;
        
        match obstacle_type {
            "circle" => {
                let x = obj.get("center_x")?.as_f64()? as f32;
                let z = obj.get("center_z")?.as_f64()? as f32;
                let radius = obj.get("radius")?.as_f64()? as f32;
                Some(Obstacle::Circle(CircleObstacle::new(x, z, radius)))
            }
            "box" => {
                let x = obj.get("center_x")?.as_f64()? as f32;
                let z = obj.get("center_z")?.as_f64()? as f32;
                let half_w = obj.get("half_width")?.as_f64()? as f32;
                let half_d = obj.get("half_depth")?.as_f64()? as f32;
                Some(Obstacle::Box(BoxObstacle::from_center(x, z, half_w, half_d)))
            }
            _ => {
                warn!("Unknown obstacle type: {}", obstacle_type);
                None
            }
        }
    }
    
    /// Fallback: hardcoded obstacles matching the Godot scene layouts
    fn init_hardcoded_obstacles(&mut self) {
        // Common village obstacles (same layout for all empires)
        let village_obstacles = vec![
            // Decorative pillars at corners
            Obstacle::Circle(CircleObstacle::new(-15.0, -15.0, 1.5)),
            Obstacle::Circle(CircleObstacle::new(15.0, -15.0, 1.5)),
            Obstacle::Circle(CircleObstacle::new(-15.0, 15.0, 1.5)),
            Obstacle::Circle(CircleObstacle::new(15.0, 15.0, 1.5)),
            
            // Main building at (10, -8) with half-extents (4, 5)
            Obstacle::Box(BoxObstacle::from_center(10.0, -8.0, 4.0, 5.0)),
            
            // Secondary building at (-12, 8) with half-extents (3, 4)
            Obstacle::Box(BoxObstacle::from_center(-12.0, 8.0, 3.0, 4.0)),
            
            // Market stall at (-8, -5) with half-extents (2, 3)
            Obstacle::Box(BoxObstacle::from_center(-8.0, -5.0, 2.0, 3.0)),
        ];
        
        // Apply common obstacles to all zones
        for zone_id in self.zones.keys().copied().collect::<Vec<_>>() {
            self.obstacles.insert(zone_id, village_obstacles.clone());
        }
        
        let total_obstacles: usize = self.obstacles.values().map(|v| v.len()).sum();
        info!("Initialized {} obstacles across {} zones", total_obstacles, self.obstacles.len());
        
        // Debug: log each zone's obstacles
        for (zone_id, obs) in &self.obstacles {
            info!("  Zone {}: {} obstacles", zone_id, obs.len());
            for (i, obstacle) in obs.iter().enumerate() {
                match obstacle {
                    Obstacle::Circle(c) => {
                        info!("    [{}] Circle at ({}, {}) radius {}", i, c.center.x, c.center.z, c.radius);
                    }
                    Obstacle::Box(b) => {
                        info!("    [{}] Box from ({}, {}) to ({}, {})", i, b.min.x, b.min.z, b.max.x, b.max.z);
                    }
                }
            }
        }
    }
}

impl Default for ZoneManager {
    fn default() -> Self {
        Self::new()
    }
}
