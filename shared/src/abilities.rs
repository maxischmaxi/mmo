//! Ability definitions shared between client and server.

use serde::{Deserialize, Serialize};
use crate::CharacterClass;

// =============================================================================
// Ability Types
// =============================================================================

/// Target type for abilities
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TargetType {
    /// Targets self only
    SelfOnly,
    /// Targets a single enemy
    Enemy,
    /// Targets a single ally (including self)
    Ally,
    /// No target needed (instant effect)
    None,
    /// Area around self
    AreaAroundSelf,
    /// Area around target
    AreaAroundTarget,
}

/// Effect types that abilities can apply
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AbilityEffect {
    /// Deal direct damage (base damage, scaling factor from attack)
    Damage { base: u32, attack_scaling: f32 },
    /// Heal (base heal, scaling factor from max health)
    Heal { base: u32, health_scaling: f32 },
    /// Damage over time (damage per tick, tick interval in seconds, duration in seconds)
    DamageOverTime { damage_per_tick: u32, interval: f32, duration: f32 },
    /// Heal over time (heal per tick, tick interval in seconds, duration in seconds)
    HealOverTime { heal_per_tick: u32, interval: f32, duration: f32 },
    /// Buff attack (amount, duration in seconds)
    BuffAttack { amount: i32, duration: f32 },
    /// Buff defense (amount, duration in seconds)
    BuffDefense { amount: i32, duration: f32 },
    /// Buff attack speed (multiplier, duration in seconds)
    BuffAttackSpeed { multiplier: f32, duration: f32 },
    /// Debuff attack (amount, duration in seconds)
    DebuffAttack { amount: i32, duration: f32 },
    /// Debuff defense (amount, duration in seconds)
    DebuffDefense { amount: i32, duration: f32 },
    /// Slow target (speed multiplier 0.5 = 50% slower, duration)
    Slow { multiplier: f32, duration: f32 },
    /// Stun target (duration in seconds)
    Stun { duration: f32 },
}

/// Ability definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbilityDef {
    /// Unique ability ID
    pub id: u32,
    /// Display name
    pub name: String,
    /// Description for tooltip
    pub description: String,
    /// Mana cost to use
    pub mana_cost: u32,
    /// Cooldown in seconds
    pub cooldown: f32,
    /// Range in units (0 = melee/self)
    pub range: f32,
    /// Target type
    pub target_type: TargetType,
    /// Class restriction (None = all classes)
    pub class_restriction: Option<CharacterClass>,
    /// Minimum level required
    pub level_requirement: u32,
    /// Effects applied when ability is used
    pub effects: Vec<AbilityEffect>,
    /// Icon path (relative to res://assets/icons/)
    pub icon: String,
}

// =============================================================================
// Ability Definitions
// =============================================================================

