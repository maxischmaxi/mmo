-- Zone System Migration
-- Adds zones, spawn points, and enemy spawns tables
-- Zone ID structure:
--   1-99:    Shinsoo (empire 0)
--   100-199: Chunjo (empire 1)
--   200-299: Jinno (empire 2)
--   300+:    Neutral/Dungeons (future)

-- =============================================================================
-- Zones Table: Zone definitions
-- =============================================================================

CREATE TABLE IF NOT EXISTS zones (
    id INTEGER PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    empire SMALLINT,  -- NULL=neutral, 0=Shinsoo, 1=Chunjo, 2=Jinno
    scene_path VARCHAR(255) NOT NULL,
    is_default_spawn BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for finding default spawn zones by empire
CREATE INDEX IF NOT EXISTS idx_zones_empire_default ON zones(empire, is_default_spawn);

-- =============================================================================
-- Zone Spawn Points Table: Where players can spawn in each zone
-- =============================================================================

CREATE TABLE IF NOT EXISTS zone_spawn_points (
    id SERIAL PRIMARY KEY,
    zone_id INTEGER NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    name VARCHAR(64) DEFAULT 'default',
    position_x REAL NOT NULL DEFAULT 0.0,
    position_y REAL NOT NULL DEFAULT 1.0,
    position_z REAL NOT NULL DEFAULT 0.0,
    is_default BOOLEAN DEFAULT FALSE
);

-- Index for fast lookup of spawn points by zone
CREATE INDEX IF NOT EXISTS idx_zone_spawn_points_zone ON zone_spawn_points(zone_id);

-- =============================================================================
-- Zone Enemy Spawns Table: Enemy spawn definitions per zone
-- =============================================================================

CREATE TABLE IF NOT EXISTS zone_enemy_spawns (
    id SERIAL PRIMARY KEY,
    zone_id INTEGER NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    enemy_type SMALLINT NOT NULL,  -- 0=Goblin, 1=Skeleton, 2=Mutant, 3=Wolf
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    position_z REAL NOT NULL,
    respawn_time_secs INTEGER DEFAULT 60
);

-- Index for loading enemy spawns by zone
CREATE INDEX IF NOT EXISTS idx_zone_enemy_spawns_zone ON zone_enemy_spawns(zone_id);

-- =============================================================================
-- Update player_state to track current zone
-- =============================================================================

ALTER TABLE player_state ADD COLUMN IF NOT EXISTS zone_id INTEGER DEFAULT 1;

-- =============================================================================
-- Seed Data: Initial Zones
-- =============================================================================

-- Empire villages (default spawn locations)
INSERT INTO zones (id, name, empire, scene_path, is_default_spawn) VALUES
(1, 'Shinsoo Village', 0, 'res://scenes/world/shinsoo/village.tscn', TRUE),
(100, 'Chunjo Village', 1, 'res://scenes/world/chunjo/village.tscn', TRUE),
(200, 'Jinno Village', 2, 'res://scenes/world/jinno/village.tscn', TRUE)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    empire = EXCLUDED.empire,
    scene_path = EXCLUDED.scene_path,
    is_default_spawn = EXCLUDED.is_default_spawn;

-- =============================================================================
-- Seed Data: Spawn Points
-- =============================================================================

-- Default spawn points for each village
INSERT INTO zone_spawn_points (zone_id, name, position_x, position_y, position_z, is_default) VALUES
(1, 'default', 0.0, 1.0, 0.0, TRUE),
(100, 'default', 0.0, 1.0, 0.0, TRUE),
(200, 'default', 0.0, 1.0, 0.0, TRUE)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Seed Data: Enemy Spawns (positioned away from spawn point and NPC at 5,0,5)
-- =============================================================================

-- Shinsoo Village enemies
INSERT INTO zone_enemy_spawns (zone_id, enemy_type, position_x, position_y, position_z, respawn_time_secs) VALUES
(1, 0, 25.0, 0.0, 25.0, 60),    -- Goblin
(1, 0, -25.0, 0.0, 15.0, 60),   -- Goblin
(1, 0, 30.0, 0.0, -20.0, 60),   -- Goblin
(1, 2, 0.0, 0.0, 35.0, 90),     -- Mutant
(1, 1, -30.0, 0.0, -30.0, 120), -- Skeleton
(1, 3, 20.0, 0.0, -15.0, 60),   -- Wolf
(1, 3, 25.0, 0.0, -20.0, 60)    -- Wolf
ON CONFLICT DO NOTHING;

-- Chunjo Village enemies
INSERT INTO zone_enemy_spawns (zone_id, enemy_type, position_x, position_y, position_z, respawn_time_secs) VALUES
(100, 0, 25.0, 0.0, 25.0, 60),  -- Goblin
(100, 0, -25.0, 0.0, 20.0, 60), -- Goblin
(100, 1, 35.0, 0.0, 15.0, 120), -- Skeleton
(100, 2, -20.0, 0.0, 30.0, 90), -- Mutant
(100, 3, 30.0, 0.0, -20.0, 60)  -- Wolf
ON CONFLICT DO NOTHING;

-- Jinno Village enemies
INSERT INTO zone_enemy_spawns (zone_id, enemy_type, position_x, position_y, position_z, respawn_time_secs) VALUES
(200, 2, 20.0, 0.0, 30.0, 90),  -- Mutant
(200, 2, -25.0, 0.0, 25.0, 90), -- Mutant
(200, 0, 35.0, 0.0, -15.0, 60), -- Goblin
(200, 1, -35.0, 0.0, 10.0, 120), -- Skeleton
(200, 3, -25.0, 0.0, -20.0, 60) -- Wolf
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Update existing characters to spawn in their empire's default zone
-- =============================================================================

-- Set zone_id based on character's empire for any existing player_state records
UPDATE player_state ps
SET zone_id = CASE 
    WHEN c.empire = 0 THEN 1    -- Shinsoo -> zone 1
    WHEN c.empire = 1 THEN 100  -- Chunjo -> zone 100
    WHEN c.empire = 2 THEN 200  -- Jinno -> zone 200
    ELSE 1
END
FROM characters c
WHERE ps.character_id = c.id;
