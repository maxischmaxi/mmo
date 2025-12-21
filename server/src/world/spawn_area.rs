//! Spawn area system for managing enemy spawns within defined regions.
//!
//! Spawn areas are polygon-based regions where enemies can spawn. Each area
//! has configurable enemy types, population limits, and respawn timers.

use std::collections::HashMap;
use std::path::Path;
use log::{info, warn, error, debug};
use rand::Rng;
use mmo_shared::EnemyType;

/// Configuration for a single enemy type within a spawn area
#[derive(Debug, Clone)]
pub struct EnemySpawnConfig {
    pub enemy_type: EnemyType,
    pub weight: f32,
    pub min_level: u8,
    pub max_level: u8,
}

/// A spawn area defining where and what enemies can spawn
#[derive(Debug, Clone)]
pub struct SpawnArea {
    pub id: String,
    pub zone_id: u32,
    /// Polygon vertices in XZ world coordinates
    pub polygon: Vec<[f32; 2]>,
    /// Enemy types that can spawn in this area
    pub enemy_configs: Vec<EnemySpawnConfig>,
    /// Maximum concurrent enemies in this area
    pub max_population: u32,
    /// Respawn time in seconds after an enemy dies
    pub respawn_time_secs: f32,
    /// Minimum distance between spawned enemies
    pub min_spawn_distance: f32,
}

impl SpawnArea {
    /// Check if a point is inside the polygon (XZ coordinates)
    pub fn contains_point(&self, x: f32, z: f32) -> bool {
        if self.polygon.len() < 3 {
            return false;
        }
        
        // Ray casting algorithm
        let mut inside = false;
        let mut j = self.polygon.len() - 1;
        
        for i in 0..self.polygon.len() {
            let xi = self.polygon[i][0];
            let zi = self.polygon[i][1];
            let xj = self.polygon[j][0];
            let zj = self.polygon[j][1];
            
            if ((zi > z) != (zj > z)) && (x < (xj - xi) * (z - zi) / (zj - zi) + xi) {
                inside = !inside;
            }
            j = i;
        }
        
        inside
    }
    
    /// Get a random point inside the polygon
    pub fn get_random_point(&self) -> Option<[f32; 2]> {
        if self.polygon.len() < 3 {
            return None;
        }
        
        // Calculate bounding box
        let mut min_x = f32::MAX;
        let mut max_x = f32::MIN;
        let mut min_z = f32::MAX;
        let mut max_z = f32::MIN;
        
        for vertex in &self.polygon {
            min_x = min_x.min(vertex[0]);
            max_x = max_x.max(vertex[0]);
            min_z = min_z.min(vertex[1]);
            max_z = max_z.max(vertex[1]);
        }
        
        let mut rng = rand::thread_rng();
        
        // Rejection sampling
        for _ in 0..100 {
            let x = rng.gen_range(min_x..max_x);
            let z = rng.gen_range(min_z..max_z);
            
            if self.contains_point(x, z) {
                return Some([x, z]);
            }
        }
        
        // Fallback to centroid
        let mut cx = 0.0;
        let mut cz = 0.0;
        for vertex in &self.polygon {
            cx += vertex[0];
            cz += vertex[1];
        }
        let n = self.polygon.len() as f32;
        Some([cx / n, cz / n])
    }
    
    /// Select a random enemy type based on weights
    pub fn select_enemy_type(&self) -> Option<&EnemySpawnConfig> {
        if self.enemy_configs.is_empty() {
            return None;
        }
        
        let total_weight: f32 = self.enemy_configs.iter().map(|c| c.weight).sum();
        if total_weight <= 0.0 {
            return Some(&self.enemy_configs[0]);
        }
        
        let mut rng = rand::thread_rng();
        let roll = rng.gen_range(0.0..total_weight);
        
        let mut cumulative = 0.0;
        for config in &self.enemy_configs {
            cumulative += config.weight;
            if roll < cumulative {
                return Some(config);
            }
        }
        
        self.enemy_configs.last()
    }
    
    /// Calculate the area of the polygon
    pub fn get_area(&self) -> f32 {
        if self.polygon.len() < 3 {
            return 0.0;
        }
        
        let mut area = 0.0;
        let mut j = self.polygon.len() - 1;
        
        for i in 0..self.polygon.len() {
            area += (self.polygon[j][0] + self.polygon[i][0]) 
                  * (self.polygon[j][1] - self.polygon[i][1]);
            j = i;
        }
        
        (area / 2.0).abs()
    }
}

/// Pending respawn entry
#[derive(Debug)]
struct PendingRespawn {
    /// Time remaining until respawn (seconds)
    time_remaining: f32,
    /// Spawn area ID
    area_id: String,
    /// Zone ID
    zone_id: u32,
}

/// Manages spawn areas and enemy spawning
pub struct SpawnAreaManager {
    /// All spawn areas, keyed by zone_id
    areas: HashMap<u32, Vec<SpawnArea>>,
    /// Maps enemy_id to spawn area id
    enemy_to_area: HashMap<u64, String>,
    /// Pending respawns
    respawn_queue: Vec<PendingRespawn>,
    /// Current population per area (area_id -> count)
    area_population: HashMap<String, u32>,
}

