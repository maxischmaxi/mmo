//! Persistence layer for the MMO server.
//! 
//! This module handles all database and cache operations in a non-blocking manner.
//! The game loop never blocks on I/O - all persistence happens in a background task.

mod database;
mod cache;

pub use database::{Database, PlayerData, PlayerStateData, InventorySlotData, CharacterData};
pub use cache::Cache;

use tokio::sync::mpsc;
use log::{info, error, warn};

/// Commands sent to the persistence background task
#[derive(Debug)]
pub enum PersistenceCommand {
    /// Save character state to both cache and database
    SaveCharacter {
        character_id: i64,
        state: PlayerStateData,
        inventory: Vec<InventorySlotData>,
    },
    /// Load character data (response sent via oneshot channel)
    LoadCharacter {
        character_id: i64,
        response: tokio::sync::oneshot::Sender<Option<(PlayerStateData, Vec<InventorySlotData>)>>,
    },
    /// Update last login timestamp for account
    UpdateLastLogin {
        player_id: i64,
    },
    /// Flush all dirty data to database (called periodically)
    FlushToDatabase,
    /// Shutdown the persistence task
    Shutdown,
}

/// Handle for sending commands to the persistence task
#[derive(Clone)]
pub struct PersistenceHandle {
    sender: mpsc::Sender<PersistenceCommand>,
}

impl PersistenceHandle {
    /// Save character state (fire and forget - non-blocking)
    pub fn save_character(&self, character_id: i64, state: PlayerStateData, inventory: Vec<InventorySlotData>) {
        let _ = self.sender.try_send(PersistenceCommand::SaveCharacter {
            character_id,
            state,
            inventory,
        });
    }
    
    /// Load character data (async - use sparingly, e.g., on character select)
    pub async fn load_character(&self, character_id: i64) -> Option<(PlayerStateData, Vec<InventorySlotData>)> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        if self.sender.send(PersistenceCommand::LoadCharacter {
            character_id,
            response: tx,
        }).await.is_err() {
            return None;
        }
        rx.await.ok().flatten()
    }
    
    /// Update last login timestamp for account
    pub fn update_last_login(&self, player_id: i64) {
        let _ = self.sender.try_send(PersistenceCommand::UpdateLastLogin { player_id });
    }
    
    /// Request a flush to database
    pub fn flush(&self) {
        let _ = self.sender.try_send(PersistenceCommand::FlushToDatabase);
    }
    
    /// Shutdown the persistence task
    pub async fn shutdown(&self) {
        let _ = self.sender.send(PersistenceCommand::Shutdown).await;
    }
}

/// Initialize the persistence system and spawn the background task.
/// Returns a handle for sending commands.
pub async fn init(
    database_url: &str,
    redis_url: &str,
) -> Result<PersistenceHandle, Box<dyn std::error::Error + Send + Sync>> {
    // Connect to PostgreSQL
    let db = Database::connect(database_url).await?;
    info!("Connected to PostgreSQL");
    
    // Connect to Redis
    let cache = Cache::connect(redis_url).await?;
    info!("Connected to Redis");
    
    // Create channel for commands
    let (tx, rx) = mpsc::channel(256);
    
    // Spawn the background persistence task
    tokio::spawn(persistence_task(db, cache, rx));
    info!("Persistence background task started");
    
    Ok(PersistenceHandle { sender: tx })
}

/// Background task that handles all persistence operations
async fn persistence_task(
    db: Database,
    cache: Cache,
    mut rx: mpsc::Receiver<PersistenceCommand>,
) {
    info!("Persistence task running");
    
    while let Some(cmd) = rx.recv().await {
        match cmd {
            PersistenceCommand::SaveCharacter { character_id, state, inventory } => {
                // Save to Redis cache first (fast)
                if let Err(e) = cache.save_character_state(character_id, &state).await {
                    warn!("Failed to save character {} state to cache: {}", character_id, e);
                }
                if let Err(e) = cache.save_character_inventory(character_id, &inventory).await {
                    warn!("Failed to save character {} inventory to cache: {}", character_id, e);
                }
                
                // Also save to database (permanent storage)
                if let Err(e) = db.save_character_state(character_id, &state).await {
                    error!("Failed to save character {} state to database: {}", character_id, e);
                }
                if let Err(e) = db.save_character_inventory(character_id, &inventory).await {
                    error!("Failed to save character {} inventory to database: {}", character_id, e);
                }
            }
            
            PersistenceCommand::LoadCharacter { character_id, response } => {
                // Try cache first
                let cached_state = cache.load_character_state(character_id).await.ok().flatten();
                let cached_inventory = cache.load_character_inventory(character_id).await.ok().flatten();
                
                let result = if let (Some(state), Some(inventory)) = (cached_state, cached_inventory) {
                    info!("Loaded character {} from cache", character_id);
                    Some((state, inventory))
                } else {
                    // Fall back to database
                    match (
                        db.load_character_state(character_id).await,
                        db.load_character_inventory(character_id).await,
                    ) {
                        (Ok(Some(state)), Ok(inventory)) => {
                            info!("Loaded character {} from database", character_id);
                            // Populate cache for next time
                            let _ = cache.save_character_state(character_id, &state).await;
                            let _ = cache.save_character_inventory(character_id, &inventory).await;
                            Some((state, inventory))
                        }
                        _ => {
                            info!("No saved data for character {}", character_id);
                            None
                        }
                    }
                };
                
                let _ = response.send(result);
            }
            
            PersistenceCommand::UpdateLastLogin { player_id } => {
                if let Err(e) = db.update_last_login(player_id).await {
                    warn!("Failed to update last login for account {}: {}", player_id, e);
                }
            }
            
            PersistenceCommand::FlushToDatabase => {
                // For now, we write through to database on every save
                // In a more optimized version, we'd batch writes here
                info!("Database flush requested (write-through mode, no action needed)");
            }
            
            PersistenceCommand::Shutdown => {
                info!("Persistence task shutting down");
                break;
            }
        }
    }
    
    info!("Persistence task stopped");
}
