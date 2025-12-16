//! Redis cache operations for hot character data.

use redis::{AsyncCommands, aio::ConnectionManager};
use super::database::{PlayerStateData, InventorySlotData};

/// Cache key prefixes
const CHARACTER_STATE_PREFIX: &str = "char:state:";
const CHARACTER_INVENTORY_PREFIX: &str = "char:inv:";

/// TTL for cached data (1 hour)
const CACHE_TTL_SECONDS: u64 = 3600;

/// Redis cache wrapper
#[derive(Clone)]
pub struct Cache {
    conn: ConnectionManager,
}

impl Cache {
    /// Connect to Redis
    pub async fn connect(url: &str) -> Result<Self, redis::RedisError> {
        let client = redis::Client::open(url)?;
        let conn = ConnectionManager::new(client).await?;
        Ok(Self { conn })
    }
    
    /// Save character state to cache
    pub async fn save_character_state(
        &self,
        character_id: i64,
        state: &PlayerStateData,
    ) -> Result<(), redis::RedisError> {
        let key = format!("{}{}", CHARACTER_STATE_PREFIX, character_id);
        let json = serde_json::to_string(state).unwrap();
        
        let mut conn = self.conn.clone();
        conn.set_ex::<_, _, ()>(&key, json, CACHE_TTL_SECONDS).await?;
        
        Ok(())
    }
    
    /// Load character state from cache
    pub async fn load_character_state(
        &self,
        character_id: i64,
    ) -> Result<Option<PlayerStateData>, redis::RedisError> {
        let key = format!("{}{}", CHARACTER_STATE_PREFIX, character_id);
        
        let mut conn = self.conn.clone();
        let json: Option<String> = conn.get(&key).await?;
        
        Ok(json.and_then(|j| serde_json::from_str(&j).ok()))
    }
    
    /// Save character inventory to cache
    pub async fn save_character_inventory(
        &self,
        character_id: i64,
        inventory: &[InventorySlotData],
    ) -> Result<(), redis::RedisError> {
        let key = format!("{}{}", CHARACTER_INVENTORY_PREFIX, character_id);
        let json = serde_json::to_string(inventory).unwrap();
        
        let mut conn = self.conn.clone();
        conn.set_ex::<_, _, ()>(&key, json, CACHE_TTL_SECONDS).await?;
        
        Ok(())
    }
    
    /// Load character inventory from cache
    pub async fn load_character_inventory(
        &self,
        character_id: i64,
    ) -> Result<Option<Vec<InventorySlotData>>, redis::RedisError> {
        let key = format!("{}{}", CHARACTER_INVENTORY_PREFIX, character_id);
        
        let mut conn = self.conn.clone();
        let json: Option<String> = conn.get(&key).await?;
        
        Ok(json.and_then(|j| serde_json::from_str(&j).ok()))
    }
    
    /// Delete character data from cache (on logout)
    pub async fn delete_character_data(&self, character_id: i64) -> Result<(), redis::RedisError> {
        let state_key = format!("{}{}", CHARACTER_STATE_PREFIX, character_id);
        let inv_key = format!("{}{}", CHARACTER_INVENTORY_PREFIX, character_id);
        
        let mut conn = self.conn.clone();
        conn.del::<_, ()>(&[state_key, inv_key]).await?;
        
        Ok(())
    }
}
