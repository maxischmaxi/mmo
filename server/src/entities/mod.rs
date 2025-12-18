//! Server-side entity definitions.

pub mod player;
mod enemy;
mod item;

pub use player::{ServerPlayer, ActiveBuff, BuffEffect, MAX_LEVEL};
pub use enemy::ServerEnemy;
pub use item::WorldItem;
