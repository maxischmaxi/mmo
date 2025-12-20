//! Server-side enemy entity with basic AI.

use log::{debug, trace};
use mmo_shared::{AnimationState, EnemyType};
use crate::navigation::{
    Obstacle, Vec2, NavigationState, navigate_toward, ENEMY_RADIUS,
};

/// Enemy aggro range - how far an enemy will detect a player
const AGGRO_RANGE: f32 = 10.0;

/// Enemy attack range - how close the enemy needs to be to attack
const ATTACK_RANGE: f32 = 2.0;

/// Enemy attack cooldown in seconds
const ATTACK_COOLDOWN: f32 = 2.0;

/// Enemy movement speed
const ENEMY_SPEED: f32 = 3.0;

/// Enemy return speed (faster when evading back to spawn)
const ENEMY_RETURN_SPEED: f32 = 5.0;

/// Default leash range - how far from spawn before enemy gives up chase
const DEFAULT_LEASH_RANGE: f32 = 25.0;

/// How close to spawn point before enemy is considered "home"
const HOME_THRESHOLD: f32 = 2.0;

/// Health regeneration rate when evading (per second, as fraction of max health)
const EVADE_REGEN_RATE: f32 = 0.2;

/// Server-side enemy state
#[derive(Debug)]
pub struct ServerEnemy {
    pub id: u64,
    /// Zone this enemy belongs to
    pub zone_id: u32,
    pub enemy_type: EnemyType,
    pub position: [f32; 3],
    pub spawn_position: [f32; 3],
    pub rotation: f32,
    pub health: u32,
    pub max_health: u32,
    pub level: u8,
    pub attack_power: u32,
    pub animation_state: AnimationState,
    pub target_id: Option<u64>,
    pub attack_cooldown: f32,
    pub leash_range: f32,
    /// Navigation state for pathfinding
    pub nav_state: NavigationState,
    /// Whether the enemy is evading (returning to spawn after leash)
    pub is_evading: bool,
}

impl ServerEnemy {
    pub fn new(id: u64, zone_id: u32, enemy_type: EnemyType, position: [f32; 3]) -> Self {
        // Stats and level range based on enemy type
        let (health, attack_power, min_level, max_level) = match enemy_type {
            EnemyType::Goblin => (50, 8, 1, 3),       // Weakest enemy
            EnemyType::Wolf => (65, 10, 2, 4),        // Pack predator, early-mid enemy
            EnemyType::Skeleton => (80, 14, 3, 5),    // Undead warrior
            EnemyType::Mutant => (150, 25, 5, 8),     // Elite enemy, very dangerous
        };
        
        // Random level within range
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let level = rng.gen_range(min_level..=max_level);
        
        // Scale health and attack power by level
        let level_multiplier = 1.0 + (level as f32 - 1.0) * 0.15;
        let scaled_health = (health as f32 * level_multiplier) as u32;
        let scaled_attack = (attack_power as f32 * level_multiplier) as u32;
        
        Self {
            id,
            zone_id,
            enemy_type,
            position,
            spawn_position: position,
            rotation: 0.0,
            health: scaled_health,
            max_health: scaled_health,
            level,
            attack_power: scaled_attack,
            animation_state: AnimationState::Idle,
            target_id: None,
            attack_cooldown: 0.0,
            leash_range: DEFAULT_LEASH_RANGE,
            nav_state: NavigationState::new(),
            is_evading: false,
        }
    }
    
    /// Get the collision radius for this enemy type
    fn get_radius(&self) -> f32 {
        match self.enemy_type {
            EnemyType::Mutant => ENEMY_RADIUS * 1.5, // Larger enemy
            _ => ENEMY_RADIUS,
        }
    }
    
