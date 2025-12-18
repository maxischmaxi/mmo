-- Migration 005: Teleport Ring Item
-- A magical ring that allows instant travel between villages.
-- Every player should have one at all times.

-- Add Teleport Ring item (ID 100, item_type 4 = Quest/Special, rarity 2 = Rare)
INSERT INTO items (id, name, description, item_type, rarity, max_stack, effects)
VALUES (100, 'Teleport Ring', 'A magical ring that allows instant travel between villages. Right-click to use.', 4, 2, 1, '[]')
ON CONFLICT (id) DO NOTHING;

-- Grant teleport ring to ALL existing characters that don't already have one
-- Find the first available inventory slot (0-19) for each character
INSERT INTO player_inventory (character_id, slot, item_id, quantity)
SELECT 
    c.id as character_id,
    (
        SELECT MIN(s.slot) 
        FROM generate_series(0, 19) s(slot)
        WHERE NOT EXISTS (
            SELECT 1 FROM player_inventory pi 
            WHERE pi.character_id = c.id AND pi.slot = s.slot
        )
    ) as slot,
    100 as item_id,
    1 as quantity
FROM characters c
WHERE NOT EXISTS (
    -- Skip characters that already have a teleport ring
    SELECT 1 FROM player_inventory pi 
    WHERE pi.character_id = c.id AND pi.item_id = 100
)
AND (
    -- Only insert if there's an available slot
    SELECT MIN(s.slot) 
    FROM generate_series(0, 19) s(slot)
    WHERE NOT EXISTS (
        SELECT 1 FROM player_inventory pi 
        WHERE pi.character_id = c.id AND pi.slot = s.slot
    )
) IS NOT NULL;
