//! Item definitions shared between client and server.

use serde::{Deserialize, Serialize};

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
}

/// Item types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ItemType {
    Consumable,
    Weapon,
    Armor,
    Material,
    Quest,
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
pub fn get_item_definitions() -> Vec<ItemDef> {
    vec![
        ItemDef {
            id: 1,
            name: "Health Potion".into(),
            description: "Restores 50 health.".into(),
            item_type: ItemType::Consumable,
            rarity: ItemRarity::Common,
            max_stack: 20,
            effects: vec![ItemEffect::RestoreHealth(50)],
        },
        ItemDef {
            id: 2,
            name: "Mana Potion".into(),
            description: "Restores 30 mana.".into(),
            item_type: ItemType::Consumable,
            rarity: ItemRarity::Common,
            max_stack: 20,
            effects: vec![ItemEffect::RestoreMana(30)],
        },
        ItemDef {
            id: 3,
            name: "Goblin Ear".into(),
            description: "A trophy from a slain goblin.".into(),
            item_type: ItemType::Material,
            rarity: ItemRarity::Common,
            max_stack: 99,
            effects: vec![],
        },
        ItemDef {
            id: 4,
            name: "Rusty Sword".into(),
            description: "A worn blade. Better than nothing.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Common,
            max_stack: 1,
            effects: vec![ItemEffect::IncreaseAttack(5)],
        },
        ItemDef {
            id: 5,
            name: "Iron Sword".into(),
            description: "A sturdy iron blade.".into(),
            item_type: ItemType::Weapon,
            rarity: ItemRarity::Uncommon,
            max_stack: 1,
            effects: vec![ItemEffect::IncreaseAttack(15)],
        },
    ]
}
