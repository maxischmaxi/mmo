//! Server-side player entity.

use mmo_shared::{AnimationState, InventorySlot, ItemEffect, ItemDef, ItemType, CharacterClass, Gender, Empire, get_item_definitions, AbilityEffect};
use std::collections::HashMap;

/// Maximum inventory slots
const INVENTORY_SIZE: usize = 20;

/// Active buff on a player
#[derive(Debug, Clone)]
pub struct ActiveBuff {
    /// Unique buff instance ID
    pub id: u32,
    /// Source ability ID
    pub ability_id: u32,
    /// Remaining duration in seconds
    pub remaining: f32,
    /// Total duration in seconds
    pub total_duration: f32,
    /// The effect being applied
    pub effect: BuffEffect,
    /// Is this a debuff (negative effect)?
    pub is_debuff: bool,
}

/// Types of buff effects
#[derive(Debug, Clone)]
pub enum BuffEffect {
    /// Flat attack bonus
    AttackBonus(i32),
    /// Flat defense bonus
    DefenseBonus(i32),
    /// Attack speed multiplier
    AttackSpeedMultiplier(f32),
    /// Movement speed multiplier
    SpeedMultiplier(f32),
    /// Heal over time (heal per tick, tick interval, time until next tick)
    HealOverTime { heal_per_tick: u32, interval: f32, next_tick: f32 },
    /// Damage over time (damage per tick, tick interval, time until next tick)
    DamageOverTime { damage_per_tick: u32, interval: f32, next_tick: f32 },
    /// Stunned (can't move or attack)
    Stunned,
}

/// Maximum level cap
pub const MAX_LEVEL: u32 = 99;

/// Server-side player state
#[derive(Debug)]
pub struct ServerPlayer {
    pub id: u64,
    pub name: String,
    pub class: CharacterClass,
    pub gender: Gender,
    pub empire: Empire,
    /// Current zone ID (1-99: Shinsoo, 100-199: Chunjo, 200-299: Jinno, 300+: Neutral)
    pub zone_id: u32,
    pub position: [f32; 3],
    pub rotation: f32,
    pub velocity: [f32; 3],
    pub health: u32,
    pub max_health: u32,
    pub mana: u32,
    pub max_mana: u32,
    pub attack_power: u32,
    pub defense: u32,
    pub animation_state: AnimationState,
    pub inventory: Vec<Option<InventorySlot>>,
    /// Currently equipped weapon item ID (None = unarmed)
    pub equipped_weapon_id: Option<u32>,
    /// Whether death has been announced (prevents duplicate EntityDeath messages)
    pub death_announced: bool,
    /// Player level
    pub level: u32,
    /// Player experience points
    pub experience: u32,
    /// Player gold
    pub gold: u64,
    /// Invincibility mode (god mode) - takes no damage
    pub is_invincible: bool,
    /// Ability cooldowns (ability_id -> remaining cooldown in seconds)
    pub ability_cooldowns: HashMap<u32, f32>,
    /// Active buffs/debuffs
    pub active_buffs: Vec<ActiveBuff>,
    /// Next buff ID counter
    pub next_buff_id: u32,
    /// Action bar (8 slots, each containing an optional ability ID)
    pub action_bar: [Option<u32>; 8],
}

impl ServerPlayer {
    /// Get base stats for a character class at level 1
    /// Returns (max_health, max_mana, attack, defense)
    pub fn base_stats_for_class(class: CharacterClass) -> (u32, u32, u32, u32) {
        match class {
            CharacterClass::Ninja => (80, 40, 12, 4),
            CharacterClass::Warrior => (120, 20, 10, 8),
            CharacterClass::Sura => (90, 60, 11, 5),
            CharacterClass::Shaman => (70, 80, 8, 4),
        }
    }
    
    /// Calculate stats for a given class and level
    /// Returns (max_health, max_mana, attack, defense)
    pub fn calculate_stats_for_level(class: CharacterClass, level: u32) -> (u32, u32, u32, u32) {
        let (base_hp, base_mp, base_atk, base_def) = Self::base_stats_for_class(class);
        let level_bonus = level.saturating_sub(1);
        
        (
            base_hp + level_bonus * 5,    // +5 HP per level
            base_mp + level_bonus * 3,    // +3 MP per level
            base_atk + level_bonus * 2,   // +2 ATK per level
            base_def + level_bonus * 1,   // +1 DEF per level
        )
    }
    
