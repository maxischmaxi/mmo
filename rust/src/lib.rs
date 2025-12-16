use godot::prelude::*;

mod player;
mod network;

pub use network::NetworkClient;

struct MmoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MmoExtension {}
