//! Game world management.

mod zone_manager;
pub mod heightmap;

pub use zone_manager::{ZoneManager, ZoneDefinition, ZoneSpawnPoint, ZoneEnemySpawn, ZoneNpcSpawn};
pub use heightmap::Heightmap;

use std::collections::HashMap;
use log::{info, debug};
use rand::Rng;

use mmo_shared::{
    ServerMessage, AnimationState, EnemyType, NpcType, NpcState, InventorySlot, ItemDef, ItemType,
    CharacterClass, Gender, Empire, AbilityEffect, TargetType,
    get_ability_by_id,
};

/// Result of equipping an item
pub enum EquipResult {
    Weapon(Option<u32>),
    Armor(Option<u32>),
}

use crate::entities::player::BuffEffect;

use crate::persistence::InventorySlotData;

use crate::entities::{ServerPlayer, ServerEnemy, ServerNpc, WorldItem};

/// The game world containing all entities
pub struct GameWorld {
    players: HashMap<u64, ServerPlayer>,
    enemies: HashMap<u64, ServerEnemy>,
    npcs: HashMap<u64, ServerNpc>,
    world_items: HashMap<u64, WorldItem>,
    next_enemy_id: u64,
    next_npc_id: u64,
    next_item_id: u64,
    /// Item definitions loaded from database
    pub items: HashMap<u32, ItemDef>,
    /// Zone manager
    pub zone_manager: ZoneManager,
}

impl GameWorld {
    pub fn new(items: HashMap<u32, ItemDef>, zone_manager: ZoneManager) -> Self {
        let mut world = Self {
            players: HashMap::new(),
            enemies: HashMap::new(),
            npcs: HashMap::new(),
            world_items: HashMap::new(),
            next_enemy_id: 10000, // Start enemy IDs high to avoid confusion with player IDs
            next_npc_id: 30000,   // NPCs start at 30000
            next_item_id: 20000,
            items,
            zone_manager,
        };
        
        // Spawn enemies for all zones
        world.spawn_all_zone_enemies();
        
        // Spawn NPCs for all zones
        world.spawn_all_zone_npcs();
        
        world
    }
    
    /// Spawn enemies for all zones using zone_manager data
    fn spawn_all_zone_enemies(&mut self) {
        let zone_ids = self.zone_manager.get_zone_ids();
        let mut total_spawned = 0;
        
        // Collect spawn data first to avoid borrow issues
        let mut spawn_data: Vec<(u32, [f32; 3], EnemyType)> = Vec::new();
        for zone_id in zone_ids {
            let spawns = self.zone_manager.get_enemy_spawns(zone_id);
            for spawn in spawns {
                spawn_data.push((zone_id, spawn.position, spawn.enemy_type));
            }
        }
        
        // Now spawn enemies
        for (zone_id, position, enemy_type) in spawn_data {
            self.spawn_enemy(zone_id, position, enemy_type);
            total_spawned += 1;
        }
        
        info!("Spawned {} enemies across all zones", total_spawned);
    }
    
    /// Spawn NPCs for all zones using zone_manager data
    fn spawn_all_zone_npcs(&mut self) {
        let zone_ids = self.zone_manager.get_zone_ids();
        let mut total_spawned = 0;
        
        // Collect spawn data first to avoid borrow issues
        let mut spawn_data: Vec<(u32, [f32; 3], f32, NpcType)> = Vec::new();
        for zone_id in zone_ids {
            let spawns = self.zone_manager.get_npc_spawns(zone_id);
            for spawn in spawns {
                spawn_data.push((zone_id, spawn.position, spawn.rotation, spawn.npc_type));
            }
        }
        
        // Now spawn NPCs
        for (zone_id, position, rotation, npc_type) in spawn_data {
            self.spawn_npc(zone_id, position, rotation, npc_type);
            total_spawned += 1;
        }
        
        info!("Spawned {} NPCs across all zones (next_npc_id: {})", total_spawned, self.next_npc_id);
    }
    
    /// Spawn a new NPC in a zone
    /// Automatically adjusts Y position based on terrain heightmap
    pub fn spawn_npc(&mut self, zone_id: u32, position: [f32; 3], rotation: f32, npc_type: NpcType) -> u64 {
        let id = self.next_npc_id;
        self.next_npc_id += 1;
        
        // Adjust Y position based on terrain height plus ground offset
        let terrain_height = self.zone_manager.get_terrain_height(zone_id, position[0], position[2]);
        let adjusted_position = [position[0], terrain_height + Self::ENTITY_GROUND_OFFSET, position[2]];
        
        debug!("Spawning NPC {} at ({:.1}, {:.1}, {:.1}) -> adjusted Y to {:.1} (terrain: {:.1})",
            id, position[0], position[1], position[2], adjusted_position[1], terrain_height);
        
        let npc = ServerNpc::new(id, zone_id, npc_type, adjusted_position, rotation);
        self.npcs.insert(id, npc);
        
        id
    }
    