    /// Update enemy AI with obstacle awareness
    /// Returns Some((target_player_id, damage)) if enemy attacks this frame
    pub fn update(
        &mut self,
        delta: f32,
        player_positions: &[(u64, [f32; 3])],
        obstacles: &[Obstacle],
    ) -> Option<(u64, u32)> {
        // Log occasionally when we have a target
        static UPDATE_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let count = UPDATE_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        
        // Update attack cooldown
        if self.attack_cooldown > 0.0 {
            self.attack_cooldown -= delta;
        }
        
        // If dead, do nothing
        if self.health == 0 {
            self.animation_state = AnimationState::Dead;
            return None;
        }
        
        let dist_from_spawn = self.distance_to(self.spawn_position);
        
        // Handle evading state (returning to spawn)
        if self.is_evading {
            // Regenerate health while evading
            let regen_amount = (self.max_health as f32 * EVADE_REGEN_RATE * delta) as u32;
            self.health = (self.health + regen_amount).min(self.max_health);
            
            // Check if we're home
            if dist_from_spawn < HOME_THRESHOLD {
                self.is_evading = false;
                self.health = self.max_health; // Full heal when reaching spawn
                self.animation_state = AnimationState::Idle;
                self.nav_state.clear_path();
                debug!("[ENEMY {}] Returned home, health restored to {}", self.id, self.health);
                return None;
            }
            
            // Move back to spawn faster
            self.move_towards_with_speed(self.spawn_position, delta, obstacles, ENEMY_RETURN_SPEED);
            self.animation_state = AnimationState::Walking;
            return None;
        }
        
        // Check leash - if too far from spawn, start evading
        if dist_from_spawn > self.leash_range {
            self.is_evading = true;
            self.target_id = None;
            self.nav_state.clear_path();
            debug!("[ENEMY {}] Leash triggered at dist={:.1}, returning to spawn", self.id, dist_from_spawn);
            return None;
        }
        
        // Find closest player in aggro range
        let mut closest_player: Option<(u64, f32)> = None;
        for (player_id, player_pos) in player_positions {
            let dist = self.distance_to(*player_pos);
            if dist <= AGGRO_RANGE {
                if closest_player.is_none() || dist < closest_player.unwrap().1 {
                    closest_player = Some((*player_id, dist));
                }
            }
        }
        
        // Update target based on aggro
        if let Some((player_id, dist)) = closest_player {
            let was_already_targeting = self.target_id == Some(player_id);
            self.target_id = Some(player_id);
            
            // Get target position
            if let Some((_, target_pos)) = player_positions.iter().find(|(id, _)| *id == player_id) {
                // Log when we start chasing a new target
                if !was_already_targeting {
                    debug!("[ENEMY {}] Started chasing player {} at ({:.2}, {:.2}), my pos=({:.2}, {:.2}), {} obstacles",
                        self.id, player_id, target_pos[0], target_pos[2], 
                        self.position[0], self.position[2], obstacles.len());
                }
                
                // Log chase status every ~2 seconds (40 ticks at 20 tick/s)
                if count % 40 == 0 && dist > ATTACK_RANGE {
                    debug!("[ENEMY {}] Chasing player {} dist={:.2}, spawn_dist={:.2}, my_pos=({:.2}, {:.2})",
                        self.id, player_id, dist, dist_from_spawn, self.position[0], self.position[2]);
                }
                
                // Always face the target when we have one
                self.face_towards(*target_pos);
                
                if dist <= ATTACK_RANGE {
                    // In attack range - try to attack
                    self.animation_state = AnimationState::Attacking;
                    // Clear path when attacking (we've reached the target)
                    self.nav_state.clear_path();
                    
                    // Attack if cooldown is ready
                    if self.attack_cooldown <= 0.0 {
                        self.attack_cooldown = ATTACK_COOLDOWN;
                        // Return attack event with damage
                        return Some((player_id, self.attack_power));
                    }
                } else {
                    // Chase player with obstacle avoidance
                    self.move_towards_with_avoidance(*target_pos, delta, obstacles);
                    self.animation_state = AnimationState::Walking;
                }
            }
        } else {
            // No target - idle or patrol
            self.target_id = None;
            self.animation_state = AnimationState::Idle;
            
            // Simple patrol: return towards spawn if far
            if dist_from_spawn > 5.0 {
                self.move_towards_with_avoidance(self.spawn_position, delta, obstacles);
                self.animation_state = AnimationState::Walking;
            } else {
                // Clear path when idle near spawn
                self.nav_state.clear_path();
            }
        }
        
        None
    }
    
