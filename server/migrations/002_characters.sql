-- Character System Migration
-- Adds characters table and updates player_state/inventory to reference characters

-- Characters table
CREATE TABLE IF NOT EXISTS characters (
    id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    name VARCHAR(32) UNIQUE NOT NULL,
    class SMALLINT NOT NULL CHECK (class >= 0 AND class <= 3),
    gender SMALLINT NOT NULL CHECK (gender >= 0 AND gender <= 1),
    empire SMALLINT NOT NULL CHECK (empire >= 0 AND empire <= 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Class values: 0=Ninja, 1=Warrior, 2=Sura, 3=Shaman
-- Gender values: 0=Male, 1=Female
-- Empire values: 0=Red(Shinsoo), 1=Yellow(Chunjo), 2=Blue(Jinno)

-- Index for fast character lookup by player (account)
CREATE INDEX IF NOT EXISTS idx_characters_player ON characters(player_id);

-- Index for character name lookups (for uniqueness checks)
CREATE INDEX IF NOT EXISTS idx_characters_name ON characters(name);

-- Update player_state to reference characters instead of players
-- First drop the existing foreign key constraint
ALTER TABLE player_state DROP CONSTRAINT IF EXISTS player_state_player_id_fkey;

-- Rename the column
ALTER TABLE player_state RENAME COLUMN player_id TO character_id;

-- Add new foreign key constraint
ALTER TABLE player_state 
    ADD CONSTRAINT player_state_character_id_fkey 
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE;

-- Update player_inventory to reference characters instead of players
ALTER TABLE player_inventory DROP CONSTRAINT IF EXISTS player_inventory_player_id_fkey;

-- Rename the column
ALTER TABLE player_inventory RENAME COLUMN player_id TO character_id;

-- Add new foreign key constraint
ALTER TABLE player_inventory
    ADD CONSTRAINT player_inventory_character_id_fkey
    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE;

-- Update the index on player_inventory
DROP INDEX IF EXISTS idx_player_inventory_player;
CREATE INDEX IF NOT EXISTS idx_player_inventory_character ON player_inventory(character_id);