    /// Get all NPCs
    pub fn get_npcs(&self) -> Vec<&ServerNpc> {
        self.npcs.values().collect()
    }
    
    /// Get all NPCs in a specific zone
    pub fn get_npcs_in_zone(&self, zone_id: u32) -> Vec<&ServerNpc> {
        self.npcs.values()
            .filter(|n| n.zone_id == zone_id)
            .collect()
    }
    
    /// Spawn enemies for a specific zone
    pub fn spawn_enemies_for_zone(&mut self, zone_id: u32) -> Vec<ServerMessage> {
        let mut messages = Vec::new();
        
        // Collect spawn data first to avoid borrow issues
        let spawn_data: Vec<([f32; 3], EnemyType)> = self.zone_manager
            .get_enemy_spawns(zone_id)
            .iter()
            .map(|spawn| (spawn.position, spawn.enemy_type))
            .collect();
        
        for (position, enemy_type) in spawn_data {
            let enemy_id = self.spawn_enemy(zone_id, position, enemy_type);
            if let Some(enemy) = self.enemies.get(&enemy_id) {
                messages.push(ServerMessage::EnemySpawn {
                    id: enemy_id,
                    zone_id,
                    enemy_type: enemy.enemy_type,
                    position: enemy.position,
                    health: enemy.health,
                    max_health: enemy.max_health,
                    level: enemy.level,
                });
            }
        }
        
        messages
    }
    
    /// Small offset added to terrain height for entity spawning.
    /// This is just a tiny buffer to ensure entities don't clip into the terrain
    /// due to floating point precision. The heightmap now contains actual
    /// Terrain3D heights, so only a minimal offset is needed.
    const ENTITY_GROUND_OFFSET: f32 = 0.1;
    
    /// Spawn a new enemy in a zone
    /// Automatically adjusts Y position based on terrain heightmap
    pub fn spawn_enemy(&mut self, zone_id: u32, position: [f32; 3], enemy_type: EnemyType) -> u64 {
        let id = self.next_enemy_id;
        self.next_enemy_id += 1;
        
        // Adjust Y position based on terrain height plus ground offset
        let terrain_height = self.zone_manager.get_terrain_height(zone_id, position[0], position[2]);
        let adjusted_position = [position[0], terrain_height + Self::ENTITY_GROUND_OFFSET, position[2]];
        
        info!("Spawning enemy {} at ({:.1}, {:.1}, {:.1}) -> adjusted Y to {:.1} (terrain: {:.1}, offset: {:.1})",
            id, position[0], position[1], position[2], adjusted_position[1], terrain_height, Self::ENTITY_GROUND_OFFSET);
        
        let enemy = ServerEnemy::new(id, zone_id, enemy_type, adjusted_position);
        self.enemies.insert(id, enemy);
        
        id
    }
    
    /// Spawn a player with saved state (for character selection)
    #[allow(clippy::too_many_arguments)]
    pub fn spawn_player_with_state(
        &mut self,
        id: u64,
        name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
        zone_id: u32,
        position: [f32; 3],
        rotation: f32,
        health: u32,
        max_health: u32,
        mana: u32,
        max_mana: u32,
        attack: u32,
        defense: u32,
        inventory_data: &[InventorySlotData],
        equipped_weapon_id: Option<u32>,
        equipped_armor_id: Option<u32>,
        level: u32,
        experience: u32,
        gold: u64,
    ) {
        // Convert inventory data to slots
        let mut inventory: Vec<Option<InventorySlot>> = vec![None; 20];
        for slot_data in inventory_data {
            if (slot_data.slot as usize) < inventory.len() {
                inventory[slot_data.slot as usize] = Some(InventorySlot {
                    item_id: slot_data.item_id as u32,
                    quantity: slot_data.quantity as u32,
                });
            }
        }
        
        let player = ServerPlayer::with_state_and_armor(
            id,
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
            attack,
            defense,
            inventory,
            equipped_weapon_id,
            equipped_armor_id,
            level,
            experience,
            gold,
        );
        self.players.insert(id, player);
    }
    
    /// Despawn a player
    pub fn despawn_player(&mut self, id: u64) {
        self.players.remove(&id);
    }
    
    /// Respawn a player at a new position with specified health
    pub fn respawn_player(&mut self, id: u64, position: [f32; 3], health: u32) {
        if let Some(player) = self.players.get_mut(&id) {
            player.position = position;
            player.health = health;
            player.animation_state = AnimationState::Idle;
            player.death_announced = false;  // Reset for next death
        }
    }
    
    /// Get a player by ID
    pub fn get_player(&self, id: u64) -> Option<&ServerPlayer> {
        self.players.get(&id)
    }
    
