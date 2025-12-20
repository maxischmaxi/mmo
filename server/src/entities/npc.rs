//! Server-side NPC entity.

use mmo_shared::{AnimationState, NpcType};

/// Server-side NPC state
#[derive(Debug)]
pub struct ServerNpc {
    pub id: u64,
    /// Zone this NPC belongs to
    pub zone_id: u32,
    pub npc_type: NpcType,
    pub position: [f32; 3],
    pub spawn_position: [f32; 3],
    pub rotation: f32,
    pub animation_state: AnimationState,
}

impl ServerNpc {
    pub fn new(id: u64, zone_id: u32, npc_type: NpcType, position: [f32; 3], rotation: f32) -> Self {
        Self {
            id,
            zone_id,
            npc_type,
            position,
            spawn_position: position,
            rotation,
            animation_state: AnimationState::Idle,
        }
    }
    
    /// Update NPC (for future roaming behavior)
    /// Currently NPCs are static and just idle
    pub fn update(&mut self, _delta: f32) {
        // Static NPC - always idle
        self.animation_state = AnimationState::Idle;
    }
}
