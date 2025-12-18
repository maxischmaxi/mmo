-- Weapon Visual System Migration
-- Adds visual_type and mesh_name columns for weapon rendering
-- Visual types: 0=OneHandedSword, 1=Dagger, 2=TwoHandedSword, 3=OneHandedAxe, 
--               4=TwoHandedAxe, 5=Hammer, 6=Staff, 7=Bow, 8=Spear

-- =============================================================================
-- Add visual columns to items table
-- =============================================================================

ALTER TABLE items ADD COLUMN IF NOT EXISTS visual_type SMALLINT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS mesh_name VARCHAR(64);

-- =============================================================================
-- Update existing weapons with visual data
-- =============================================================================

-- Universal Weapons (IDs 4-5)
UPDATE items SET visual_type = 0, mesh_name = 'Arming_Sword' WHERE id = 4;
UPDATE items SET visual_type = 0, mesh_name = 'Cutlass' WHERE id = 5;

-- Ninja Weapons (IDs 10-11) - Daggers
UPDATE items SET visual_type = 1, mesh_name = 'Dagger' WHERE id = 10;
UPDATE items SET visual_type = 1, mesh_name = 'Bone_Shiv' WHERE id = 11;

-- Warrior Weapons (IDs 12-13) - Two-handed
UPDATE items SET visual_type = 2, mesh_name = 'Great_Sword' WHERE id = 12;
UPDATE items SET visual_type = 4, mesh_name = 'Double_Axe' WHERE id = 13;

-- Sura Weapons (IDs 14-15) - One-handed swords
UPDATE items SET visual_type = 0, mesh_name = 'Scimitar' WHERE id = 14;
UPDATE items SET visual_type = 0, mesh_name = 'Kopesh' WHERE id = 15;

-- Shaman Weapons (IDs 16-17) - Staffs
UPDATE items SET visual_type = 6, mesh_name = 'Wizard_Staff' WHERE id = 16;
UPDATE items SET visual_type = 6, mesh_name = 'Wizard_Staff' WHERE id = 17;
