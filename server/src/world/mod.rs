//! Game world management.

mod zone_manager;

pub use zone_manager::{ZoneManager, ZoneDefinition, ZoneSpawnPoint, ZoneEnemySpawn};

use std::collections::HashMap;
use log::{info, debug};
use rand::Rng;

use mmo_shared::{
    ServerMessage, AnimationState, EnemyType, InventorySlot, ItemDef,
    CharacterClass, Gender, Empire,
};

use crate::persistence::InventorySlotData;

use crate::entities::{ServerPlayer, ServerEnemy, WorldItem};

/// The game world containing all entities
pub struct GameWorld {
    players: HashMap<u64, ServerPlayer>,
    enemies: HashMap<u64, ServerEnemy>,
    world_items: HashMap<u64, WorldItem>,
    next_enemy_id: u64,
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
            world_items: HashMap::new(),
            next_enemy_id: 10000, // Start enemy IDs high to avoid confusion with player IDs
            next_item_id: 20000,
            items,
            zone_manager,
        };
        
        // Spawn enemies for all zones
        world.spawn_all_zone_enemies();
        
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
    
    /// Spawn a new enemy in a zone
    pub fn spawn_enemy(&mut self, zone_id: u32, position: [f32; 3], enemy_type: EnemyType) -> u64 {
        let id = self.next_enemy_id;
        self.next_enemy_id += 1;
        
        let enemy = ServerEnemy::new(id, zone_id, enemy_type, position);
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
        
        let player = ServerPlayer::with_state(
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
    
    /// Equip an item from inventory
    /// Returns Ok(new_weapon_id) on success, Err(reason) on failure
    pub fn equip_item(&mut self, player_id: u64, inventory_slot: u8) -> Result<Option<u32>, &'static str> {
        let player = self.players.get_mut(&player_id).ok_or("Player not found")?;
        player.try_equip_weapon(inventory_slot, &self.items)?;
        Ok(player.equipped_weapon_id)
    }
    
    /// Unequip weapon
    /// Returns the previously equipped weapon ID
    pub fn unequip_weapon(&mut self, player_id: u64) -> Option<u32> {
        let player = self.players.get_mut(&player_id)?;
        player.unequip_weapon()
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
        
        for enemy in self.enemies.values_mut() {
            // Get players in the same zone as this enemy
            let player_positions = zone_player_positions
                .get(&enemy.zone_id)
                .map(|v| v.as_slice())
                .unwrap_or(&[]);
            
            if let Some((target_player_id, damage)) = enemy.update(delta, player_positions) {
                attacks.push((enemy.id, target_player_id, damage));
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
    
    /// Process enemy deaths and spawn loot
    /// Returns messages to broadcast (despawns, spawns, item spawns)
    fn process_enemy_deaths(&mut self) -> Vec<ServerMessage> {
        let mut messages = Vec::new();
        
        let dead_enemies: Vec<u64> = self.enemies
            .iter()
            .filter(|(_, e)| e.health == 0)
            .map(|(id, _)| *id)
            .collect();
        
        let mut rng = rand::thread_rng();
        
        for enemy_id in dead_enemies {
            if let Some(enemy) = self.enemies.remove(&enemy_id) {
                info!("Enemy {} died", enemy_id);
                
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
}
