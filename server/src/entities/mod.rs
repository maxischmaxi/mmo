//! Server-side entity definitions.

mod player;
mod enemy;
mod item;

pub use player::ServerPlayer;
pub use enemy::ServerEnemy;
pub use item::WorldItem;
