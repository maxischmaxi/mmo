# MMO Game Prototype

A WoW-style MMO game prototype built with **Godot 4.5** (client) and **Rust** (server + GDExtension).

## Architecture

```
mmo/
├── godot/          # Godot 4.5 game client
├── rust/           # Rust GDExtension (client-side networking & player controller)
├── server/         # Authoritative Rust game server
└── shared/         # Shared protocol definitions (used by both client and server)
```

### Technology Stack

| Component   | Technology                                         |
| ----------- | -------------------------------------------------- |
| Game Client | Godot 4.5 + GDExtension (Rust)                     |
| Game Server | Rust + Tokio (async)                               |
| Networking  | UDP with custom protocol (bincode serialization)   |
| Shared Code | Rust library with serde-based protocol definitions |

## Features

### Implemented

- **Networking**
  - UDP client/server communication
  - Connection handshake with protocol versioning
  - World state synchronization at 20 tick/sec
  - Chat system (broadcast messages)

- **Player System**
  - WoW-style third-person camera controller
    - Right-click + drag: Orbit camera
    - Left-click + drag: Turn character
    - Both buttons: Auto-run forward
    - Mouse wheel: Zoom in/out
  - WASD movement (character-relative, WoW-style)
    - A/D turn character, Q/E strafe
    - Hold right-click to make A/D strafe
  - Sprint (Shift key)
  - Jump physics

- **Targeting System** (WoW-style)
  - Left-click to select enemies/players
  - Tab targeting (cycles by distance)
  - Escape to clear target
  - Target Frame UI showing name, level, health
  - Selection circle visual indicator under target
  - Attack keybind (1) with range checking
  - Combat feedback messages ("Out of range", "No target")
  - Auto-clear target on enemy death

- **Combat System**
  - Click-to-target attacks
  - Damage calculation with critical hits (10% chance, 2x damage)
  - Health bars above entities
  - Floating damage numbers

- **Enemy AI**
  - Three enemy types: Goblin, Skeleton, Wolf
  - Enemy levels (scaled by type, affects HP and damage)
  - Aggro range detection (10 units)
  - Chase behavior
  - Attack range (2 units)
  - Leash/return to spawn (30 units)
  - Idle patrol behavior

- **Items & Inventory**
  - Item definitions (consumables, weapons, armor, materials)
  - Item rarity system (Common to Legendary)
  - Inventory slots
  - Item pickup from world
  - Item use and drop
  - Loot drops from enemies

- **UI**
  - Player HUD (health, mana, name, level)
  - Target Frame (enemy/player info when selected)
  - Chat window
  - Inventory panel
  - World health bars
  - Damage number effects (with object pooling)
  - Combat text feedback (error messages)

## Getting Started

### Prerequisites

