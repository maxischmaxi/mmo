-- Extended Equipment Slots Migration
-- Adds additional equipment slots: helmet, shield, boots, necklace, ring

-- =============================================================================
-- Schema Changes
-- =============================================================================

-- Add new equipment slots to character_equipment table
ALTER TABLE character_equipment 
    ADD COLUMN IF NOT EXISTS helmet_slot INTEGER REFERENCES items(id),
    ADD COLUMN IF NOT EXISTS shield_slot INTEGER REFERENCES items(id),
    ADD COLUMN IF NOT EXISTS boots_slot INTEGER REFERENCES items(id),
    ADD COLUMN IF NOT EXISTS necklace_slot INTEGER REFERENCES items(id),
    ADD COLUMN IF NOT EXISTS ring_slot INTEGER REFERENCES items(id);

-- Add comment for documentation
COMMENT ON COLUMN character_equipment.helmet_slot IS 'Equipped helmet item ID';
COMMENT ON COLUMN character_equipment.shield_slot IS 'Equipped shield item ID';
COMMENT ON COLUMN character_equipment.boots_slot IS 'Equipped boots item ID';
COMMENT ON COLUMN character_equipment.necklace_slot IS 'Equipped necklace item ID';
COMMENT ON COLUMN character_equipment.ring_slot IS 'Equipped ring/arm ring item ID';
