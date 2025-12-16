//! Server-side enemy entity with basic AI.

use mmo_shared::{AnimationState, EnemyType};

/// Enemy aggro range
const AGGRO_RANGE: f32 = 10.0;

/// Enemy attack range
const ATTACK_RANGE: f32 = 2.0;

/// Enemy attack cooldown in seconds
const ATTACK_COOLDOWN: f32 = 2.0;

/// Enemy movement speed
const ENEMY_SPEED: f32 = 3.0;

/// Server-side enemy state
#[derive(Debug)]
pub struct ServerEnemy {
    pub id: u64,
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
}

impl ServerEnemy {
    pub fn new(id: u64, enemy_type: EnemyType, position: [f32; 3]) -> Self {
        // Stats and level range based on enemy type
        let (health, attack_power, min_level, max_level) = match enemy_type {
            EnemyType::Goblin => (50, 8, 1, 3),
            EnemyType::Skeleton => (70, 12, 3, 5),
            EnemyType::Wolf => (40, 10, 2, 4),
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
            leash_range: 30.0, // Return to spawn if too far
        }
    }
    
    /// Update enemy AI
    /// Returns Some((target_player_id, damage)) if enemy attacks this frame
    pub fn update(&mut self, delta: f32, player_positions: &[(u64, [f32; 3])]) -> Option<(u64, u32)> {
        // Update attack cooldown
        if self.attack_cooldown > 0.0 {
            self.attack_cooldown -= delta;
        }
        
        // If dead, do nothing
        if self.health == 0 {
            self.animation_state = AnimationState::Dead;
            return None;
        }
        
        // Check leash (return to spawn if too far)
        let dist_from_spawn = self.distance_to(self.spawn_position);
        if dist_from_spawn > self.leash_range {
            self.target_id = None;
            self.move_towards(self.spawn_position, delta);
            self.animation_state = AnimationState::Walking;
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
            self.target_id = Some(player_id);
            
            // Get target position
            if let Some((_, target_pos)) = player_positions.iter().find(|(id, _)| *id == player_id) {
                if dist <= ATTACK_RANGE {
                    // In attack range - try to attack
                    self.animation_state = AnimationState::Attacking;
                    
                    // Attack if cooldown is ready
                    if self.attack_cooldown <= 0.0 {
                        self.attack_cooldown = ATTACK_COOLDOWN;
                        // Return attack event with damage
                        return Some((player_id, self.attack_power));
                    }
                } else {
                    // Chase player
                    self.move_towards(*target_pos, delta);
                    self.animation_state = AnimationState::Walking;
                }
            }
        } else {
            // No target - idle or patrol
            self.target_id = None;
            self.animation_state = AnimationState::Idle;
            
            // Simple patrol: return towards spawn if far
            if dist_from_spawn > 5.0 {
                self.move_towards(self.spawn_position, delta);
                self.animation_state = AnimationState::Walking;
            }
        }
        
        None
    }
    
    /// Move towards a target position
    fn move_towards(&mut self, target: [f32; 3], delta: f32) {
        let dx = target[0] - self.position[0];
        let dz = target[2] - self.position[2];
        let dist = (dx * dx + dz * dz).sqrt();
        
        if dist > 0.1 {
            let move_dist = ENEMY_SPEED * delta;
            let ratio = (move_dist / dist).min(1.0);
            
            self.position[0] += dx * ratio;
            self.position[2] += dz * ratio;
            
            // Update rotation to face movement direction
            self.rotation = dz.atan2(dx);
        }
    }
    
    /// Calculate distance to a position
    fn distance_to(&self, target: [f32; 3]) -> f32 {
        let dx = target[0] - self.position[0];
        let dz = target[2] - self.position[2];
        (dx * dx + dz * dz).sqrt()
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
