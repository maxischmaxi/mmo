//! Server-side player entity.

use mmo_shared::{AnimationState, InventorySlot, ItemEffect, ItemDef, ItemType, CharacterClass, Gender, Empire, get_item_definitions};
use std::collections::HashMap;

/// Maximum inventory slots
const INVENTORY_SIZE: usize = 20;

/// Server-side player state
#[derive(Debug)]
pub struct ServerPlayer {
    pub id: u64,
    pub name: String,
    pub class: CharacterClass,
    pub gender: Gender,
    pub empire: Empire,
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
}

impl ServerPlayer {
    /// Create a player with saved state (for persistence)
    #[allow(clippy::too_many_arguments)]
    pub fn with_state(
        id: u64,
        name: String,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
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
    ) -> Self {
        Self {
            id,
            name,
            class,
            gender,
            empire,
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
    
    /// Take damage
    pub fn take_damage(&mut self, damage: u32) -> u32 {
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
}