    /// Calculate XP required to reach a given level
    /// Formula: base_xp * level^2 (exponential curve)
    /// Level 2: 100 XP, Level 3: 400 XP, Level 10: 10000 XP, etc.
    pub fn experience_for_level(level: u32) -> u32 {
        if level <= 1 {
            return 0;
        }
        // XP required to reach this level from level 1
        100 * (level - 1) * (level - 1)
    }
    
    /// Calculate XP needed from current level to next level
    pub fn experience_to_next_level(level: u32) -> u32 {
        if level >= MAX_LEVEL {
            return 0; // Max level
        }
        Self::experience_for_level(level + 1) - Self::experience_for_level(level)
    }
    
    /// Get XP to next level for this player
    pub fn get_experience_to_next_level(&self) -> u32 {
        Self::experience_to_next_level(self.level)
    }
    
    /// Calculate XP reward for killing an enemy of a given level
    /// Base: enemy_level * 10
    /// Bonus/penalty based on level difference
    pub fn calculate_xp_for_enemy(player_level: u32, enemy_level: u8) -> u32 {
        let enemy_lvl = enemy_level as u32;
        let base_xp = enemy_lvl * 10;
        
        // Level difference modifier
        let level_diff = enemy_lvl as i32 - player_level as i32;
        let modifier = match level_diff {
            d if d >= 5 => 1.5,   // Much higher level enemy: 50% bonus
            d if d >= 2 => 1.2,   // Higher level enemy: 20% bonus
            d if d >= -1 => 1.0,  // Same level (+/- 1): normal XP
            d if d >= -4 => 0.8,  // Lower level enemy: 20% penalty
            _ => 0.5,             // Much lower level: 50% penalty
        };
        
        ((base_xp as f32) * modifier) as u32
    }
    
    /// Add experience and check for level up
    /// Returns Some(new_level) if player leveled up, None otherwise
    pub fn add_experience(&mut self, amount: u32) -> Option<u32> {
        if self.level >= MAX_LEVEL {
            return None; // Already max level
        }
        
        self.experience += amount;
        
        // Check for level up(s) - can level multiple times at once
        let mut leveled_up = false;
        while self.level < MAX_LEVEL {
            let xp_needed = Self::experience_for_level(self.level + 1);
            if self.experience >= xp_needed {
                self.level += 1;
                leveled_up = true;
                log::info!("Player {} leveled up to {}", self.name, self.level);
            } else {
                break;
            }
        }
        
        if leveled_up {
            self.recalculate_stats_for_level();
            Some(self.level)
        } else {
            None
        }
    }
    
    /// Set experience directly (for commands)
    /// Returns Some(new_level) if level changed, None otherwise
    pub fn set_experience(&mut self, experience: u32) -> Option<u32> {
        let old_level = self.level;
        self.experience = experience;
        
        // Recalculate level based on total XP
        let mut new_level = 1u32;
        while new_level < MAX_LEVEL && self.experience >= Self::experience_for_level(new_level + 1) {
            new_level += 1;
        }
        
        if new_level != old_level {
            self.level = new_level;
            self.recalculate_stats_for_level();
            Some(new_level)
        } else {
            None
        }
    }
    
    /// Recalculate stats based on current level, updating max values and healing to full
    pub fn recalculate_stats_for_level(&mut self) {
        let (max_health, max_mana, attack, defense) = Self::calculate_stats_for_level(self.class, self.level);
        self.max_health = max_health;
        self.max_mana = max_mana;
        self.attack_power = attack;
        self.defense = defense;
        // Heal to full when leveling
        self.health = max_health;
        self.mana = max_mana;
    }
    
    /// Create a player with saved state (for persistence)
    #[allow(clippy::too_many_arguments)]
    pub fn with_state(
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
        attack_power: u32,
        defense: u32,
        inventory: Vec<Option<InventorySlot>>,
        equipped_weapon_id: Option<u32>,
        level: u32,
        experience: u32,
        gold: u64,
    ) -> Self {
        Self {
            id,
            name,
            class,
            gender,
            empire,
            zone_id,
            position,
            rotation,
            velocity: [0.0, 0.0, 0.0],
            health,
            max_health,
            mana,
            max_mana,
            attack_power,
            defense,
            animation_state: AnimationState::Idle,
            inventory,
            equipped_weapon_id,
            death_announced: false,
            level,
            experience,
            gold,
            is_invincible: false,
            ability_cooldowns: HashMap::new(),
            active_buffs: Vec::new(),
            next_buff_id: 1,
            action_bar: mmo_shared::get_default_action_bar(class),
        }
    }
    