    /// Move towards a target position with obstacle avoidance
    fn move_towards_with_avoidance(&mut self, target: [f32; 3], delta: f32, obstacles: &[Obstacle]) {
        self.move_towards_with_speed(target, delta, obstacles, ENEMY_SPEED);
    }
    
    /// Move towards a target position with obstacle avoidance at a custom speed
    fn move_towards_with_speed(&mut self, target: [f32; 3], delta: f32, obstacles: &[Obstacle], speed: f32) {
        let current_pos = Vec2::from_3d(self.position);
        let target_pos = Vec2::new(target[0], target[2]);
        let enemy_radius = self.get_radius();
        
        let old_pos = self.position;
        
        let nav_result = navigate_toward(
            current_pos,
            target_pos,
            obstacles,
            &mut self.nav_state,
            speed,
            delta,
            enemy_radius,
        );
        
        // Update position from navigation result
        self.position[0] = nav_result.new_position.x;
        self.position[2] = nav_result.new_position.z;
        self.rotation = nav_result.rotation;
        
        // Log movement
        let move_dist = ((self.position[0] - old_pos[0]).powi(2) + (self.position[2] - old_pos[2]).powi(2)).sqrt();
        if move_dist > 0.001 {
            trace!("[ENEMY {}] Moved from ({:.2}, {:.2}) to ({:.2}, {:.2}) dist={:.3} target=({:.2}, {:.2})",
                self.id, old_pos[0], old_pos[2], self.position[0], self.position[2], 
                move_dist, target[0], target[2]);
        }
        
        if nav_result.is_stuck {
            debug!("[ENEMY {}] Navigation reports STUCK at ({:.2}, {:.2})", 
                self.id, self.position[0], self.position[2]);
        }
    }
    
    /// Simple move towards without avoidance (legacy, for cases without obstacles)
    #[allow(dead_code)]
    fn move_towards_simple(&mut self, target: [f32; 3], delta: f32) {
        let dx = target[0] - self.position[0];
        let dz = target[2] - self.position[2];
        let dist = (dx * dx + dz * dz).sqrt();
        
        if dist > 0.1 {
            let move_dist = ENEMY_SPEED * delta;
            let ratio = (move_dist / dist).min(1.0);
            
            self.position[0] += dx * ratio;
            self.position[2] += dz * ratio;
            
            // Update rotation to face movement direction
            // atan2(x, z) gives the angle where 0 = facing +Z, matching Godot's convention
            self.rotation = dx.atan2(dz);
        }
    }
    
    /// Calculate distance to a position
    fn distance_to(&self, target: [f32; 3]) -> f32 {
        let dx = target[0] - self.position[0];
        let dz = target[2] - self.position[2];
        (dx * dx + dz * dz).sqrt()
    }
    
    /// Update rotation to face a target position
    fn face_towards(&mut self, target: [f32; 3]) {
        let dx = target[0] - self.position[0];
        let dz = target[2] - self.position[2];
        if dx.abs() > 0.01 || dz.abs() > 0.01 {
            // atan2(x, z) gives the angle where 0 = facing +Z, matching Godot's convention
            self.rotation = dx.atan2(dz);
        }
    }
    
    /// Take damage
    pub fn take_damage(&mut self, damage: u32) {
        self.health = self.health.saturating_sub(damage);
        if self.health > 0 {
            self.animation_state = AnimationState::TakingDamage;
        } else {
            self.animation_state = AnimationState::Dying;
        }
    }
}
