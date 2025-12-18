//! MMO Game Server
//! 
//! A simple authoritative game server for the WoW-like MMO prototype.

mod network;
mod world;
mod entities;
mod persistence;

use std::time::{Duration, Instant};
use log::{info, error};
use mmo_shared::{DEFAULT_PORT, SERVER_TICK_RATE};

use crate::network::Server;
use crate::world::GameWorld;
use crate::persistence::{PersistenceHandle, Database};

/// Database URL (matches docker-compose.yml)
const DATABASE_URL: &str = "postgres://mmo:mmo_dev_password@localhost:5433/mmo";

/// Redis URL (matches docker-compose.yml)
const REDIS_URL: &str = "redis://localhost:6380";

/// How often to save player data (in seconds)
const SAVE_INTERVAL_SECS: u64 = 60;

#[tokio::main]
async fn main() {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    info!("Starting MMO Server...");
    info!("Tick rate: {} Hz", SERVER_TICK_RATE);
    info!("Listening on port {}", DEFAULT_PORT);
    
    // Initialize persistence (database + cache)
    let persistence = match persistence::init(DATABASE_URL, REDIS_URL).await {
        Ok(p) => {
            info!("Persistence layer initialized");
            Some(p)
        }
        Err(e) => {
            error!("Failed to initialize persistence: {}", e);
            error!("Server will run without persistence (no login/save)");
            None
        }
    };
    
    // Load items from database
    let items = match Database::connect(DATABASE_URL).await {
        Ok(db) => {
            match db.load_all_items().await {
                Ok(items) => {
                    info!("Loaded {} items from database", items.len());
                    items
                }
                Err(e) => {
                    error!("Failed to load items from database: {}", e);
                    error!("Using fallback hardcoded items");
                    // Fallback to hardcoded items
                    mmo_shared::get_item_definitions()
                        .into_iter()
                        .map(|i| (i.id, i))
                        .collect()
                }
            }
        }
        Err(e) => {
            error!("Failed to connect to database for items: {}", e);
            error!("Using fallback hardcoded items");
            mmo_shared::get_item_definitions()
                .into_iter()
                .map(|i| (i.id, i))
                .collect()
        }
    };
    
    // Create the game world with loaded items
    let mut world = GameWorld::new(items);
    
    // Create the network server
    let mut server = match Server::new(DEFAULT_PORT, persistence.clone()).await {
        Ok(s) => s,
        Err(e) => {
            error!("Failed to start server: {}", e);
            return;
        }
    };
    
    // Calculate tick duration
    let tick_duration = Duration::from_secs_f64(1.0 / SERVER_TICK_RATE as f64);
    let mut last_tick = Instant::now();
    let mut tick_count: u64 = 0;
    
    // Timer for periodic saves
    let mut last_save = Instant::now();
    let save_interval = Duration::from_secs(SAVE_INTERVAL_SECS);
    
    info!("Server started successfully!");
    
    // Main game loop
    loop {
        let tick_start = Instant::now();
        
        // Process incoming network messages
        server.process_incoming(&mut world).await;
        
        // Update game world
        let delta = last_tick.elapsed().as_secs_f32();
        last_tick = Instant::now();
        let world_messages = world.update(delta, tick_count);
        
        // Queue any broadcast messages from world update (enemy deaths, spawns, etc.)
        if !world_messages.is_empty() {
            server.queue_broadcasts(world_messages);
        }
        
        // Send world state to all clients
        server.broadcast_world_state(&world, tick_count).await;
        
        // Process outgoing messages (chat, events, etc.)
        server.process_outgoing(&world).await;
        
        // Periodic save and time sync
        if last_save.elapsed() >= save_interval {
            if let Some(ref persistence) = persistence {
                server.save_all_players(&world, persistence);
                info!("Periodic save complete");
            }
            // Broadcast time sync to all clients (for day/night cycle)
            server.broadcast_time_sync().await;
            last_save = Instant::now();
        }
        
        tick_count += 1;
        
        // Sleep until next tick
        let elapsed = tick_start.elapsed();
        if elapsed < tick_duration {
            tokio::time::sleep(tick_duration - elapsed).await;
        }
    }
}