impl SpawnAreaManager {
    pub fn new() -> Self {
        Self {
            areas: HashMap::new(),
            enemy_to_area: HashMap::new(),
            respawn_queue: Vec::new(),
            area_population: HashMap::new(),
        }
    }
    
    /// Load spawn areas from JSON file
    pub fn load_from_json<P: AsRef<Path>>(&mut self, path: P) -> Result<(), String> {
        let path = path.as_ref();
        
        let content = std::fs::read_to_string(path)
            .map_err(|e| format!("Failed to read spawn_areas.json: {}", e))?;
        
        let json: serde_json::Value = serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse spawn_areas.json: {}", e))?;
        
        let obj = json.as_object()
            .ok_or("spawn_areas.json root is not an object")?;
        
        self.areas.clear();
        
        for (zone_id_str, areas_array) in obj {
            let zone_id: u32 = zone_id_str.parse()
                .map_err(|_| format!("Invalid zone ID: {}", zone_id_str))?;
            
            let areas = areas_array.as_array()
                .ok_or(format!("Zone {} areas is not an array", zone_id))?;
            
            let mut zone_areas = Vec::new();
            
            for area_json in areas {
                if let Some(area) = self.parse_spawn_area(area_json, zone_id) {
                    zone_areas.push(area);
                }
            }
            
            if !zone_areas.is_empty() {
                info!("Loaded {} spawn areas for zone {}", zone_areas.len(), zone_id);
                self.areas.insert(zone_id, zone_areas);
            }
        }
        
        let total: usize = self.areas.values().map(|v| v.len()).sum();
        info!("Loaded {} total spawn areas from {:?}", total, path);
        
        Ok(())
    }
    
    /// Parse a single spawn area from JSON
    fn parse_spawn_area(&self, value: &serde_json::Value, zone_id: u32) -> Option<SpawnArea> {
        let obj = value.as_object()?;
        
        let id = obj.get("id")?.as_str()?.to_string();
        
        // Parse polygon
        let polygon_json = obj.get("polygon")?.as_array()?;
        let mut polygon = Vec::new();
        for vertex in polygon_json {
            let coords = vertex.as_array()?;
            if coords.len() >= 2 {
                let x = coords[0].as_f64()? as f32;
                let z = coords[1].as_f64()? as f32;
                polygon.push([x, z]);
            }
        }
        
        if polygon.len() < 3 {
            warn!("Spawn area {} has invalid polygon (< 3 vertices)", id);
            return None;
        }
        
        // Parse enemy configs
        let configs_json = obj.get("enemy_configs")?.as_array()?;
        let mut enemy_configs = Vec::new();
        for config_json in configs_json {
            if let Some(config) = self.parse_enemy_config(config_json) {
                enemy_configs.push(config);
            }
        }
        
        if enemy_configs.is_empty() {
            warn!("Spawn area {} has no valid enemy configs", id);
            return None;
        }
        
        let max_population = obj.get("max_population")
            .and_then(|v| v.as_u64())
            .unwrap_or(5) as u32;
        
        let respawn_time_secs = obj.get("respawn_time_secs")
            .and_then(|v| v.as_f64())
            .unwrap_or(60.0) as f32;
        
        let min_spawn_distance = obj.get("min_spawn_distance")
            .and_then(|v| v.as_f64())
            .unwrap_or(2.0) as f32;
        
        Some(SpawnArea {
            id,
            zone_id,
            polygon,
            enemy_configs,
            max_population,
            respawn_time_secs,
            min_spawn_distance,
        })
    }
    
    /// Parse an enemy config from JSON
    fn parse_enemy_config(&self, value: &serde_json::Value) -> Option<EnemySpawnConfig> {
        let obj = value.as_object()?;
        
        let enemy_type_str = obj.get("enemy_type")?.as_str()?;
        let enemy_type = match enemy_type_str.to_lowercase().as_str() {
            "goblin" => EnemyType::Goblin,
            "wolf" => EnemyType::Wolf,
            "skeleton" => EnemyType::Skeleton,
            "mutant" => EnemyType::Mutant,
            _ => {
                warn!("Unknown enemy type: {}", enemy_type_str);
                return None;
            }
        };
        
        let weight = obj.get("weight")
            .and_then(|v| v.as_f64())
            .unwrap_or(1.0) as f32;
        
        let min_level = obj.get("min_level")
            .and_then(|v| v.as_u64())
            .unwrap_or(1) as u8;
        
        let max_level = obj.get("max_level")
            .and_then(|v| v.as_u64())
            .unwrap_or(5) as u8;
        
        Some(EnemySpawnConfig {
            enemy_type,
            weight,
            min_level,
            max_level,
        })
    }
    
    /// Check if spawn areas are loaded
    pub fn has_spawn_areas(&self) -> bool {
        !self.areas.is_empty()
    }
    
    /// Get spawn areas for a zone
    pub fn get_areas(&self, zone_id: u32) -> &[SpawnArea] {
        self.areas.get(&zone_id).map(|v| v.as_slice()).unwrap_or(&[])
    }
    