    /// Get a mutable reference to a player by ID
    pub fn get_player_mut(&mut self, id: u64) -> Option<&mut ServerPlayer> {
        self.players.get_mut(&id)
    }
    
    /// Get all players
    pub fn get_players(&self) -> Vec<&ServerPlayer> {
        self.players.values().collect()
    }
    
    /// Get all players in a specific zone
    pub fn get_players_in_zone(&self, zone_id: u32) -> Vec<&ServerPlayer> {
        self.players.values()
            .filter(|p| p.zone_id == zone_id)
            .collect()
    }
    
    /// Get all enemies
    pub fn get_enemies(&self) -> Vec<&ServerEnemy> {
        self.enemies.values().collect()
    }
    
    /// Get all enemies in a specific zone
    pub fn get_enemies_in_zone(&self, zone_id: u32) -> Vec<&ServerEnemy> {
        self.enemies.values()
            .filter(|e| e.zone_id == zone_id)
            .collect()
    }
    
    /// Check if an enemy exists
    pub fn has_enemy(&self, id: u64) -> bool {
        self.enemies.contains_key(&id)
    }
    
    /// Get an enemy by ID
    pub fn get_enemy(&self, id: u64) -> Option<&ServerEnemy> {
        self.enemies.get(&id)
    }
    
    /// Get a mutable reference to an enemy by ID
    pub fn get_enemy_mut(&mut self, id: u64) -> Option<&mut ServerEnemy> {
        self.enemies.get_mut(&id)
    }
    
    /// Update player state from client input
    pub fn update_player_state(
        &mut self,
        player_id: u64,
        position: [f32; 3],
        rotation: f32,
        velocity: [f32; 3],
        animation_state: AnimationState,
    ) {
        if let Some(player) = self.players.get_mut(&player_id) {
            // TODO: Validate position (anti-cheat)
            player.position = position;
            player.rotation = rotation;
            player.velocity = velocity;
            player.animation_state = animation_state;
        }
    }
    
    /// Process an attack from a player to a target
    pub fn process_attack(&mut self, attacker_id: u64, target_id: u64) -> Option<ServerMessage> {
        let attacker = self.players.get(&attacker_id)?;
        
        // Check if target is an enemy
        if let Some(enemy) = self.enemies.get_mut(&target_id) {
            // Check range (simple distance check)
            let dx = enemy.position[0] - attacker.position[0];
            let dz = enemy.position[2] - attacker.position[2];
            let dist_sq = dx * dx + dz * dz;
            
            if dist_sq > 5.0 * 5.0 {
                debug!("Attack out of range");
                return None;
            }
            
            // Calculate damage based on equipped weapon
            let base_damage = attacker.calculate_attack_damage(&self.items);
            let mut rng = rand::thread_rng();
            let is_critical = rng.gen_bool(0.1); // 10% crit chance
            let damage = if is_critical { base_damage * 2 } else { base_damage };
            
            // Apply damage
            enemy.health = enemy.health.saturating_sub(damage);
            enemy.target_id = Some(attacker_id); // Aggro
            
            return Some(ServerMessage::DamageEvent {
                attacker_id,
                target_id,
                damage,
                target_new_health: enemy.health,
                is_critical,
            });
        }
        
        // TODO: PvP combat
        
        None
    }
    
    /// Pickup an item from the world
    pub fn pickup_item(&mut self, player_id: u64, item_entity_id: u64) -> Option<(ServerMessage, ServerMessage)> {
        let item = self.world_items.remove(&item_entity_id)?;
        let player = self.players.get_mut(&player_id)?;
        
        // Try to add to inventory
        player.add_to_inventory(item.item_id, item.quantity);
        
        let despawn_msg = ServerMessage::ItemDespawn {
            entity_id: item_entity_id,
        };
        
        let inv_msg = ServerMessage::InventoryUpdate {
            slots: player.get_inventory_slots(),
        };
        
        Some((despawn_msg, inv_msg))
    }
    
    /// Use an item from inventory
    pub fn use_item(&mut self, player_id: u64, slot: u8) -> Option<ServerMessage> {
        let player = self.players.get_mut(&player_id)?;
        player.use_item(slot)?;
        
        Some(ServerMessage::InventoryUpdate {
            slots: player.get_inventory_slots(),
        })
    }
    
    /// Drop an item from inventory
    pub fn drop_item(&mut self, player_id: u64, slot: u8) -> Option<(ServerMessage, ServerMessage)> {
        let player = self.players.get_mut(&player_id)?;
        let (item_id, quantity) = player.remove_from_inventory(slot)?;
        
        // Spawn item in world
        let entity_id = self.next_item_id;
        self.next_item_id += 1;
        
        let position = player.position;
        self.world_items.insert(entity_id, WorldItem {
            entity_id,
            item_id,
            quantity,
            position,
        });
        
        let spawn_msg = ServerMessage::ItemSpawn {
            entity_id,
            item_id,
            position,
        };
        
        let inv_msg = ServerMessage::InventoryUpdate {
            slots: player.get_inventory_slots(),
        };
        
        Some((spawn_msg, inv_msg))
    }
    
