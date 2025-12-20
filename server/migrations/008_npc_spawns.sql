-- NPC Spawns Migration
-- Adds NPC spawn definitions per zone

-- =============================================================================
-- Zone NPC Spawns Table: NPC spawn definitions per zone
-- =============================================================================

CREATE TABLE IF NOT EXISTS zone_npc_spawns (
    id SERIAL PRIMARY KEY,
    zone_id INTEGER NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    npc_type SMALLINT NOT NULL,  -- 0=OldMan (more types to come)
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    position_z REAL NOT NULL,
    rotation REAL NOT NULL DEFAULT 0.0
);

-- Index for loading NPC spawns by zone
CREATE INDEX IF NOT EXISTS idx_zone_npc_spawns_zone ON zone_npc_spawns(zone_id);

-- =============================================================================
-- Seed Data: NPC Spawns
-- =============================================================================

-- Old Man NPC in each village (positioned near spawn point but offset)
INSERT INTO zone_npc_spawns (zone_id, npc_type, position_x, position_y, position_z, rotation) VALUES
(1, 0, 5.0, 0.0, 5.0, 0.0),     -- Old Man in Shinsoo Village
(100, 0, 5.0, 0.0, 5.0, 0.0),   -- Old Man in Chunjo Village
(200, 0, 5.0, 0.0, 5.0, 0.0)    -- Old Man in Jinno Village
ON CONFLICT DO NOTHING;