    /// Add item to inventory, stacking if possible
    pub fn add_to_inventory(&mut self, item_id: u32, quantity: u32) -> bool {
        let item_defs = get_item_definitions();
        let item_def = item_defs.iter().find(|i| i.id == item_id);
        let max_stack = item_def.map(|i| i.max_stack).unwrap_or(1);
        
        let mut remaining = quantity;
        
        // Try to stack with existing items
        for slot in &mut self.inventory {
            if remaining == 0 {
                break;
            }
            if let Some(inv_slot) = slot {
                if inv_slot.item_id == item_id && inv_slot.quantity < max_stack {
                    let can_add = (max_stack - inv_slot.quantity).min(remaining);
                    inv_slot.quantity += can_add;
                    remaining -= can_add;
                }
            }
        }
        
        // Add to empty slots
        for slot in &mut self.inventory {
            if remaining == 0 {
                break;
            }
            if slot.is_none() {
                let add_amount = remaining.min(max_stack);
                *slot = Some(InventorySlot {
                    item_id,
                    quantity: add_amount,
                });
                remaining -= add_amount;
            }
        }
        
        remaining == 0
    }
    
    /// Remove item from inventory slot
    pub fn remove_from_inventory(&mut self, slot: u8) -> Option<(u32, u32)> {
        let slot_idx = slot as usize;
        if slot_idx >= self.inventory.len() {
            return None;
        }
        
        let inv_slot = self.inventory[slot_idx].take()?;
        Some((inv_slot.item_id, inv_slot.quantity))
    }
    
    /// Use item from inventory
    pub fn use_item(&mut self, slot: u8) -> Option<()> {
        let slot_idx = slot as usize;
        if slot_idx >= self.inventory.len() {
            return None;
        }
        
        let inv_slot = self.inventory[slot_idx].as_mut()?;
        let item_defs = get_item_definitions();
        let item_def = item_defs.iter().find(|i| i.id == inv_slot.item_id)?;
        
        // Apply effects
        for effect in &item_def.effects {
            match effect {
                ItemEffect::RestoreHealth(amount) => {
                    self.health = (self.health + amount).min(self.max_health);
                }
                ItemEffect::RestoreMana(amount) => {
                    self.mana = (self.mana + amount).min(self.max_mana);
                }
                ItemEffect::IncreaseAttack(amount) => {
                    self.attack_power += amount;
                }
                ItemEffect::IncreaseDefense(amount) => {
                    self.defense += amount;
                }
                ItemEffect::IncreaseSpeed(_) => {
                    // TODO: Implement speed buff
                }
            }
        }
        
        // Consume item
        inv_slot.quantity -= 1;
        if inv_slot.quantity == 0 {
            self.inventory[slot_idx] = None;
        }
        
        Some(())
    }
    
    /// Get inventory slots for network update
    pub fn get_inventory_slots(&self) -> Vec<Option<InventorySlot>> {
        self.inventory.clone()
    }
    
    /// Take damage (returns 0 if invincible)
    pub fn take_damage(&mut self, damage: u32) -> u32 {
        if self.is_invincible {
            return 0;
        }
        let actual_damage = damage.saturating_sub(self.defense / 2);
        self.health = self.health.saturating_sub(actual_damage);
        actual_damage
    }
    
    /// Check if dead
    pub fn is_dead(&self) -> bool {
        self.health == 0
    }
    
    /// Get attack speed (base from class * weapon multiplier)
    /// Returns attacks per second multiplier (1.0 = normal, higher = faster)
    pub fn get_attack_speed(&self, items: &HashMap<u32, ItemDef>) -> f32 {
        // Base attack speed from class
        let base_speed = self.class.base_attack_speed();
        
        // Get weapon attack speed multiplier
        if let Some(weapon_id) = self.equipped_weapon_id {
            if let Some(item) = items.get(&weapon_id) {
                if let Some(stats) = &item.weapon_stats {
                    return base_speed * stats.attack_speed;
                }
            }
        }
        
        // Unarmed is slower
        base_speed * 0.8
    }
    
