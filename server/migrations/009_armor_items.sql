-- Armor System Migration
-- Adds armor slot to equipment table and armor-specific columns to items table
-- Also inserts all armor item definitions

-- =============================================================================
-- Schema Changes
-- =============================================================================

-- Add armor slot to character_equipment table
ALTER TABLE character_equipment 
    ADD COLUMN IF NOT EXISTS armor_slot INTEGER REFERENCES items(id);

-- Add armor-specific columns to items table
-- defense_bonus: armor defense value
-- hp_bonus: armor HP bonus value  
-- level_requirement: minimum level to equip (applies to armor)
ALTER TABLE items 
    ADD COLUMN IF NOT EXISTS defense_bonus INTEGER,
    ADD COLUMN IF NOT EXISTS hp_bonus INTEGER,
    ADD COLUMN IF NOT EXISTS level_requirement INTEGER DEFAULT 0;

-- Update item_type constraint to include item type 5 (Special)
-- Item types: 0=Consumable, 1=Weapon, 2=Armor, 3=Material, 4=Quest, 5=Special
ALTER TABLE items DROP CONSTRAINT IF EXISTS items_item_type_check;
ALTER TABLE items ADD CONSTRAINT items_item_type_check CHECK (item_type >= 0 AND item_type <= 5);

-- =============================================================================
-- Armor Items: Ninja (IDs 200-205)
-- =============================================================================
-- Class restriction: 0=Ninja, 1=Warrior, 2=Sura, 3=Shaman
-- Rarity: 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Legendary
-- Item type 2 = Armor