    /// Equip an item from inventory (weapon or armor)
    /// Returns Ok(EquipResult) on success, Err(reason) on failure
    pub fn equip_item(&mut self, player_id: u64, inventory_slot: u8) -> Result<EquipResult, &'static str> {
        // First check what type of item is in the slot
        let player = self.players.get(&player_id).ok_or("Player not found")?;
        let inv_slot = player.inventory.get(inventory_slot as usize)
            .ok_or("Invalid inventory slot")?
            .as_ref()
            .ok_or("No item in slot")?;
        let item_id = inv_slot.item_id;
        
        let item = self.items.get(&item_id).ok_or("Item not found")?;
        let item_type = item.item_type;
        
        // Now get mutable reference and equip based on type
        let player = self.players.get_mut(&player_id).ok_or("Player not found")?;
        
        match item_type {
            ItemType::Weapon => {
                player.try_equip_weapon(inventory_slot, &self.items)?;
                Ok(EquipResult::Weapon(player.equipped_weapon_id))
            }
            ItemType::Armor => {
                player.try_equip_armor(inventory_slot, &self.items)?;
                Ok(EquipResult::Armor(player.equipped_armor_id))
            }
            _ => Err("Item cannot be equipped"),
        }
    }
    
    /// Unequip weapon
    /// Returns the previously equipped weapon ID
    pub fn unequip_weapon(&mut self, player_id: u64) -> Option<u32> {
        let player = self.players.get_mut(&player_id)?;
        player.unequip_weapon()
    }
    
    /// Unequip armor
    /// Returns the previously equipped armor ID
    pub fn unequip_armor(&mut self, player_id: u64) -> Option<u32> {
        let player = self.players.get_mut(&player_id)?;
        player.unequip_armor()
    }
    
    /// Add item to a player's inventory (for dev commands)
    pub fn add_item_to_player(&mut self, player_id: u64, item_id: u32, quantity: u32) -> Option<ServerMessage> {
        let player = self.players.get_mut(&player_id)?;
        player.add_to_inventory(item_id, quantity);
        
        Some(ServerMessage::InventoryUpdate {
            slots: player.get_inventory_slots(),
        })
    }
    
    /// Swap two inventory slots (for drag & drop)
    pub fn swap_inventory_slots(&mut self, player_id: u64, from_slot: u8, to_slot: u8) -> Option<ServerMessage> {
        let player = self.players.get_mut(&player_id)?;
        
        // Validate slots
        if from_slot >= 20 || to_slot >= 20 {
            return None;
        }
        
        // Swap the slots in player's inventory
        player.inventory.swap(from_slot as usize, to_slot as usize);
        
        Some(ServerMessage::InventoryUpdate {
            slots: player.get_inventory_slots(),
        })
    }
    
    /// Update the world (called every tick)
    /// Returns a list of messages that should be broadcast to all clients
    pub fn update(&mut self, delta: f32, _tick: u64) -> Vec<ServerMessage> {
        let mut messages = Vec::new();
        
        // Update enemies (AI, attacks) and collect damage events
        let damage_events = self.update_enemies(delta);
        messages.extend(damage_events);
        
        // Check for dead enemies and handle loot drops
        let death_messages = self.process_enemy_deaths();
        messages.extend(death_messages);
        
        messages
    }
    
    /// Update enemy AI and process enemy attacks
    /// Returns damage events to broadcast
    fn update_enemies(&mut self, delta: f32) -> Vec<ServerMessage> {
        let mut damage_events = Vec::new();
        
        // Build a map of zone_id -> player positions for that zone
        let mut zone_player_positions: HashMap<u32, Vec<(u64, [f32; 3])>> = HashMap::new();
        for player in self.players.values() {
            if !player.is_dead() {
                zone_player_positions
                    .entry(player.zone_id)
                    .or_insert_with(Vec::new)
                    .push((player.id, player.position));
            }
        }
        
        // Collect attacks from enemies
        let mut attacks: Vec<(u64, u64, u32)> = Vec::new(); // (enemy_id, player_id, damage)
        
        // Log obstacle count once per update cycle (not per enemy)
        static OBSTACLE_LOG_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let log_count = OBSTACLE_LOG_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        
        for enemy in self.enemies.values_mut() {
            // Get players in the same zone as this enemy
            let player_positions = zone_player_positions
                .get(&enemy.zone_id)
                .map(|v| v.as_slice())
                .unwrap_or(&[]);
            
            // Get obstacles for this zone
            let obstacles = self.zone_manager.get_obstacles(enemy.zone_id);
            
            // Debug log every 100 updates (about every 5 seconds at 20 tick/s)
            if log_count % 100 == 0 && enemy.target_id.is_some() {
                debug!("Enemy {} in zone {} chasing target, {} obstacles available", 
                    enemy.id, enemy.zone_id, obstacles.len());
            }
            
            if let Some((target_player_id, damage)) = enemy.update(delta, player_positions, obstacles) {
                attacks.push((enemy.id, target_player_id, damage));
            }
        }
        
        // Update enemy Y positions based on terrain height
        // This is done after movement to ensure enemies follow the terrain
        for enemy in self.enemies.values_mut() {
            let terrain_height = self.zone_manager.get_terrain_height(
                enemy.zone_id,
                enemy.position[0],
                enemy.position[2]
            );
            // Apply ground offset to ensure enemies stand ON the terrain
            enemy.position[1] = terrain_height + Self::ENTITY_GROUND_OFFSET;
            // Also update spawn position Y if it hasn't been set
            if enemy.spawn_position[1] == 0.0 {
                enemy.spawn_position[1] = self.zone_manager.get_terrain_height(
                    enemy.zone_id,
                    enemy.spawn_position[0],
                    enemy.spawn_position[2]
                ) + Self::ENTITY_GROUND_OFFSET;
            }
        }
        
        // Process attacks and apply damage to players
        for (attacker_id, target_id, base_damage) in attacks {
            if let Some(player) = self.players.get_mut(&target_id) {
                // Skip if player is already dead
                if player.is_dead() {
                    continue;
                }
                
                // Apply damage (defense reduces damage by ~50%)
                let actual_damage = player.take_damage(base_damage);
                
                damage_events.push(ServerMessage::DamageEvent {
                    attacker_id,
                    target_id,
                    damage: actual_damage,
                    target_new_health: player.health,
                    is_critical: false, // Enemies don't crit for now
                });
                
                // Check if player died (and death not yet announced)
                if player.is_dead() && !player.death_announced {
                    info!("Player {} was killed by enemy {}", target_id, attacker_id);
                    player.death_announced = true;
                    // Send death message to all clients
                    damage_events.push(ServerMessage::EntityDeath {
                        entity_id: target_id,
                        killer_id: Some(attacker_id),
                    });
                }
            }
        }
        
        damage_events
    }
    
    /// Process enemy deaths and spawn loot, award XP and gold
    /// Returns (broadcast_messages, player_specific_messages)
    /// player_specific_messages is a Vec of (player_id, Vec<ServerMessage>)
    fn process_enemy_deaths(&mut self) -> Vec<ServerMessage> {
        let mut messages = Vec::new();
        
        // Collect dead enemies with their killer info
        let dead_enemies: Vec<(u64, Option<u64>, u8)> = self.enemies
            .iter()
            .filter(|(_, e)| e.health == 0)
            .map(|(id, e)| (*id, e.target_id, e.level))
            .collect();
        
        let mut rng = rand::thread_rng();
        
        for (enemy_id, killer_id, enemy_level) in dead_enemies {
            if let Some(enemy) = self.enemies.remove(&enemy_id) {
                info!("Enemy {} (level {}) died, killer: {:?}", enemy_id, enemy_level, killer_id);
                
                // Award XP and gold to killer
                if let Some(player_id) = killer_id {
                    if let Some(player) = self.players.get_mut(&player_id) {
                        // Calculate and award XP
                        let xp_gained = ServerPlayer::calculate_xp_for_enemy(player.level, enemy_level);
                        let level_up = player.add_experience(xp_gained);
                        
                        info!("Player {} gained {} XP (total: {})", player.name, xp_gained, player.experience);
                        
                        // Send XP gained message
                        messages.push(ServerMessage::ExperienceGained {
                            amount: xp_gained,
                            current_experience: player.experience,
                            experience_to_next_level: player.get_experience_to_next_level(),
                        });
                        
                        // If leveled up, send level up message
                        if let Some(new_level) = level_up {
                            info!("Player {} leveled up to {}", player.name, new_level);
                            messages.push(ServerMessage::LevelUp {
                                new_level,
                                max_health: player.max_health,
                                max_mana: player.max_mana,
                                attack: player.attack_power,
                                defense: player.defense,
                            });
                        }
                        
                        // Award gold (enemy_level * 5-15 random)
                        let gold_gained = (enemy_level as u64) * rng.gen_range(5..=15);
                        player.gold += gold_gained;
                        
                        info!("Player {} gained {} gold", player.name, gold_gained);
                        messages.push(ServerMessage::GoldUpdate { gold: player.gold });
                    }
                }
                
                // Broadcast enemy despawn
                messages.push(ServerMessage::EnemyDespawn { id: enemy_id });
                
                // Spawn loot
                if rng.gen_bool(0.5) {
                    let item_entity_id = self.next_item_id;
                    self.next_item_id += 1;
                    
                    let item = WorldItem {
                        entity_id: item_entity_id,
                        item_id: 3, // Goblin Ear
                        quantity: 1,
                        position: enemy.position,
                    };
                    self.world_items.insert(item_entity_id, item.clone());
                    
                    messages.push(ServerMessage::ItemSpawn {
                        entity_id: item_entity_id,
                        item_id: item.item_id,
                        position: item.position,
                    });
                }
                
                // Health potion drop
                if rng.gen_bool(0.2) {
                    let item_entity_id = self.next_item_id;
                    self.next_item_id += 1;
                    
                    let position = [
                        enemy.position[0] + rng.gen_range(-1.0..1.0),
                        enemy.position[1],
                        enemy.position[2] + rng.gen_range(-1.0..1.0),
                    ];
                    
                    let item = WorldItem {
                        entity_id: item_entity_id,
                        item_id: 1, // Health Potion
                        quantity: 1,
                        position,
                    };
                    self.world_items.insert(item_entity_id, item);
                    
                    messages.push(ServerMessage::ItemSpawn {
                        entity_id: item_entity_id,
                        item_id: 1,
                        position,
                    });
                }
                
                // Respawn enemy after delay (simplified: immediate respawn at random location)
                let new_pos = [
                    enemy.spawn_position[0] + rng.gen_range(-5.0..5.0),
                    enemy.spawn_position[1],
                    enemy.spawn_position[2] + rng.gen_range(-5.0..5.0),
                ];
                // Preserve zone_id when respawning
                let zone_id = enemy.zone_id;
                let new_enemy_id = self.spawn_enemy(zone_id, new_pos, enemy.enemy_type);
                
                // Broadcast new enemy spawn
                if let Some(new_enemy) = self.enemies.get(&new_enemy_id) {
                    messages.push(ServerMessage::EnemySpawn {
                        id: new_enemy_id,
                        zone_id,
                        enemy_type: new_enemy.enemy_type,
                        position: new_enemy.position,
                        health: new_enemy.health,
                        max_health: new_enemy.max_health,
                        level: new_enemy.level,
                    });
                }
            }
        }
        
        messages
    }
    
    /// Award XP to a player (for commands)
    pub fn add_experience_to_player(&mut self, player_id: u64, amount: u32) -> Option<(u32, Option<u32>)> {
        let player = self.players.get_mut(&player_id)?;
        let level_up = player.add_experience(amount);
        Some((player.experience, level_up))
    }
    
    /// Set XP for a player (for commands)
    pub fn set_player_experience(&mut self, player_id: u64, experience: u32) -> Option<(u32, u32, Option<u32>)> {
        let player = self.players.get_mut(&player_id)?;
        let level_changed = player.set_experience(experience);
        Some((player.experience, player.level, level_changed))
    }
    
    // ==========================================================================
    // Ability System
    // ==========================================================================
    
    /// Process an ability use request
    /// Returns (messages_for_caster, messages_for_broadcast)
    pub fn process_ability(
        &mut self,
        caster_id: u64,
        ability_id: u32,
        target_id: Option<u64>,
    ) -> (Vec<ServerMessage>, Vec<ServerMessage>) {
        let mut caster_msgs = Vec::new();
        let mut broadcast_msgs = Vec::new();
        
        // Get ability definition
        let ability = match get_ability_by_id(ability_id) {
            Some(a) => a,
            None => {
                caster_msgs.push(ServerMessage::AbilityFailed {
                    ability_id,
                    reason: "Unknown ability".into(),
                });
                return (caster_msgs, broadcast_msgs);
            }
        };
        
        // Get caster
        let caster = match self.players.get(&caster_id) {
            Some(p) => p,
            None => return (caster_msgs, broadcast_msgs),
        };
        
        // Check if dead
        if caster.is_dead() {
            caster_msgs.push(ServerMessage::AbilityFailed {
                ability_id,
                reason: "You are dead".into(),
            });
            return (caster_msgs, broadcast_msgs);
        }
        
        // Check if stunned
        if caster.is_stunned() {
            caster_msgs.push(ServerMessage::AbilityFailed {
                ability_id,
                reason: "You are stunned".into(),
            });
            return (caster_msgs, broadcast_msgs);
        }
        
        // Check class restriction
        if let Some(required_class) = ability.class_restriction {
            if caster.class != required_class {
                caster_msgs.push(ServerMessage::AbilityFailed {
                    ability_id,
                    reason: format!("Requires {} class", required_class.name()),
                });
                return (caster_msgs, broadcast_msgs);
            }
        }
        
        // Check level requirement
        if caster.level < ability.level_requirement {
            caster_msgs.push(ServerMessage::AbilityFailed {
                ability_id,
                reason: format!("Requires level {}", ability.level_requirement),
            });
            return (caster_msgs, broadcast_msgs);
        }
        
        // Check cooldown
        if caster.is_ability_on_cooldown(ability_id) {
            let remaining = caster.get_ability_cooldown(ability_id);
            caster_msgs.push(ServerMessage::AbilityFailed {
                ability_id,
                reason: format!("On cooldown ({:.1}s)", remaining),
            });
            return (caster_msgs, broadcast_msgs);
        }
        
        // Check mana
        if caster.mana < ability.mana_cost {
            caster_msgs.push(ServerMessage::AbilityFailed {
                ability_id,
                reason: "Not enough mana".into(),
            });
            return (caster_msgs, broadcast_msgs);
        }
        
        // Validate target based on ability type
        let validated_target = match ability.target_type {
            TargetType::SelfOnly => Some(caster_id),
            TargetType::Enemy => {
                match target_id {
                    Some(tid) => {
                        // Check if target exists and is an enemy
                        if !self.enemies.contains_key(&tid) {
                            caster_msgs.push(ServerMessage::AbilityFailed {
                                ability_id,
                                reason: "Invalid target".into(),
                            });
                            return (caster_msgs, broadcast_msgs);
                        }
                        // Check range
                        if let Some(enemy) = self.enemies.get(&tid) {
                            let dx = enemy.position[0] - caster.position[0];
                            let dz = enemy.position[2] - caster.position[2];
                            let dist = (dx * dx + dz * dz).sqrt();
                            if dist > ability.range {
                                caster_msgs.push(ServerMessage::AbilityFailed {
                                    ability_id,
                                    reason: "Out of range".into(),
                                });
                                return (caster_msgs, broadcast_msgs);
                            }
                        }
                        Some(tid)
                    }
                    None => {
                        caster_msgs.push(ServerMessage::AbilityFailed {
                            ability_id,
                            reason: "No target".into(),
                        });
                        return (caster_msgs, broadcast_msgs);
                    }
                }
            }
            TargetType::Ally => {
                // For now, ally abilities only work on self
                Some(caster_id)
            }
            TargetType::None | TargetType::AreaAroundSelf | TargetType::AreaAroundTarget => None,
        };
        
        // All checks passed - consume mana and start cooldown
        let caster = self.players.get_mut(&caster_id).unwrap();
        caster.consume_mana(ability.mana_cost);
        caster.start_ability_cooldown(ability_id, ability.cooldown);
        
        // Send cooldown message
        caster_msgs.push(ServerMessage::AbilityCooldown {
            ability_id,
            remaining: ability.cooldown,
            total: ability.cooldown,
        });
        
        // Broadcast ability used
        broadcast_msgs.push(ServerMessage::AbilityUsed {
            caster_id,
            ability_id,
            target_id: validated_target,
        });
        
        // Apply effects
        for effect in &ability.effects {
            match effect {
                AbilityEffect::Damage { base, attack_scaling } => {
                    if let Some(tid) = validated_target {
                        if let Some(enemy) = self.enemies.get_mut(&tid) {
                            let caster = self.players.get(&caster_id).unwrap();
                            let damage = caster.calculate_ability_damage(*base, *attack_scaling, &self.items);
                            
                            enemy.health = enemy.health.saturating_sub(damage);
                            enemy.target_id = Some(caster_id); // Aggro
                            
                            broadcast_msgs.push(ServerMessage::DamageEvent {
                                attacker_id: caster_id,
                                target_id: tid,
                                damage,
                                target_new_health: enemy.health,
                                is_critical: false,
                            });
                        }
                    }
                }
                AbilityEffect::Heal { base, health_scaling } => {
                    let target = validated_target.unwrap_or(caster_id);
                    if let Some(player) = self.players.get_mut(&target) {
                        let heal_amount = player.calculate_heal_amount(*base, *health_scaling);
                        let old_health = player.health;
                        player.health = (player.health + heal_amount).min(player.max_health);
                        let actual_heal = player.health - old_health;
                        
                        if actual_heal > 0 {
                            broadcast_msgs.push(ServerMessage::HealEvent {
                                healer_id: caster_id,
                                target_id: target,
                                amount: actual_heal,
                                target_new_health: player.health,
                            });
                        }
                    }
                }
                AbilityEffect::DamageOverTime { damage_per_tick, interval, duration } => {
                    if let Some(tid) = validated_target {
                        if let Some(enemy) = self.enemies.get_mut(&tid) {
                            // For enemies, we'll track DOT separately
                            // For now, just apply first tick immediately
                            enemy.health = enemy.health.saturating_sub(*damage_per_tick);
                            broadcast_msgs.push(ServerMessage::DamageEvent {
                                attacker_id: caster_id,
                                target_id: tid,
                                damage: *damage_per_tick,
                                target_new_health: enemy.health,
                                is_critical: false,
                            });
                            // TODO: Track DOT on enemies properly
                        }
                    }
                }
                AbilityEffect::HealOverTime { heal_per_tick, interval, duration } => {
                    let target = validated_target.unwrap_or(caster_id);
                    if let Some(player) = self.players.get_mut(&target) {
                        // Calculate heal per tick (if 0, use 2% of max health)
                        let tick_heal = if *heal_per_tick == 0 {
                            (player.max_health as f32 * 0.02) as u32
                        } else {
                            *heal_per_tick
                        };
                        
                        let buff_id = player.add_buff(
                            ability_id,
                            BuffEffect::HealOverTime {
                                heal_per_tick: tick_heal,
                                interval: *interval,
                                next_tick: *interval,
                            },
                            *duration,
                            false,
                        );
                        
                        broadcast_msgs.push(ServerMessage::BuffApplied {
                            target_id: target,
                            buff_id,
                            ability_id,
                            duration: *duration,
                            is_debuff: false,
                        });
                    }
                }
                AbilityEffect::BuffAttack { amount, duration } => {
                    let target = validated_target.unwrap_or(caster_id);
                    if let Some(player) = self.players.get_mut(&target) {
                        let buff_id = player.add_buff(
                            ability_id,
                            BuffEffect::AttackBonus(*amount),
                            *duration,
                            false,
                        );
                        
                        broadcast_msgs.push(ServerMessage::BuffApplied {
                            target_id: target,
                            buff_id,
                            ability_id,
                            duration: *duration,
                            is_debuff: false,
                        });
                    }
                }
                AbilityEffect::BuffDefense { amount, duration } => {
                    let target = validated_target.unwrap_or(caster_id);
                    if let Some(player) = self.players.get_mut(&target) {
                        let buff_id = player.add_buff(
                            ability_id,
                            BuffEffect::DefenseBonus(*amount),
                            *duration,
                            false,
                        );
                        
                        broadcast_msgs.push(ServerMessage::BuffApplied {
                            target_id: target,
                            buff_id,
                            ability_id,
                            duration: *duration,
                            is_debuff: false,
                        });
                    }
                }
                AbilityEffect::BuffAttackSpeed { multiplier, duration } => {
                    let target = validated_target.unwrap_or(caster_id);
                    if let Some(player) = self.players.get_mut(&target) {
                        let buff_id = player.add_buff(
                            ability_id,
                            BuffEffect::AttackSpeedMultiplier(*multiplier),
                            *duration,
                            false,
                        );
                        
                        broadcast_msgs.push(ServerMessage::BuffApplied {
                            target_id: target,
                            buff_id,
                            ability_id,
                            duration: *duration,
                            is_debuff: false,
                        });
                    }
                }
                AbilityEffect::DebuffAttack { amount, duration } => {
                    // Debuffs go on enemies (for now, track separately)
                    // TODO: Implement enemy debuff tracking
                }
                AbilityEffect::DebuffDefense { amount, duration } => {
                    // TODO: Implement enemy debuff tracking
                }
                AbilityEffect::Slow { multiplier, duration } => {
                    // TODO: Implement enemy slow
                }
                AbilityEffect::Stun { duration } => {
                    // TODO: Implement enemy stun
                }
            }
        }
        
        (caster_msgs, broadcast_msgs)
    }
    
    /// Update player cooldowns and buffs
    /// Returns messages to send to individual players (player_id, messages)
    pub fn update_player_abilities(&mut self, delta: f32) -> Vec<(u64, Vec<ServerMessage>)> {
        let mut player_messages = Vec::new();
        
        // Collect player IDs first to avoid borrow issues
        let player_ids: Vec<u64> = self.players.keys().copied().collect();
        
        for player_id in player_ids {
            let mut messages = Vec::new();
            
            if let Some(player) = self.players.get_mut(&player_id) {
                // Update cooldowns
                player.update_cooldowns(delta);
                
                // Update buffs and get events
                let (expired_buffs, dot_damage, hot_heal) = player.update_buffs(delta);
                
                // Send buff removed messages
                for buff_id in expired_buffs {
                    messages.push(ServerMessage::BuffRemoved {
                        target_id: player_id,
                        buff_id,
                    });
                }
                
                // DOT damage is handled separately (on enemies)
                // HOT heal already applied in update_buffs
                
                // Send heal event for HOT if any
                if hot_heal > 0 {
                    messages.push(ServerMessage::HealEvent {
                        healer_id: player_id,
                        target_id: player_id,
                        amount: hot_heal,
                        target_new_health: player.health,
                    });
                }
            }
            
            if !messages.is_empty() {
                player_messages.push((player_id, messages));
            }
        }
        
        player_messages
    }
    
    /// Get a player's action bar
    pub fn get_player_action_bar(&self, player_id: u64) -> Option<[Option<u32>; 8]> {
        self.players.get(&player_id).map(|p| p.action_bar)
    }
}