/// Get all ability definitions
pub fn get_ability_definitions() -> Vec<AbilityDef> {
    vec![
        // =====================================================================
        // Universal Abilities (ID 1-10)
        // =====================================================================
        AbilityDef {
            id: 1,
            name: "Power Strike".into(),
            description: "A powerful melee attack dealing 150% weapon damage.".into(),
            mana_cost: 10,
            cooldown: 6.0,
            range: 3.0,
            target_type: TargetType::Enemy,
            class_restriction: None,
            level_requirement: 1,
            effects: vec![AbilityEffect::Damage { base: 5, attack_scaling: 1.5 }],
            icon: "power_strike.png".into(),
        },
        AbilityDef {
            id: 2,
            name: "Recuperate".into(),
            description: "Restore 20% of your maximum health over 10 seconds.".into(),
            mana_cost: 20,
            cooldown: 30.0,
            range: 0.0,
            target_type: TargetType::SelfOnly,
            class_restriction: None,
            level_requirement: 1,
            effects: vec![AbilityEffect::HealOverTime { 
                heal_per_tick: 0, // Will be calculated as 2% per tick
                interval: 1.0, 
                duration: 10.0 
            }],
            icon: "recuperate.png".into(),
        },
        
        // =====================================================================
        // Ninja Abilities (ID 11-20)
        // =====================================================================
        AbilityDef {
            id: 11,
            name: "Shadow Strike".into(),
            description: "Strike from the shadows, dealing 200% weapon damage with increased critical chance.".into(),
            mana_cost: 15,
            cooldown: 8.0,
            range: 3.0,
            target_type: TargetType::Enemy,
            class_restriction: Some(CharacterClass::Ninja),
            level_requirement: 1,
            effects: vec![AbilityEffect::Damage { base: 8, attack_scaling: 2.0 }],
            icon: "shadow_strike.png".into(),
        },
        AbilityDef {
            id: 12,
            name: "Poison Blade".into(),
            description: "Coat your weapon in poison, causing the target to take damage over 8 seconds.".into(),
            mana_cost: 20,
            cooldown: 12.0,
            range: 3.0,
            target_type: TargetType::Enemy,
            class_restriction: Some(CharacterClass::Ninja),
            level_requirement: 5,
            effects: vec![
                AbilityEffect::Damage { base: 5, attack_scaling: 0.5 },
                AbilityEffect::DamageOverTime { damage_per_tick: 8, interval: 2.0, duration: 8.0 },
            ],
            icon: "poison_blade.png".into(),
        },
        
        // =====================================================================
        // Warrior Abilities (ID 21-30)
        // =====================================================================
        AbilityDef {
            id: 21,
            name: "Crushing Blow".into(),
            description: "A devastating attack dealing 180% weapon damage and reducing enemy defense.".into(),
            mana_cost: 20,
            cooldown: 10.0,
            range: 3.0,
            target_type: TargetType::Enemy,
            class_restriction: Some(CharacterClass::Warrior),
            level_requirement: 1,
            effects: vec![
                AbilityEffect::Damage { base: 10, attack_scaling: 1.8 },
                AbilityEffect::DebuffDefense { amount: 5, duration: 10.0 },
            ],
            icon: "crushing_blow.png".into(),
        },
        AbilityDef {
            id: 22,
            name: "Battle Cry".into(),
            description: "Let out a battle cry, increasing your attack by 20% for 15 seconds.".into(),
            mana_cost: 25,
            cooldown: 45.0,
            range: 0.0,
            target_type: TargetType::SelfOnly,
            class_restriction: Some(CharacterClass::Warrior),
            level_requirement: 5,
            effects: vec![AbilityEffect::BuffAttack { amount: 10, duration: 15.0 }],
            icon: "battle_cry.png".into(),
        },
        
        // =====================================================================
        // Sura Abilities (ID 31-40)
        // =====================================================================
        AbilityDef {
            id: 31,
            name: "Dark Slash".into(),
            description: "Channel dark energy into your blade, dealing 170% weapon damage.".into(),
            mana_cost: 15,
            cooldown: 7.0,
            range: 3.0,
            target_type: TargetType::Enemy,
            class_restriction: Some(CharacterClass::Sura),
            level_requirement: 1,
            effects: vec![AbilityEffect::Damage { base: 8, attack_scaling: 1.7 }],
            icon: "dark_slash.png".into(),
        },
        AbilityDef {
            id: 32,
            name: "Life Drain".into(),
            description: "Drain life from your enemy, dealing damage and healing yourself.".into(),
            mana_cost: 30,
            cooldown: 15.0,
            range: 5.0,
            target_type: TargetType::Enemy,
            class_restriction: Some(CharacterClass::Sura),
            level_requirement: 5,
            effects: vec![
                AbilityEffect::Damage { base: 15, attack_scaling: 1.0 },
                AbilityEffect::Heal { base: 20, health_scaling: 0.1 },
            ],
            icon: "life_drain.png".into(),
        },
        
        // =====================================================================
        // Shaman Abilities (ID 41-50)
        // =====================================================================
        AbilityDef {
            id: 41,
            name: "Lightning Bolt".into(),
            description: "Call down lightning on your enemy, dealing magic damage.".into(),
            mana_cost: 20,
            cooldown: 5.0,
            range: 15.0,
            target_type: TargetType::Enemy,
            class_restriction: Some(CharacterClass::Shaman),
            level_requirement: 1,
            effects: vec![AbilityEffect::Damage { base: 25, attack_scaling: 0.8 }],
            icon: "lightning_bolt.png".into(),
        },
        AbilityDef {
            id: 42,
            name: "Healing Wave".into(),
            description: "Channel healing energy to restore health.".into(),
            mana_cost: 35,
            cooldown: 12.0,
            range: 0.0,
            target_type: TargetType::SelfOnly,
            class_restriction: Some(CharacterClass::Shaman),
            level_requirement: 5,
            effects: vec![AbilityEffect::Heal { base: 50, health_scaling: 0.15 }],
            icon: "healing_wave.png".into(),
        },
    ]
}

/// Get ability by ID
pub fn get_ability_by_id(id: u32) -> Option<AbilityDef> {
    get_ability_definitions().into_iter().find(|a| a.id == id)
}

/// Get abilities available for a class at a given level
pub fn get_abilities_for_class(class: CharacterClass, level: u32) -> Vec<AbilityDef> {
    get_ability_definitions()
        .into_iter()
        .filter(|a| {
            // Must meet level requirement
            a.level_requirement <= level &&
            // Must be universal or match class
            (a.class_restriction.is_none() || a.class_restriction == Some(class))
        })
        .collect()
}

/// Get default action bar ability IDs for a class (slots 1-4)
pub fn get_default_action_bar(class: CharacterClass) -> [Option<u32>; 8] {
    let mut bar = [None; 8];
    
    // Slot 0: Power Strike (universal)
    bar[0] = Some(1);
    
    // Slot 1: Class-specific attack ability
    bar[1] = match class {
        CharacterClass::Ninja => Some(11),   // Shadow Strike
        CharacterClass::Warrior => Some(21), // Crushing Blow
        CharacterClass::Sura => Some(31),    // Dark Slash
        CharacterClass::Shaman => Some(41),  // Lightning Bolt
    };
    
    // Slot 2: Class-specific utility (unlocked at level 5)
    bar[2] = match class {
        CharacterClass::Ninja => Some(12),   // Poison Blade
        CharacterClass::Warrior => Some(22), // Battle Cry
        CharacterClass::Sura => Some(32),    // Life Drain
        CharacterClass::Shaman => Some(42),  // Healing Wave
    };
    
    // Slot 3: Recuperate (universal)
    bar[3] = Some(2);
    
    // Slots 4-7: Empty for future abilities
    
    bar
}