    /// Calculate attack damage based on equipped weapon
    /// Formula: weapon_damage + (base_attack / 2), or base_attack / 2 if unarmed
    pub fn calculate_attack_damage(&self, items: &HashMap<u32, ItemDef>) -> u32 {
        if let Some(weapon_id) = self.equipped_weapon_id {
            if let Some(item) = items.get(&weapon_id) {
                if let Some(stats) = &item.weapon_stats {
                    return stats.damage + (self.attack_power / 2);
                }
            }
        }
        
        // Unarmed: reduced damage
        self.attack_power / 2
    }
    
    /// Try to equip a weapon from inventory
    /// Returns Ok(old_weapon_id) if successful, Err with reason if failed
    /// The item is removed from inventory; if there was an old weapon, it goes into the vacated slot
    pub fn try_equip_weapon(&mut self, inventory_slot: u8, items: &HashMap<u32, ItemDef>) -> Result<Option<u32>, &'static str> {
        let slot_idx = inventory_slot as usize;
        if slot_idx >= self.inventory.len() {
            return Err("Invalid inventory slot");
        }
        
        let inv_slot = self.inventory[slot_idx].as_ref().ok_or("No item in slot")?;
        let item_id = inv_slot.item_id;
        
        let item = items.get(&item_id).ok_or("Item not found")?;
        
        // Check if it's a weapon
        if item.item_type != ItemType::Weapon {
            return Err("Item is not a weapon");
        }
        
        // Check class restriction
        if let Some(stats) = &item.weapon_stats {
            if let Some(required_class) = stats.class_restriction {
                if required_class != self.class {
                    return Err("Cannot equip: wrong class");
                }
            }
        }
        
        // Store the old weapon before we modify anything
        let old_weapon = self.equipped_weapon_id;
        
        // Remove item from inventory slot
        self.inventory[slot_idx] = None;
        
        // If we had a weapon equipped, put it in the now-empty inventory slot
        if let Some(old_weapon_id) = old_weapon {
            self.inventory[slot_idx] = Some(InventorySlot {
                item_id: old_weapon_id,
                quantity: 1,
            });
        }
        
        // Equip the new weapon
        self.equipped_weapon_id = Some(item_id);
        
