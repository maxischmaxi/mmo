-- Admin and Currency System Migration
-- Adds is_admin flag to players and gold currency to player_state

-- =============================================================================
-- Add is_admin column to players table
-- =============================================================================

ALTER TABLE players ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;

-- Make existing player ID 1 an admin (first registered account)
UPDATE players SET is_admin = TRUE WHERE id = 1;

-- =============================================================================
-- Add gold column to player_state table
-- =============================================================================

ALTER TABLE player_state ADD COLUMN IF NOT EXISTS gold BIGINT DEFAULT 0;

-- Give existing characters some starting gold
UPDATE player_state SET gold = 100 WHERE gold = 0 OR gold IS NULL;
