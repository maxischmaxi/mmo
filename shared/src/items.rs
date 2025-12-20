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

/// Armor-specific stats
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArmorStats {
    /// Defense bonus from armor
    pub defense: u32,
    /// HP bonus from armor
    pub hp_bonus: u32,
    /// Minimum level required to equip
    pub level_requirement: u32,
    /// Class restriction (None = any class can use)
    pub class_restriction: Option<CharacterClass>,
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
    /// Armor stats (only for armor)
    pub armor_stats: Option<ArmorStats>,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
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
            armor_stats: None,
        },
        
        // =============================================================================
        // ARMOR ITEMS (IDs 200-235)
        // =============================================================================
        
        // -----------------------------------------------------------------------------
        // Ninja Armor (IDs 200-205)
        // -----------------------------------------------------------------------------
        ItemDef {
            id: 200,
            name: "Ninja Cloth Wrappings".into(),
            description: "Simple cloth wrappings worn by ninja initiates.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 5,
                hp_bonus: 20,
                level_requirement: 0,
                class_restriction: Some(CharacterClass::Ninja),
            }),
        },
        ItemDef {
            id: 201,
            name: "Shadow Leather Vest".into(),
            description: "Dark leather armor that blends with shadows.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Uncommon,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 12,
                hp_bonus: 50,
                level_requirement: 9,
                class_restriction: Some(CharacterClass::Ninja),
            }),
        },
        ItemDef {
            id: 202,
            name: "Silent Chainmail".into(),
            description: "Specially crafted chainmail that makes no sound.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 22,
                hp_bonus: 90,
                level_requirement: 18,
                class_restriction: Some(CharacterClass::Ninja),
            }),
        },
        ItemDef {
            id: 203,
            name: "Assassin's Plate".into(),
            description: "Lightweight plate armor favored by master assassins.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 35,
                hp_bonus: 140,
                level_requirement: 26,
                class_restriction: Some(CharacterClass::Ninja),
            }),
        },
        ItemDef {
            id: 204,
            name: "Phantom Armor".into(),
            description: "Enchanted armor that seems to phase in and out of existence.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Epic,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 50,
                hp_bonus: 200,
                level_requirement: 32,
                class_restriction: Some(CharacterClass::Ninja),
            }),
        },
        ItemDef {
            id: 205,
            name: "Eclipse Raiment".into(),
            description: "Legendary armor forged during a solar eclipse, granting its wearer supernatural agility.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Legendary,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 70,
                hp_bonus: 300,
                level_requirement: 46,
                class_restriction: Some(CharacterClass::Ninja),
            }),
        },
        
        // -----------------------------------------------------------------------------
        // Warrior Armor (IDs 210-215)
        // -----------------------------------------------------------------------------
        ItemDef {
            id: 210,
            name: "Warrior's Padded Tunic".into(),
            description: "A thick padded tunic for new warriors.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 7,
                hp_bonus: 30,
                level_requirement: 0,
                class_restriction: Some(CharacterClass::Warrior),
            }),
        },
        ItemDef {
            id: 211,
            name: "Battle Leather Armor".into(),
            description: "Sturdy leather armor reinforced for combat.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Uncommon,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 15,
                hp_bonus: 60,
                level_requirement: 9,
                class_restriction: Some(CharacterClass::Warrior),
            }),
        },
        ItemDef {
            id: 212,
            name: "Soldier's Chainmail".into(),
            description: "Standard issue chainmail for seasoned soldiers.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 28,
                hp_bonus: 110,
                level_requirement: 18,
                class_restriction: Some(CharacterClass::Warrior),
            }),
        },
        ItemDef {
            id: 213,
            name: "Veteran's Plate".into(),
            description: "Heavy plate armor worn by veteran warriors.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 45,
                hp_bonus: 170,
                level_requirement: 26,
                class_restriction: Some(CharacterClass::Warrior),
            }),
        },
        ItemDef {
            id: 214,
            name: "Champion's Aegis".into(),
            description: "Magnificent armor forged for tournament champions.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Epic,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 65,
                hp_bonus: 250,
                level_requirement: 32,
                class_restriction: Some(CharacterClass::Warrior),
            }),
        },
        ItemDef {
            id: 215,
            name: "Warlord's Regalia".into(),
            description: "Legendary armor worn by the greatest warlords in history.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Legendary,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 90,
                hp_bonus: 380,
                level_requirement: 46,
                class_restriction: Some(CharacterClass::Warrior),
            }),
        },
        
        // -----------------------------------------------------------------------------
        // Sura Armor (IDs 220-225)
        // -----------------------------------------------------------------------------
        ItemDef {
            id: 220,
            name: "Sura Initiate Robes".into(),
            description: "Dark robes worn by those beginning the path of the Sura.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 5,
                hp_bonus: 25,
                level_requirement: 0,
                class_restriction: Some(CharacterClass::Sura),
            }),
        },
        ItemDef {
            id: 221,
            name: "Dark Leather Vestments".into(),
            description: "Leather armor imbued with dark energy.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Uncommon,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 12,
                hp_bonus: 55,
                level_requirement: 9,
                class_restriction: Some(CharacterClass::Sura),
            }),
        },
        ItemDef {
            id: 222,
            name: "Cursed Chainmail".into(),
            description: "Chainmail armor corrupted by dark magic.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 24,
                hp_bonus: 100,
                level_requirement: 18,
                class_restriction: Some(CharacterClass::Sura),
            }),
        },
        ItemDef {
            id: 223,
            name: "Demon-Touched Plate".into(),
            description: "Plate armor marked by demonic influence.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 38,
                hp_bonus: 155,
                level_requirement: 26,
                class_restriction: Some(CharacterClass::Sura),
            }),
        },
        ItemDef {
            id: 224,
            name: "Abyssal Armor".into(),
            description: "Armor forged in the depths of the abyss.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Epic,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 55,
                hp_bonus: 220,
                level_requirement: 32,
                class_restriction: Some(CharacterClass::Sura),
            }),
        },
        ItemDef {
            id: 225,
            name: "Netherworld Vestments".into(),
            description: "Legendary armor from the netherworld, pulsing with dark power.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Legendary,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 75,
                hp_bonus: 330,
                level_requirement: 46,
                class_restriction: Some(CharacterClass::Sura),
            }),
        },
        
        // -----------------------------------------------------------------------------
        // Shaman Armor (IDs 230-235)
        // -----------------------------------------------------------------------------
        ItemDef {
            id: 230,
            name: "Shaman Apprentice Robes".into(),
            description: "Simple robes worn by shaman apprentices.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 4,
                hp_bonus: 20,
                level_requirement: 0,
                class_restriction: Some(CharacterClass::Shaman),
            }),
        },
        ItemDef {
            id: 231,
            name: "Spirit Leather Tunic".into(),
            description: "Leather armor blessed by nature spirits.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Uncommon,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 10,
                hp_bonus: 45,
                level_requirement: 9,
                class_restriction: Some(CharacterClass::Shaman),
            }),
        },
        ItemDef {
            id: 232,
            name: "Ancestral Chainmail".into(),
            description: "Chainmail passed down through generations of shamans.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 20,
                hp_bonus: 85,
                level_requirement: 18,
                class_restriction: Some(CharacterClass::Shaman),
            }),
        },
        ItemDef {
            id: 233,
            name: "Totem-Bearer's Plate".into(),
            description: "Sacred plate armor worn by totem bearers.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Rare,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 32,
                hp_bonus: 130,
                level_requirement: 26,
                class_restriction: Some(CharacterClass::Shaman),
            }),
        },
        ItemDef {
            id: 234,
            name: "Elder's Regalia".into(),
            description: "Ceremonial armor of the tribal elders.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Epic,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 48,
                hp_bonus: 190,
                level_requirement: 32,
                class_restriction: Some(CharacterClass::Shaman),
            }),
        },
        ItemDef {
            id: 235,
            name: "Sacred Spirit Vestments".into(),
            description: "Legendary vestments blessed by the great spirits themselves.".into(),
            item_type: ItemType::Armor,
            rarity: ItemRarity::Legendary,
            max_stack: 1,
            effects: vec![],
            weapon_stats: None,
            armor_stats: Some(ArmorStats {
                defense: 68,
                hp_bonus: 290,
                level_requirement: 46,
                class_restriction: Some(CharacterClass::Shaman),
            }),
        },
    ]
}

/// Get starter armor ID for a character class
pub fn get_starter_armor_id(class: CharacterClass) -> u32 {
    match class {
        CharacterClass::Ninja => 200,    // Ninja Cloth Wrappings
        CharacterClass::Warrior => 210,  // Warrior's Padded Tunic
        CharacterClass::Sura => 220,     // Sura Initiate Robes
        CharacterClass::Shaman => 230,   // Shaman Apprentice Robes
    }
}