        Ok(old_weapon)
    }
    
    /// Unequip weapon and put it back in inventory
    /// Returns the previously equipped weapon ID, or None if no weapon was equipped or no space
    pub fn unequip_weapon(&mut self) -> Option<u32> {
        let weapon_id = self.equipped_weapon_id.take()?;
        
        // Find an empty inventory slot
        let empty_slot = self.inventory.iter().position(|s| s.is_none());
        
        if let Some(slot_idx) = empty_slot {
            self.inventory[slot_idx] = Some(InventorySlot {
                item_id: weapon_id,
                quantity: 1,
            });
            Some(weapon_id)
        } else {
            // No space in inventory, re-equip the weapon
            self.equipped_weapon_id = Some(weapon_id);
            None
        }
    }
    
    // ==========================================================================
    // Ability System
    // ==========================================================================
    
    /// Check if an ability is on cooldown
    pub fn is_ability_on_cooldown(&self, ability_id: u32) -> bool {
        self.ability_cooldowns.get(&ability_id).map_or(false, |&cd| cd > 0.0)
    }
    
    /// Get remaining cooldown for an ability
    pub fn get_ability_cooldown(&self, ability_id: u32) -> f32 {
        *self.ability_cooldowns.get(&ability_id).unwrap_or(&0.0)
    }
    
    /// Start cooldown for an ability
    pub fn start_ability_cooldown(&mut self, ability_id: u32, duration: f32) {
        self.ability_cooldowns.insert(ability_id, duration);
    }
    
    /// Update all cooldowns (call every tick with delta time)
    pub fn update_cooldowns(&mut self, delta: f32) {
        self.ability_cooldowns.retain(|_, cd| {
            *cd -= delta;
            *cd > 0.0
        });
    }
    
    /// Consume mana (returns true if successful)
    pub fn consume_mana(&mut self, amount: u32) -> bool {
        if self.mana >= amount {
            self.mana -= amount;
            true
        } else {
            false
        }
    }
    
    /// Add a buff to the player
    pub fn add_buff(&mut self, ability_id: u32, effect: BuffEffect, duration: f32, is_debuff: bool) -> u32 {
        let buff_id = self.next_buff_id;
        self.next_buff_id += 1;
        
        self.active_buffs.push(ActiveBuff {
            id: buff_id,
            ability_id,
            remaining: duration,
            total_duration: duration,
            effect,
            is_debuff,
        });
        
        buff_id
    }
    
    /// Remove a buff by ID
    pub fn remove_buff(&mut self, buff_id: u32) -> bool {
        if let Some(pos) = self.active_buffs.iter().position(|b| b.id == buff_id) {
            self.active_buffs.remove(pos);
            true
        } else {
            false
        }
    }
    
    /// Update buffs and return events (expired buff IDs, DOT damage, HOT heals)
    /// Returns (expired_buff_ids, dot_damage, hot_heal)
    pub fn update_buffs(&mut self, delta: f32) -> (Vec<u32>, u32, u32) {
        let mut expired = Vec::new();
        let mut total_dot_damage = 0u32;
        let mut total_hot_heal = 0u32;
        
        for buff in &mut self.active_buffs {
            buff.remaining -= delta;
            
            // Handle tick-based effects
            match &mut buff.effect {
                BuffEffect::DamageOverTime { damage_per_tick, interval, next_tick } => {
                    *next_tick -= delta;
                    while *next_tick <= 0.0 && buff.remaining > 0.0 {
                        total_dot_damage += *damage_per_tick;
                        *next_tick += *interval;
                    }
                }
                BuffEffect::HealOverTime { heal_per_tick, interval, next_tick } => {
                    *next_tick -= delta;
                    while *next_tick <= 0.0 && buff.remaining > 0.0 {
                        total_hot_heal += *heal_per_tick;
                        *next_tick += *interval;
                    }
                }
                _ => {}
            }
            
            if buff.remaining <= 0.0 {
                expired.push(buff.id);
            }
        }
        
        // Remove expired buffs
        self.active_buffs.retain(|b| b.remaining > 0.0);
        
        // Apply HOT healing
        if total_hot_heal > 0 {
            self.health = (self.health + total_hot_heal).min(self.max_health);
        }
        
        (expired, total_dot_damage, total_hot_heal)
    }
    
    /// Get total attack bonus from buffs
    pub fn get_buff_attack_bonus(&self) -> i32 {
        self.active_buffs.iter().filter_map(|b| {
            match &b.effect {
                BuffEffect::AttackBonus(amount) => Some(*amount),
                _ => None,
            }
        }).sum()
    }
    
    /// Get total defense bonus from buffs
    pub fn get_buff_defense_bonus(&self) -> i32 {
        self.active_buffs.iter().filter_map(|b| {
            match &b.effect {
                BuffEffect::DefenseBonus(amount) => Some(*amount),
                _ => None,
            }
        }).sum()
    }
    
    /// Get attack speed multiplier from buffs
    pub fn get_buff_attack_speed_multiplier(&self) -> f32 {
        self.active_buffs.iter().filter_map(|b| {
            match &b.effect {
                BuffEffect::AttackSpeedMultiplier(mult) => Some(*mult),
                _ => None,
            }
        }).product::<f32>().max(1.0) // Default to 1.0 if no buffs
    }
    
    /// Check if player is stunned
    pub fn is_stunned(&self) -> bool {
        self.active_buffs.iter().any(|b| matches!(b.effect, BuffEffect::Stunned))
    }
    
    /// Calculate ability damage based on effect and player stats
    pub fn calculate_ability_damage(&self, base: u32, attack_scaling: f32, items: &HashMap<u32, ItemDef>) -> u32 {
        let weapon_damage = self.calculate_attack_damage(items);
        let attack_bonus = self.get_buff_attack_bonus();
        let total_attack = (self.attack_power as i32 + attack_bonus).max(0) as u32;
        
        base + ((weapon_damage as f32 + total_attack as f32 / 2.0) * attack_scaling) as u32
    }
    
    /// Calculate heal amount based on effect
    pub fn calculate_heal_amount(&self, base: u32, health_scaling: f32) -> u32 {
        base + (self.max_health as f32 * health_scaling) as u32
    }
}