    /// Get all zone IDs with spawn areas
    pub fn get_zone_ids(&self) -> Vec<u32> {
        self.areas.keys().copied().collect()
    }
    
    /// Get spawn requests for initial population
    /// Returns: Vec<(zone_id, position_xz, enemy_type, level)>
    pub fn get_initial_spawns(&mut self) -> Vec<(u32, [f32; 2], EnemyType, u8)> {
        let mut spawns = Vec::new();
        let mut rng = rand::thread_rng();
        
        for (zone_id, areas) in &self.areas {
            for area in areas {
                // Spawn up to max_population
                for _ in 0..area.max_population {
                    if let Some(pos) = area.get_random_point() {
                        if let Some(config) = area.select_enemy_type() {
                            let level = rng.gen_range(config.min_level..=config.max_level);
                            spawns.push((*zone_id, pos, config.enemy_type, level));
                            
                            // Track population
                            *self.area_population.entry(area.id.clone()).or_insert(0) += 1;
                        }
                    }
                }
            }
        }
        
        spawns
    }
    
    /// Register an enemy as belonging to a spawn area
    pub fn register_enemy(&mut self, enemy_id: u64, area_id: &str) {
        self.enemy_to_area.insert(enemy_id, area_id.to_string());
    }
    
    /// Called when an enemy dies - queues respawn
    pub fn on_enemy_death(&mut self, enemy_id: u64) {
        if let Some(area_id) = self.enemy_to_area.remove(&enemy_id) {
            // Decrement population
            if let Some(pop) = self.area_population.get_mut(&area_id) {
                *pop = pop.saturating_sub(1);
            }
            
            // Find the area to get respawn time
            let respawn_time = self.find_area(&area_id)
                .map(|a| a.respawn_time_secs)
                .unwrap_or(60.0);
            
            let zone_id = self.find_area(&area_id)
                .map(|a| a.zone_id)
                .unwrap_or(1);
            
            debug!("Enemy {} died in area {}, respawning in {:.1}s", 
                enemy_id, area_id, respawn_time);
            
            self.respawn_queue.push(PendingRespawn {
                time_remaining: respawn_time,
                area_id,
                zone_id,
            });
        }
    }
    
    /// Find an area by ID
    fn find_area(&self, area_id: &str) -> Option<&SpawnArea> {
        for areas in self.areas.values() {
            for area in areas {
                if area.id == area_id {
                    return Some(area);
                }
            }
        }
        None
    }
    
    /// Update respawn timers and return spawn requests
    /// Returns: Vec<(zone_id, position_xz, enemy_type, level)>
    pub fn update(&mut self, delta: f32) -> Vec<(u32, [f32; 2], EnemyType, u8)> {
        let mut spawns = Vec::new();
        let mut rng = rand::thread_rng();
        
        // Update respawn timers
        let mut completed = Vec::new();
        for (i, respawn) in self.respawn_queue.iter_mut().enumerate() {
            respawn.time_remaining -= delta;
            if respawn.time_remaining <= 0.0 {
                completed.push(i);
            }
        }
        
        // Process completed respawns (in reverse order to avoid index issues)
        for i in completed.into_iter().rev() {
            let respawn = self.respawn_queue.remove(i);
            
            // Find the area and check population
            if let Some(area) = self.find_area(&respawn.area_id) {
                let current_pop = self.area_population.get(&area.id).copied().unwrap_or(0);
                
                if current_pop < area.max_population {
                    if let Some(pos) = area.get_random_point() {
                        if let Some(config) = area.select_enemy_type() {
                            let level = rng.gen_range(config.min_level..=config.max_level);
                            
                            debug!("Respawning enemy in area {} at ({:.1}, {:.1})", 
                                area.id, pos[0], pos[1]);
                            
                            spawns.push((respawn.zone_id, pos, config.enemy_type, level));
                            
                            // Track population
                            *self.area_population.entry(area.id.clone()).or_insert(0) += 1;
                        }
                    }
                } else {
                    debug!("Area {} at max population {}, skipping respawn", 
                        area.id, area.max_population);
                }
            }
        }
        
        spawns
    }
    
    /// Get the area ID for a given enemy position (for assigning enemies to areas)
    pub fn find_area_at(&self, zone_id: u32, x: f32, z: f32) -> Option<&str> {
        if let Some(areas) = self.areas.get(&zone_id) {
            for area in areas {
                if area.contains_point(x, z) {
                    return Some(&area.id);
                }
            }
        }
        None
    }
    
    /// Get current population of an area
    pub fn get_area_population(&self, area_id: &str) -> u32 {
        self.area_population.get(area_id).copied().unwrap_or(0)
    }
}

impl Default for SpawnAreaManager {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Debug for SpawnAreaManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SpawnAreaManager")
            .field("areas", &self.areas.keys().collect::<Vec<_>>())
            .field("enemy_count", &self.enemy_to_area.len())
            .field("pending_respawns", &self.respawn_queue.len())
            .finish()
    }
}
