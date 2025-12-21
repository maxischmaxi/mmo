//! Server-side player entity.

use mmo_shared::{AnimationState, InventorySlot, ItemEffect, ItemDef, ItemType, CharacterClass, Gender, Empire, get_item_definitions, get_item_slot_size, AbilityEffect, ArmorStats};
use std::collections::HashMap;

/// Maximum inventory slots
const INVENTORY_SIZE: usize = 20;

/// Number of columns in inventory grid (for multi-slot item row boundary checks)
const INVENTORY_COLUMNS: usize = 5;

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
    /// Currently equipped armor item ID (None = no armor)
    pub equipped_armor_id: Option<u32>,
    /// Currently equipped helmet item ID (None = no helmet)
    pub equipped_helmet_id: Option<u32>,
    /// Currently equipped shield item ID (None = no shield)
    pub equipped_shield_id: Option<u32>,
    /// Currently equipped boots item ID (None = no boots)
    pub equipped_boots_id: Option<u32>,
    /// Currently equipped necklace item ID (None = no necklace)
    pub equipped_necklace_id: Option<u32>,
    /// Currently equipped ring item ID (None = no ring)
    pub equipped_ring_id: Option<u32>,
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
            equipped_armor_id: None,
            equipped_helmet_id: None,
            equipped_shield_id: None,
            equipped_boots_id: None,
            equipped_necklace_id: None,
            equipped_ring_id: None,
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
    
    /// Create a player with saved state including all equipment (for persistence)
    #[allow(clippy::too_many_arguments)]
    pub fn with_full_equipment(
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
        equipped_armor_id: Option<u32>,
        equipped_helmet_id: Option<u32>,
        equipped_shield_id: Option<u32>,
        equipped_boots_id: Option<u32>,
        equipped_necklace_id: Option<u32>,
        equipped_ring_id: Option<u32>,
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
            equipped_armor_id,
            equipped_helmet_id,
            equipped_shield_id,
            equipped_boots_id,
            equipped_necklace_id,
            equipped_ring_id,
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
    
    /// Create a player with saved state including armor (for persistence) - legacy compatibility
    #[allow(clippy::too_many_arguments)]
    pub fn with_state_and_armor(
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
        equipped_armor_id: Option<u32>,
        level: u32,
        experience: u32,
        gold: u64,
    ) -> Self {
        Self::with_full_equipment(
            id, name, class, gender, empire, zone_id, position, rotation,
            health, max_health, mana, max_mana, attack_power, defense,
            inventory, equipped_weapon_id, equipped_armor_id,
            None, None, None, None, None,  // New slots empty
            level, experience, gold,
        )
    }
    
    /// Check if a multi-slot item can be placed at the given slot index
    /// Multi-slot items expand VERTICALLY (down columns, like Metin2)
    /// Validates: slot is empty, all continuation slots below are empty, doesn't exceed grid
    fn can_place_item_at(&self, start_slot: usize, slot_size: u8) -> bool {
        let size = slot_size as usize;
        let num_rows = INVENTORY_SIZE / INVENTORY_COLUMNS;
        
        // Check which row/column we're in
        let start_row = start_slot / INVENTORY_COLUMNS;
        let start_col = start_slot % INVENTORY_COLUMNS;
        
        // Check if item fits vertically (doesn't go past last row)
        if start_row + size > num_rows {
            return false;
        }
        
        // Check all required slots are empty (going down vertically)
        for i in 0..size {
            let slot_idx = start_slot + (i * INVENTORY_COLUMNS);
            if slot_idx >= INVENTORY_SIZE {
                return false;
            }
            if self.inventory[slot_idx].is_some() {
                return false;
            }
        }
        
        true
    }
    
    /// Find contiguous empty slots for a multi-slot item (vertical placement)
    fn find_contiguous_slots(&self, slot_size: u8) -> Option<usize> {
        for start_slot in 0..INVENTORY_SIZE {
            if self.can_place_item_at(start_slot, slot_size) {
                return Some(start_slot);
            }
        }
        None
    }
    
    /// Place a multi-slot item starting at the given slot (vertical expansion)
    fn place_item_at(&mut self, start_slot: usize, item_id: u32, quantity: u32, slot_size: u8) {
        // Primary slot
        self.inventory[start_slot] = Some(InventorySlot {
            item_id,
            quantity,
            continuation_of: None,
        });
        
        // Continuation slots (going down vertically)
        for i in 1..slot_size as usize {
            let slot_idx = start_slot + (i * INVENTORY_COLUMNS);
            if slot_idx < INVENTORY_SIZE {
                self.inventory[slot_idx] = Some(InventorySlot {
                    item_id: 0,  // No item in continuation slots
                    quantity: 0,
                    continuation_of: Some(start_slot as u8),
                });
            }
        }
    }
    
    /// Clear a multi-slot item and all its continuation slots (vertical)
    fn clear_item_slots(&mut self, primary_slot: usize, slot_size: u8) {
        for i in 0..slot_size as usize {
            let slot_idx = primary_slot + (i * INVENTORY_COLUMNS);
            if slot_idx < INVENTORY_SIZE {
                self.inventory[slot_idx] = None;
            }
        }
    }
    
    /// Swap two inventory slots (handles multi-slot items)
    /// If either slot is a continuation, operates on the primary item instead.
    /// Returns true if swap was successful.
    pub fn swap_inventory_slots(&mut self, from_slot: u8, to_slot: u8) -> bool {
        let from_idx = from_slot as usize;
        let to_idx = to_slot as usize;
        
        if from_idx >= INVENTORY_SIZE || to_idx >= INVENTORY_SIZE {
            return false;
        }
        
        // Handle empty slot cases
        let from_empty = self.inventory[from_idx].is_none();
        let to_empty = self.inventory[to_idx].is_none();
        
        if from_empty && to_empty {
            return true; // Nothing to swap
        }
        
        // Find primary slots (in case we clicked on a continuation slot)
        let from_primary = if let Some(slot) = &self.inventory[from_idx] {
            slot.continuation_of.map(|p| p as usize).unwrap_or(from_idx)
        } else {
            from_idx
        };
        
        let to_primary = if let Some(slot) = &self.inventory[to_idx] {
            slot.continuation_of.map(|p| p as usize).unwrap_or(to_idx)
        } else {
            to_idx
        };
        
        // If both slots belong to the same item, nothing to do
        if from_primary == to_primary {
            return true;
        }
        
        // Get item info from primary slots
        let from_item = if from_empty {
            None
        } else {
            self.inventory[from_primary].as_ref().map(|s| (s.item_id, s.quantity))
        };
        
        let to_item = if to_empty {
            None
        } else {
            self.inventory[to_primary].as_ref().map(|s| (s.item_id, s.quantity))
        };
        
        // Get slot sizes
        let from_size = from_item.map(|(id, _)| get_item_slot_size(id)).unwrap_or(0);
        let to_size = to_item.map(|(id, _)| get_item_slot_size(id)).unwrap_or(0);
        
        // Case 1: Moving item to empty slot
        if to_item.is_none() {
            let (item_id, quantity) = from_item.unwrap();
            
            // Check if the destination can fit the item
            // First clear the source so dest check sees it as empty
            self.clear_item_slots(from_primary, from_size);
            
            if self.can_place_item_at(to_idx, from_size) {
                self.place_item_at(to_idx, item_id, quantity, from_size);
                return true;
            } else {
                // Can't place at destination, restore original
                self.place_item_at(from_primary, item_id, quantity, from_size);
                return false;
            }
        }
        
        // Case 2: Moving to a slot that has an item (swap)
        if from_item.is_none() {
            // Moving empty to item - just move the item to empty
            let (item_id, quantity) = to_item.unwrap();
            self.clear_item_slots(to_primary, to_size);
            
            if self.can_place_item_at(from_idx, to_size) {
                self.place_item_at(from_idx, item_id, quantity, to_size);
                return true;
            } else {
                // Can't place at destination, restore original
                self.place_item_at(to_primary, item_id, quantity, to_size);
                return false;
            }
        }
        
        // Case 3: Both slots have items - real swap
        let (from_id, from_qty) = from_item.unwrap();
        let (to_id, to_qty) = to_item.unwrap();
        
        // Clear both items first
        self.clear_item_slots(from_primary, from_size);
        self.clear_item_slots(to_primary, to_size);
        
        // Try to place from_item at to's location
        let from_dest = if self.can_place_item_at(to_primary, from_size) {
            to_primary
        } else if self.can_place_item_at(to_idx, from_size) {
            to_idx
        } else {
            // Can't place - restore both items
            self.place_item_at(from_primary, from_id, from_qty, from_size);
            self.place_item_at(to_primary, to_id, to_qty, to_size);
            return false;
        };
        
        // Try to place to_item at from's location
        let to_dest = if self.can_place_item_at(from_primary, to_size) {
            from_primary
        } else if self.can_place_item_at(from_idx, to_size) {
            from_idx
        } else {
            // Can't place to_item - restore both at original positions
            self.place_item_at(from_primary, from_id, from_qty, from_size);
            self.place_item_at(to_primary, to_id, to_qty, to_size);
            return false;
        };
        
        // Place both items at their new locations
        self.place_item_at(from_dest, from_id, from_qty, from_size);
        self.place_item_at(to_dest, to_id, to_qty, to_size);
        
        true
    }
    
    /// Add item to inventory, stacking if possible
    /// Handles multi-slot items (weapons may take 2-3 slots)
    pub fn add_to_inventory(&mut self, item_id: u32, quantity: u32) -> bool {
        let item_defs = get_item_definitions();
        let item_def = item_defs.iter().find(|i| i.id == item_id);
        let max_stack = item_def.map(|i| i.max_stack).unwrap_or(1);
        let slot_size = get_item_slot_size(item_id);
        
        let mut remaining = quantity;
        
        // For single-slot stackable items, try to stack with existing
        if slot_size == 1 && max_stack > 1 {
            for slot in &mut self.inventory {
                if remaining == 0 {
                    break;
                }
                if let Some(inv_slot) = slot {
                    // Skip continuation slots
                    if inv_slot.continuation_of.is_some() {
                        continue;
                    }
                    if inv_slot.item_id == item_id && inv_slot.quantity < max_stack {
                        let can_add = (max_stack - inv_slot.quantity).min(remaining);
                        inv_slot.quantity += can_add;
                        remaining -= can_add;
                    }
                }
            }
        }
        
        // Add to empty slots (respecting slot_size)
        while remaining > 0 {
            if let Some(start_slot) = self.find_contiguous_slots(slot_size) {
                let add_amount = remaining.min(max_stack);
                self.place_item_at(start_slot, item_id, add_amount, slot_size);
                remaining -= add_amount;
            } else {
                // No space found
                break;
            }
        }
        
        remaining == 0
    }
    
    /// Remove item from inventory slot (handles multi-slot items)
    pub fn remove_from_inventory(&mut self, slot: u8) -> Option<(u32, u32)> {
        let slot_idx = slot as usize;
        if slot_idx >= self.inventory.len() {
            return None;
        }
        
        let inv_slot = self.inventory[slot_idx].as_ref()?;
        
        // If this is a continuation slot, find the primary slot
        let primary_slot = if let Some(primary) = inv_slot.continuation_of {
            primary as usize
        } else {
            slot_idx
        };
        
        // Get the item info from the primary slot
        let primary_inv_slot = self.inventory[primary_slot].as_ref()?;
        if primary_inv_slot.continuation_of.is_some() {
            // This shouldn't happen - primary slot shouldn't be a continuation
            return None;
        }
        
        let item_id = primary_inv_slot.item_id;
        let quantity = primary_inv_slot.quantity;
        let slot_size = get_item_slot_size(item_id);
        
        // Clear all slots
        self.clear_item_slots(primary_slot, slot_size);
        
        Some((item_id, quantity))
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
    /// Note: For armor-aware damage calculation, use take_damage_with_armor instead
    pub fn take_damage(&mut self, damage: u32) -> u32 {
        if self.is_invincible {
            return 0;
        }
        let actual_damage = damage.saturating_sub(self.defense / 2);
        self.health = self.health.saturating_sub(actual_damage);
        actual_damage
    }
    
    /// Take damage with armor bonus factored in
    pub fn take_damage_with_armor(&mut self, damage: u32, items: &HashMap<u32, ItemDef>) -> u32 {
        if self.is_invincible {
            return 0;
        }
        let total_defense = self.get_total_defense(items);
        let actual_damage = damage.saturating_sub(total_defense / 2);
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
    /// The item is removed from inventory; if there was an old weapon, it goes into available slots
    pub fn try_equip_weapon(&mut self, inventory_slot: u8, items: &HashMap<u32, ItemDef>) -> Result<Option<u32>, &'static str> {
        let slot_idx = inventory_slot as usize;
        if slot_idx >= self.inventory.len() {
            return Err("Invalid inventory slot");
        }
        
        // Find the primary slot if this is a continuation
        let primary_slot = {
            let inv_slot = self.inventory[slot_idx].as_ref().ok_or("No item in slot")?;
            if let Some(primary) = inv_slot.continuation_of {
                primary as usize
            } else {
                slot_idx
            }
        };
        
        let inv_slot = self.inventory[primary_slot].as_ref().ok_or("No item in primary slot")?;
        let item_id = inv_slot.item_id;
        let new_weapon_slot_size = get_item_slot_size(item_id);
        
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
        let old_weapon_slot_size = old_weapon.map(|id| get_item_slot_size(id)).unwrap_or(0);
        
        // Clear the new weapon from inventory (all its slots)
        self.clear_item_slots(primary_slot, new_weapon_slot_size);
        
        // If we had a weapon equipped, try to put it back in the freed slots
        if let Some(old_weapon_id) = old_weapon {
            // Check if the freed slots can hold the old weapon
            if self.can_place_item_at(primary_slot, old_weapon_slot_size) {
                self.place_item_at(primary_slot, old_weapon_id, 1, old_weapon_slot_size);
            } else {
                // Try to find any available slots for the old weapon
                if let Some(free_slot) = self.find_contiguous_slots(old_weapon_slot_size) {
                    self.place_item_at(free_slot, old_weapon_id, 1, old_weapon_slot_size);
                } else {
                    // Can't fit old weapon, restore new weapon and fail
                    self.place_item_at(primary_slot, item_id, 1, new_weapon_slot_size);
                    return Err("No space for currently equipped weapon");
                }
            }
        }
        
        // Equip the new weapon
        self.equipped_weapon_id = Some(item_id);
        
        Ok(old_weapon)
    }
    
    /// Unequip weapon and put it back in inventory
    /// Returns the previously equipped weapon ID, or None if no weapon was equipped or no space
    pub fn unequip_weapon(&mut self) -> Option<u32> {
        let weapon_id = self.equipped_weapon_id.take()?;
        let slot_size = get_item_slot_size(weapon_id);
        
        // Find contiguous empty slots for the weapon
        if let Some(start_slot) = self.find_contiguous_slots(slot_size) {
            self.place_item_at(start_slot, weapon_id, 1, slot_size);
            Some(weapon_id)
        } else {
            // No space in inventory, re-equip the weapon
            self.equipped_weapon_id = Some(weapon_id);
            None
        }
    }
    
    // ==========================================================================
    // Armor Equipment
    // ==========================================================================
    
    /// Try to equip armor from inventory
    /// Returns Ok(old_armor_id) if successful, Err with reason if failed
    /// The item is removed from inventory; if there was old armor, it goes into the vacated slot
    pub fn try_equip_armor(&mut self, inventory_slot: u8, items: &HashMap<u32, ItemDef>) -> Result<Option<u32>, &'static str> {
        let slot_idx = inventory_slot as usize;
        if slot_idx >= self.inventory.len() {
            return Err("Invalid inventory slot");
        }
        
        let inv_slot = self.inventory[slot_idx].as_ref().ok_or("No item in slot")?;
        let item_id = inv_slot.item_id;
        
        let item = items.get(&item_id).ok_or("Item not found")?;
        
        // Check if it's armor
        if item.item_type != ItemType::Armor {
            return Err("Item is not armor");
        }
        
        // Check armor stats and restrictions
        if let Some(stats) = &item.armor_stats {
            // Check level requirement
            if self.level < stats.level_requirement {
                return Err("Cannot equip: level too low");
            }
            
            // Check class restriction
            if let Some(required_class) = stats.class_restriction {
                if required_class != self.class {
                    return Err("Cannot equip: wrong class");
                }
            }
        } else {
            return Err("Armor has no stats");
        }
        
        // Store the old armor before we modify anything
        let old_armor = self.equipped_armor_id;
        
        // Remove item from inventory slot
        self.inventory[slot_idx] = None;
        
        // If we had armor equipped, put it in the now-empty inventory slot
        if let Some(old_armor_id) = old_armor {
            self.inventory[slot_idx] = Some(InventorySlot {
                item_id: old_armor_id,
                quantity: 1,
                continuation_of: None,
            });
        }
        
        // Equip the new armor
        self.equipped_armor_id = Some(item_id);
        
        Ok(old_armor)
    }
    
    /// Unequip armor and put it back in inventory
    /// Returns the previously equipped armor ID, or None if no armor was equipped or no space
    pub fn unequip_armor(&mut self) -> Option<u32> {
        let armor_id = self.equipped_armor_id.take()?;
        
        // Find an empty inventory slot
        let empty_slot = self.inventory.iter().position(|s| s.is_none());
        
        if let Some(slot_idx) = empty_slot {
            self.inventory[slot_idx] = Some(InventorySlot {
                item_id: armor_id,
                quantity: 1,
                continuation_of: None,
            });
            Some(armor_id)
        } else {
            // No space in inventory, re-equip the armor
            self.equipped_armor_id = Some(armor_id);
            None
        }
    }
    
    /// Get defense bonus from equipped armor
    pub fn get_armor_defense_bonus(&self, items: &HashMap<u32, ItemDef>) -> u32 {
        if let Some(armor_id) = self.equipped_armor_id {
            if let Some(item) = items.get(&armor_id) {
                if let Some(stats) = &item.armor_stats {
                    return stats.defense;
                }
            }
        }
        0
    }
    
    /// Get HP bonus from equipped armor
    pub fn get_armor_hp_bonus(&self, items: &HashMap<u32, ItemDef>) -> u32 {
        if let Some(armor_id) = self.equipped_armor_id {
            if let Some(item) = items.get(&armor_id) {
                if let Some(stats) = &item.armor_stats {
                    return stats.hp_bonus;
                }
            }
        }
        0
    }
    
    /// Get total defense (base + armor bonus + buff bonus)
    pub fn get_total_defense(&self, items: &HashMap<u32, ItemDef>) -> u32 {
        let base = self.defense;
        let armor_bonus = self.get_armor_defense_bonus(items);
        let buff_bonus = self.get_buff_defense_bonus();
        ((base as i32 + armor_bonus as i32 + buff_bonus).max(0)) as u32
    }
    
    /// Get total max health (base + armor bonus)
    pub fn get_total_max_health(&self, items: &HashMap<u32, ItemDef>) -> u32 {
        self.max_health + self.get_armor_hp_bonus(items)
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
