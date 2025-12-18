//! Item definitions shared between client and server.

use serde::{Deserialize, Serialize};
use crate::CharacterClass;

/// Teleport Ring item ID - every player should have one
pub const TELEPORT_RING_ID: u32 = 100;

/// Visual type for weapons - determines grip style and animations
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[repr(u8)]
pub enum WeaponVisualType {
    #[default]
    OneHandedSword = 0,
    Dagger = 1,
    TwoHandedSword = 2,
    OneHandedAxe = 3,
    TwoHandedAxe = 4,
    Hammer = 5,
    Staff = 6,
    Bow = 7,
    Spear = 8,
}

impl WeaponVisualType {
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::OneHandedSword),
            1 => Some(Self::Dagger),
            2 => Some(Self::TwoHandedSword),
            3 => Some(Self::OneHandedAxe),
            4 => Some(Self::TwoHandedAxe),
            5 => Some(Self::Hammer),
            6 => Some(Self::Staff),
            7 => Some(Self::Bow),
            8 => Some(Self::Spear),
            _ => None,
        }
    }
    
    pub fn as_u8(&self) -> u8 {
        *self as u8
    }
}

/// Weapon-specific stats
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeaponStats {
    /// Base damage of the weapon
    pub damage: u32,
    /// Attack speed multiplier (1.0 = normal, 1.3 = 30% faster, 0.8 = 20% slower)
    pub attack_speed: f32,
    /// Class restriction (None = any class can use)
    pub class_restriction: Option<CharacterClass>,
    /// Visual type for grip style and animations
    pub visual_type: WeaponVisualType,
    /// Mesh name from the weapon pack (e.g., "Arming_Sword" loads "...fbx_Arming_Sword.fbx")
    pub mesh_name: String,
}

/// Item definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemDef {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub item_type: ItemType,
    pub rarity: ItemRarity,
    pub max_stack: u32,
    pub effects: Vec<ItemEffect>,
    /// Weapon stats (only for weapons)
    pub weapon_stats: Option<WeaponStats>,
}

/// Item types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ItemType {
    Consumable = 0,
    Weapon = 1,
    Armor = 2,
    Material = 3,
    Quest = 4,
    /// Special items like Teleport Ring - cannot be dropped or sold
    Special = 5,
}

/// Item rarity
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ItemRarity {
    Common,
    Uncommon,
    Rare,
    Epic,
    Legendary,
}

/// Effects that items can have
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ItemEffect {
    RestoreHealth(u32),
    RestoreMana(u32),
    IncreaseAttack(u32),
    IncreaseDefense(u32),
    IncreaseSpeed(f32),
}

