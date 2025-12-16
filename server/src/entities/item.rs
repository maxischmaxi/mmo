//! World item entity (dropped items).

/// An item in the world that can be picked up
#[derive(Debug, Clone)]
pub struct WorldItem {
    pub entity_id: u64,
    pub item_id: u32,
    pub quantity: u32,
    pub position: [f32; 3],
}
