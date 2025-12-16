-- MMO Database Schema
-- Initial migration: Players, State, and Inventory

-- Players table: Authentication and account info
CREATE TABLE IF NOT EXISTS players (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(32) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE
);

-- Index for fast username lookups during login
CREATE INDEX IF NOT EXISTS idx_players_username ON players(username);

-- Player state table: Position, stats, and combat info
CREATE TABLE IF NOT EXISTS player_state (
    player_id BIGINT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    position_x REAL NOT NULL DEFAULT 0.0,
    position_y REAL NOT NULL DEFAULT 1.0,
    position_z REAL NOT NULL DEFAULT 0.0,
    rotation REAL NOT NULL DEFAULT 0.0,
    health INTEGER NOT NULL DEFAULT 100,
    max_health INTEGER NOT NULL DEFAULT 100,
    mana INTEGER NOT NULL DEFAULT 50,
    max_mana INTEGER NOT NULL DEFAULT 50,
    level INTEGER NOT NULL DEFAULT 1,
    experience INTEGER NOT NULL DEFAULT 0,
    attack INTEGER NOT NULL DEFAULT 10,
    defense INTEGER NOT NULL DEFAULT 5,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Player inventory table: Items in inventory slots
CREATE TABLE IF NOT EXISTS player_inventory (
    player_id BIGINT REFERENCES players(id) ON DELETE CASCADE,
    slot SMALLINT NOT NULL CHECK (slot >= 0 AND slot < 20),
    item_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    PRIMARY KEY (player_id, slot)
);

-- Index for loading full inventory
CREATE INDEX IF NOT EXISTS idx_player_inventory_player ON player_inventory(player_id);

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to auto-update updated_at on player_state changes
DROP TRIGGER IF EXISTS update_player_state_updated_at ON player_state;
CREATE TRIGGER update_player_state_updated_at
    BEFORE UPDATE ON player_state
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