/// Built-in item definitions for the prototype
/// NOTE: These are fallback definitions. The server loads items from the database.
/// This function is kept for client-side reference until full item sync is implemented.
pub fn get_item_definitions() -> Vec<ItemDef> {
    vec![
        // Consumables and Materials (IDs 1-3)
        ItemDef {
            id: 1,
            name: "Health Potion".into(),
            description: "Restores 50 health.".into(),
            item_type: ItemType::Consumable,
            rarity: ItemRarity::Common,
            max_stack: 20,
            effects: vec![ItemEffect::RestoreHealth(50)],
            weapon_stats: None,
        },
        ItemDef {
            id: 2,
            name: "Mana Potion".into(),
            description: "Restores 30 mana.".into(),
            item_type: ItemType::Consumable,
            rarity: ItemRarity::Common,
            max_stack: 20,
            effects: vec![ItemEffect::RestoreMana(30)],
            weapon_stats: None,
        },
        ItemDef {
            id: 3,
            name: "Goblin Ear".into(),
            description: "A trophy from a slain goblin.".into(),
            item_type: ItemType::Material,
            rarity: ItemRarity::Common,
            max_stack: 99,
            effects: vec![],
            weapon_stats: None,
        },
        // Universal Weapons (IDs 4-5)
        ItemDef {
            id: 4,
            name: "Rusty Sword".into(),
            description: "A worn blade. Better than nothing.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 8,
                attack_speed: 1.0,
                class_restriction: None,
                visual_type: WeaponVisualType::OneHandedSword,
                mesh_name: "Arming_Sword".into(),
            }),
        },
        ItemDef {
            id: 5,
            name: "Iron Sword".into(),
            description: "A sturdy iron blade.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Uncommon,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 12,
                attack_speed: 1.0,
                class_restriction: None,
                visual_type: WeaponVisualType::OneHandedSword,
                mesh_name: "Cutlass".into(),
            }),
        },
        // Ninja Weapons (IDs 10-11)
        ItemDef {
            id: 10,
            name: "Shadow Dagger".into(),
            description: "A swift blade favored by ninjas.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 10,
                attack_speed: 1.3,
                class_restriction: Some(CharacterClass::Ninja),
                visual_type: WeaponVisualType::Dagger,
                mesh_name: "Dagger".into(),
            }),
        },
        ItemDef {
            id: 11,
            name: "Viper's Fang".into(),
            description: "A deadly dagger that strikes like a serpent.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 18,
                attack_speed: 1.4,
                class_restriction: Some(CharacterClass::Ninja),
                visual_type: WeaponVisualType::Dagger,
                mesh_name: "Bone_Shiv".into(),
            }),
        },
        // Warrior Weapons (IDs 12-13)
        ItemDef {
            id: 12,
            name: "Steel Claymore".into(),
            description: "A heavy two-handed sword for warriors.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 16,
                attack_speed: 0.85,
                class_restriction: Some(CharacterClass::Warrior),
                visual_type: WeaponVisualType::TwoHandedSword,
                mesh_name: "Great_Sword".into(),
            }),
        },
        ItemDef {
            id: 13,
            name: "Berserker's Axe".into(),
            description: "A massive axe that cleaves through armor.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 26,
                attack_speed: 0.8,
                class_restriction: Some(CharacterClass::Warrior),
                visual_type: WeaponVisualType::TwoHandedAxe,
                mesh_name: "Double_Axe".into(),
            }),
        },
        // Sura Weapons (IDs 14-15)
        ItemDef {
            id: 14,
            name: "Cursed Scimitar".into(),
            description: "A blade infused with dark magic.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 12,
                attack_speed: 1.15,
                class_restriction: Some(CharacterClass::Sura),
                visual_type: WeaponVisualType::OneHandedSword,
                mesh_name: "Scimitar".into(),
            }),
        },
        ItemDef {
            id: 15,
            name: "Soulreaver Blade".into(),
            description: "A sword that hungers for souls.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 22,
                attack_speed: 1.2,
                class_restriction: Some(CharacterClass::Sura),
                visual_type: WeaponVisualType::OneHandedSword,
                mesh_name: "Kopesh".into(),
            }),
        },
        // Shaman Weapons (IDs 16-17)
        ItemDef {
            id: 16,
            name: "Oak Staff".into(),
            description: "A simple staff for channeling nature magic.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 8,
                attack_speed: 1.0,
                class_restriction: Some(CharacterClass::Shaman),
                visual_type: WeaponVisualType::Staff,
                mesh_name: "Wizard_Staff".into(),
            }),
        },
        ItemDef {
            id: 17,
            name: "Spirit Totem".into(),
            description: "A totem imbued with ancestral spirits.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: Some(WeaponStats {
                damage: 14,
                attack_speed: 1.1,
                class_restriction: Some(CharacterClass::Shaman),
                visual_type: WeaponVisualType::Staff,
                mesh_name: "Wizard_Staff".into(),
            }),
        },
        // Special Items
        ItemDef {
            id: TELEPORT_RING_ID,
            name: "Teleport Ring".into(),
            description: "A magical ring that allows instant travel between villages. Right-click to use.".into(),
            item_type: ItemType::Special,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
        },
    ]
}