INSERT INTO items (id, name, description, item_type, rarity, max_stack, class_restriction, defense_bonus, hp_bonus, level_requirement, effects) VALUES
(200, 'Ninja Cloth Wrappings', 'Simple cloth wrappings worn by ninja initiates.', 2, 0, 1, 0, 5, 20, 0, '[]'),
(201, 'Shadow Leather Vest', 'Dark leather armor that blends with shadows.', 2, 1, 1, 0, 12, 50, 9, '[]'),
(202, 'Silent Chainmail', 'Specially crafted chainmail that makes no sound.', 2, 2, 1, 0, 22, 90, 18, '[]'),
(203, 'Assassin''s Plate', 'Lightweight plate armor favored by master assassins.', 2, 2, 1, 0, 35, 140, 26, '[]'),
(204, 'Phantom Armor', 'Enchanted armor that seems to phase in and out of existence.', 2, 3, 1, 0, 50, 200, 32, '[]'),
(205, 'Eclipse Raiment', 'Legendary armor forged during a solar eclipse, granting its wearer supernatural agility.', 2, 4, 1, 0, 70, 300, 46, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    class_restriction = EXCLUDED.class_restriction,
    defense_bonus = EXCLUDED.defense_bonus,
    hp_bonus = EXCLUDED.hp_bonus,
    level_requirement = EXCLUDED.level_requirement,
    effects = EXCLUDED.effects;

-- =============================================================================
-- Armor Items: Warrior (IDs 210-215)
-- =============================================================================

INSERT INTO items (id, name, description, item_type, rarity, max_stack, class_restriction, defense_bonus, hp_bonus, level_requirement, effects) VALUES
(210, 'Warrior''s Padded Tunic', 'A thick padded tunic for new warriors.', 2, 0, 1, 1, 7, 30, 0, '[]'),
(211, 'Battle Leather Armor', 'Sturdy leather armor reinforced for combat.', 2, 1, 1, 1, 15, 60, 9, '[]'),
(212, 'Soldier''s Chainmail', 'Standard issue chainmail for seasoned soldiers.', 2, 2, 1, 1, 28, 110, 18, '[]'),
(213, 'Veteran''s Plate', 'Heavy plate armor worn by veteran warriors.', 2, 2, 1, 1, 45, 170, 26, '[]'),
(214, 'Champion''s Aegis', 'Magnificent armor forged for tournament champions.', 2, 3, 1, 1, 65, 250, 32, '[]'),
(215, 'Warlord''s Regalia', 'Legendary armor worn by the greatest warlords in history.', 2, 4, 1, 1, 90, 380, 46, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    class_restriction = EXCLUDED.class_restriction,
    defense_bonus = EXCLUDED.defense_bonus,
    hp_bonus = EXCLUDED.hp_bonus,
    level_requirement = EXCLUDED.level_requirement,
    effects = EXCLUDED.effects;

-- =============================================================================
-- Armor Items: Sura (IDs 220-225)
-- =============================================================================

INSERT INTO items (id, name, description, item_type, rarity, max_stack, class_restriction, defense_bonus, hp_bonus, level_requirement, effects) VALUES
(220, 'Sura Initiate Robes', 'Dark robes worn by those beginning the path of the Sura.', 2, 0, 1, 2, 5, 25, 0, '[]'),
(221, 'Dark Leather Vestments', 'Leather armor imbued with dark energy.', 2, 1, 1, 2, 12, 55, 9, '[]'),
(222, 'Cursed Chainmail', 'Chainmail armor corrupted by dark magic.', 2, 2, 1, 2, 24, 100, 18, '[]'),
(223, 'Demon-Touched Plate', 'Plate armor marked by demonic influence.', 2, 2, 1, 2, 38, 155, 26, '[]'),
(224, 'Abyssal Armor', 'Armor forged in the depths of the abyss.', 2, 3, 1, 2, 55, 220, 32, '[]'),
(225, 'Netherworld Vestments', 'Legendary armor from the netherworld, pulsing with dark power.', 2, 4, 1, 2, 75, 330, 46, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    class_restriction = EXCLUDED.class_restriction,
    defense_bonus = EXCLUDED.defense_bonus,
    hp_bonus = EXCLUDED.hp_bonus,
    level_requirement = EXCLUDED.level_requirement,
    effects = EXCLUDED.effects;

-- =============================================================================
-- Armor Items: Shaman (IDs 230-235)
-- =============================================================================

INSERT INTO items (id, name, description, item_type, rarity, max_stack, class_restriction, defense_bonus, hp_bonus, level_requirement, effects) VALUES
(230, 'Shaman Apprentice Robes', 'Simple robes worn by shaman apprentices.', 2, 0, 1, 3, 4, 20, 0, '[]'),
(231, 'Spirit Leather Tunic', 'Leather armor blessed by nature spirits.', 2, 1, 1, 3, 10, 45, 9, '[]'),
(232, 'Ancestral Chainmail', 'Chainmail passed down through generations of shamans.', 2, 2, 1, 3, 20, 85, 18, '[]'),
(233, 'Totem-Bearer''s Plate', 'Sacred plate armor worn by totem bearers.', 2, 2, 1, 3, 32, 130, 26, '[]'),
(234, 'Elder''s Regalia', 'Ceremonial armor of the tribal elders.', 2, 3, 1, 3, 48, 190, 32, '[]'),
(235, 'Sacred Spirit Vestments', 'Legendary vestments blessed by the great spirits themselves.', 2, 4, 1, 3, 68, 290, 46, '[]')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    item_type = EXCLUDED.item_type,
    rarity = EXCLUDED.rarity,
    max_stack = EXCLUDED.max_stack,
    class_restriction = EXCLUDED.class_restriction,
    defense_bonus = EXCLUDED.defense_bonus,
    hp_bonus = EXCLUDED.hp_bonus,
    level_requirement = EXCLUDED.level_requirement,
    effects = EXCLUDED.effects;

-- =============================================================================
-- Equip starter armor for existing characters based on their class
-- =============================================================================

-- Update existing character equipment records to add starter armor
-- Class 0 (Ninja) -> armor 200
-- Class 1 (Warrior) -> armor 210
-- Class 2 (Sura) -> armor 220
-- Class 3 (Shaman) -> armor 230

UPDATE character_equipment ce
SET armor_slot = CASE 
    WHEN c.class = 0 THEN 200
    WHEN c.class = 1 THEN 210
    WHEN c.class = 2 THEN 220
    WHEN c.class = 3 THEN 230
    ELSE NULL
END
FROM characters c
WHERE ce.character_id = c.id
AND ce.armor_slot IS NULL;