- [Godot 4.5](https://godotengine.org/download) (with .NET support not required)
- [Rust](https://rustup.rs/) (stable toolchain)

### Building

1. **Build the shared library:**

   ```bash
   cd shared
   cargo build
   ```

2. **Build the GDExtension (client):**

   ```bash
   cd rust
   cargo build
   ```

3. **Build the server:**
   ```bash
   cd server
   cargo build
   ```

### Running

1. **Start the server:**

   ```bash
   cd server
   cargo run
   ```

   The server will start on port 7777.

2. **Open the Godot project:**
   - Open Godot 4.5
   - Import the project from `godot/project.godot`
   - Press F5 to run the game

3. **Connect to the server:**
   - The client automatically connects to `127.0.0.1:7777` on startup
   - Edit the Player node's `server_address` property to connect to a different server

## Controls

WoW-style controls - movement is relative to **character facing**, not camera.

### Movement

| Key/Button        | Action                                     |
| ----------------- | ------------------------------------------ |
| W                 | Move forward (character facing direction)  |
| S                 | Move backward (character facing direction) |
| A                 | Turn left (rotate character)               |
| D                 | Turn right (rotate character)              |
| Q                 | Strafe left                                |
| E                 | Strafe right                               |
| A/D + Right Mouse | Strafe instead of turn                     |
| Space             | Jump                                       |
| Shift             | Sprint (1.5x speed)                        |

### Camera

| Key/Button         | Action                                          |
| ------------------ | ----------------------------------------------- |
| Right Mouse + Drag | Rotate camera only (character doesn't turn)     |
| Left Mouse + Drag  | Rotate camera AND turn character to face camera |
| Both Mouse Buttons | Auto-run forward in camera direction            |
| Mouse Wheel        | Zoom in/out                                     |

### Targeting

| Key/Button | Action                                     |
| ---------- | ------------------------------------------ |
| Left Click | Select target (enemy or player)            |
| Tab        | Cycle through nearby enemies (by distance) |
| Escape     | Clear current target                       |
| 1          | Attack current target                      |

### UI

| Key/Button | Action           |
| ---------- | ---------------- |
| Enter      | Open chat        |
| I          | Toggle inventory |

## Project Structure

### Godot Client (`godot/`)

```
godot/
├── scenes/
│   ├── main.tscn              # Main game scene
│   ├── player/
│   │   ├── player.tscn        # Local player scene
│   │   └── remote_player.tscn # Other players
│   ├── ui/
│   │   ├── chat.tscn          # Chat window
│   │   ├── inventory.tscn     # Inventory panel
│   │   ├── player_hud.tscn    # Player HUD
│   │   ├── target_frame.tscn  # Target info frame
│   │   ├── combat_text.tscn   # Combat feedback messages
│   │   ├── item_slot.tscn     # Inventory slot
│   │   └── world_health_bar.tscn
│   ├── effects/
│   │   ├── damage_number.tscn # Floating damage numbers
│   │   └── selection_circle.tscn # Target selection indicator
│   └── world/
│       └── zone_1.tscn        # Test zone
├── scripts/
│   ├── game_manager.gd        # Entity management
│   ├── camera_controller.gd   # WoW-style camera + click detection
│   ├── targeting_system.gd    # WoW-style targeting system
│   ├── remote_player.gd       # Remote player interpolation
│   ├── ui/                    # UI scripts
│   │   ├── target_frame.gd    # Target frame logic
│   │   └── combat_text.gd     # Combat feedback display
│   └── effects/
│       └── selection_circle.gd # Selection indicator
└── mmo.gdextension            # GDExtension config
```

### Rust GDExtension (`rust/`)

- `lib.rs` - Extension entry point
- `player.rs` - Player controller (CharacterBody3D)
- `network/client.rs` - UDP network client

### Server (`server/`)

- `main.rs` - Server entry point and game loop
- `network/server.rs` - Client connection handling
- `world/mod.rs` - Game world state and logic
- `entities/` - Server-side entity definitions
  - `player.rs` - Player state and inventory
  - `enemy.rs` - Enemy AI and state
  - `item.rs` - World item entities

### Shared Protocol (`shared/`)

- `protocol.rs` - Client/Server message definitions
- `items.rs` - Item definitions and effects
- `entities.rs` - Shared entity types

## Network Protocol

### Message Flow

```
Client                          Server
   |                              |
   |-- Connect(username) -------->|
   |<-------- Connected(id) ------|
   |                              |
   |-- PlayerUpdate(pos/rot) ---->|  (50ms intervals)
   |<-------- WorldState ---------|  (50ms intervals)
   |                              |
   |-- Attack(target_id) -------->|
   |<-------- DamageEvent --------|
   |                              |
   |-- ChatMessage(text) -------->|
   |<-------- ChatBroadcast ------|
```

### Server Tick Rate

The server runs at **20 ticks per second** (50ms per tick):

- Processes all incoming client messages
- Updates game world (enemy AI, physics)
- Broadcasts world state to all clients
- Processes entity deaths and respawns

## Configuration

### Server Settings (in `shared/src/protocol.rs`)

```rust
pub const PROTOCOL_VERSION: u32 = 1;
pub const SERVER_TICK_RATE: u32 = 20;
pub const DEFAULT_PORT: u16 = 7777;
```

### Player Settings (in Godot editor or `player.tscn`)

| Property            | Default     | Description                     |
| ------------------- | ----------- | ------------------------------- |
| `speed`             | 5.0         | Base movement speed             |
| `jump_velocity`     | 4.5         | Jump strength                   |
| `sprint_multiplier` | 1.5         | Speed multiplier when sprinting |
| `server_address`    | "127.0.0.1" | Server IP to connect to         |
| `username`          | "Player"    | Display name                    |

### Camera Settings (in `camera_controller.gd`)

| Property           | Default | Description              |
| ------------------ | ------- | ------------------------ |
| `min_distance`     | 2.0     | Minimum zoom distance    |
| `max_distance`     | 15.0    | Maximum zoom distance    |
| `default_distance` | 7.0     | Initial camera distance  |
| `rotation_speed`   | 0.3     | Mouse sensitivity        |
| `zoom_speed`       | 1.0     | Scroll wheel sensitivity |

## Development

### Adding New Items

1. Add item definition in `shared/src/items.rs`:

   ```rust
   ItemDef {
       id: 6,
       name: "New Item".into(),
       description: "Description here.".into(),
       item_type: ItemType::Consumable,
       rarity: ItemRarity::Rare,
       max_stack: 10,
       effects: vec![ItemEffect::RestoreHealth(100)],
   }
   ```

2. Handle item effects in `server/src/entities/player.rs`

### Adding New Enemy Types

1. Add variant to `EnemyType` in `shared/src/protocol.rs`
2. Configure stats in `server/src/entities/enemy.rs`
3. Add visual representation in `godot/scripts/game_manager.gd`

### Adding New Messages

1. Add message variant to `ClientMessage` or `ServerMessage` in `shared/src/protocol.rs`
2. Handle sending in `rust/src/network/client.rs`
3. Handle receiving in `server/src/network/server.rs`
4. Process in game logic

## Roadmap

- [ ] Target selection system (Tab targeting, click targeting)
- [ ] Ability/skill system
- [ ] Experience and leveling
- [ ] Equipment system
- [ ] More enemy types and boss encounters
- [ ] Multiple zones with zone transitions
- [ ] Persistent character saves (database)
- [ ] Party system
- [ ] PvP combat
- [ ] Proper character models and animations

## License

This project is a prototype for educational purposes.
