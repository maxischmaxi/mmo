-- Items and Equipment System Migration
-- Adds items table with weapon stats and character equipment

-- =============================================================================
-- Items Table: Master item definitions
-- =============================================================================
-- Item types: 0=Consumable, 1=Weapon, 2=Armor, 3=Material, 4=Quest
-- Rarity: 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Legendary
-- Class restriction: NULL=Any, 0=Ninja, 1=Warrior, 2=Sura, 3=Shaman

CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    description TEXT NOT NULL,
    item_type SMALLINT NOT NULL CHECK (item_type >= 0 AND item_type <= 4),
    rarity SMALLINT NOT NULL CHECK (rarity >= 0 AND rarity <= 4),
    max_stack INTEGER NOT NULL DEFAULT 1 CHECK (max_stack > 0),
    -- Weapon-specific fields (NULL for non-weapons)
    damage INTEGER,
    attack_speed REAL,
    class_restriction SMALLINT CHECK (class_restriction IS NULL OR (class_restriction >= 0 AND class_restriction <= 3)),
    -- Effects stored as JSONB for flexibility (consumables, buffs, etc.)
    effects JSONB NOT NULL DEFAULT '[]'
);

-- Index for item type lookups (e.g., "get all weapons")
CREATE INDEX IF NOT EXISTS idx_items_type ON items(item_type);

-- =============================================================================
-- Character Equipment Table: What's equipped per character
-- =============================================================================

CREATE TABLE IF NOT EXISTS character_equipment (
    character_id BIGINT PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    weapon_slot INTEGER REFERENCES items(id),  -- NULL = unarmed
    -- Future expansion: armor_head, armor_chest, armor_legs, armor_boots, etc.
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Trigger to auto-update updated_at
DROP TRIGGER IF EXISTS update_character_equipment_updated_at ON character_equipment;
CREATE TRIGGER update_character_equipment_updated_at
    BEFORE UPDATE ON character_equipment
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- Seed Data: Items
-- =============================================================================

-- Consumables and Materials (IDs 1-9)
INSERT INTO items (id, name, description, item_type, rarity, max_stack, effects) VALUES
(1, 'Health Potion', 'Restores 50 health.', 0, 0, 20, '[{"RestoreHealth": 50}]'),
(2, 'Mana Potion', 'Restores 30 mana.', 0, 0, 20, '[{"RestoreMana": 30}]'),
(3, 'Goblin Ear', 'A trophy from a slain goblin.', 3, 0, 99, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    effects = EXCLUDED.effects;

-- Universal Weapons (IDs 4-5) - Any class can use
INSERT INTO items (id, name, description, item_type, rarity, max_stack, damage, attack_speed, class_restriction, effects) VALUES
(4, 'Rusty Sword', 'A worn blade. Better than nothing.', 1, 0, 1, 8, 1.0, NULL, '[]'),
(5, 'Iron Sword', 'A sturdy iron blade.', 1, 1, 1, 12, 1.0, NULL, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    damage = EXCLUDED.damage,
    attack_speed = EXCLUDED.attack_speed,
    class_restriction = EXCLUDED.class_restriction,
    effects = EXCLUDED.effects;

-- Ninja Weapons (IDs 10-11) - Fast attacks, moderate damage
INSERT INTO items (id, name, description, item_type, rarity, max_stack, damage, attack_speed, class_restriction, effects) VALUES
(10, 'Shadow Dagger', 'A swift blade favored by ninjas.', 1, 0, 1, 10, 1.3, 0, '[]'),
(11, 'Viper''s Fang', 'A deadly dagger that strikes like a serpent.', 1, 2, 1, 18, 1.4, 0, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    damage = EXCLUDED.damage,
    attack_speed = EXCLUDED.attack_speed,
    class_restriction = EXCLUDED.class_restriction,
    effects = EXCLUDED.effects;

-- Warrior Weapons (IDs 12-13) - Slow attacks, high damage
INSERT INTO items (id, name, description, item_type, rarity, max_stack, damage, attack_speed, class_restriction, effects) VALUES
(12, 'Steel Claymore', 'A heavy two-handed sword for warriors.', 1, 0, 1, 16, 0.85, 1, '[]'),
(13, 'Berserker''s Axe', 'A massive axe that cleaves through armor.', 1, 2, 1, 26, 0.8, 1, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    damage = EXCLUDED.damage,
    attack_speed = EXCLUDED.attack_speed,
    class_restriction = EXCLUDED.class_restriction,
    effects = EXCLUDED.effects;

-- Sura Weapons (IDs 14-15) - Balanced with slight speed advantage
INSERT INTO items (id, name, description, item_type, rarity, max_stack, damage, attack_speed, class_restriction, effects) VALUES
(14, 'Cursed Scimitar', 'A blade infused with dark magic.', 1, 0, 1, 12, 1.15, 2, '[]'),
(15, 'Soulreaver Blade', 'A sword that hungers for souls.', 1, 2, 1, 22, 1.2, 2, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    damage = EXCLUDED.damage,
    attack_speed = EXCLUDED.attack_speed,
    class_restriction = EXCLUDED.class_restriction,
    effects = EXCLUDED.effects;

-- Shaman Weapons (IDs 16-17) - Magic-focused, normal speed
INSERT INTO items (id, name, description, item_type, rarity, max_stack, damage, attack_speed, class_restriction, effects) VALUES
(16, 'Oak Staff', 'A simple staff for channeling nature magic.', 1, 0, 1, 8, 1.0, 3, '[]'),
(17, 'Spirit Totem', 'A totem imbued with ancestral spirits.', 1, 2, 1, 14, 1.1, 3, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    damage = EXCLUDED.damage,
    attack_speed = EXCLUDED.attack_speed,
    class_restriction = EXCLUDED.class_restriction,
    effects = EXCLUDED.effects;

-- =============================================================================
-- Create equipment records for existing characters (if any)
-- Sets them to unarmed initially - they can equip from inventory
-- =============================================================================

INSERT INTO character_equipment (character_id, weapon_slot)
SELECT id, NULL FROM characters
WHERE id NOT IN (SELECT character_id FROM character_equipment)
ON CONFLICT (character_id) DO NOTHING;
