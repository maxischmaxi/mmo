//! PostgreSQL database operations.

use sqlx::{PgPool, postgres::PgPoolOptions, Row};
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use serde::{Deserialize, Serialize};
use mmo_shared::{CharacterClass, Gender, Empire, CharacterInfo, MAX_CHARACTERS_PER_ACCOUNT, ItemDef, ItemType, ItemRarity, ItemEffect, WeaponStats};
use std::collections::HashMap;

/// Player account data from the database
#[derive(Debug, Clone)]
pub struct PlayerData {
    pub id: i64,
    pub username: String,
    pub password_hash: String,
}

/// Character data from the database (full info)
#[derive(Debug, Clone)]
pub struct CharacterData {
    pub id: i64,
    pub player_id: i64,
    pub name: String,
    pub class: CharacterClass,
    pub gender: Gender,
    pub empire: Empire,
    pub level: i32,
}

/// Player state data for persistence (now per-character)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerStateData {
    pub zone_id: i32,
    pub position_x: f32,
    pub position_y: f32,
    pub position_z: f32,
    pub rotation: f32,
    pub health: i32,
    pub max_health: i32,
    pub mana: i32,
    pub max_mana: i32,
    pub level: i32,
    pub experience: i32,
    pub attack: i32,
    pub defense: i32,
}

impl PlayerStateData {
    /// Create default state based on class and empire
    pub fn new_for_class(class: CharacterClass, empire: Empire) -> Self {
        // Get default zone and spawn position for empire
        let zone_id = match empire {
            Empire::Red => 1,     // Shinsoo Village
            Empire::Yellow => 100, // Chunjo Village
            Empire::Blue => 200,   // Jinno Village
        };
        let spawn = [0.0, 1.0, 0.0]; // Default spawn within zone
        
        let (health, max_health, mana, max_mana, attack, defense) = match class {
            CharacterClass::Ninja => (80, 80, 40, 40, 12, 4),
            CharacterClass::Warrior => (120, 120, 20, 20, 10, 8),
            CharacterClass::Sura => (90, 90, 60, 60, 11, 5),
            CharacterClass::Shaman => (70, 70, 80, 80, 8, 4),
        };
        
        Self {
            zone_id,
            position_x: spawn[0],
            position_y: spawn[1],
            position_z: spawn[2],
            rotation: 0.0,
            health,
            max_health,
            mana,
            max_mana,
            level: 1,
            experience: 0,
            attack,
            defense,
        }
    }
}

impl Default for PlayerStateData {
    fn default() -> Self {
        Self {
            zone_id: 1, // Default to Shinsoo Village
            position_x: 0.0,
            position_y: 1.0,
            position_z: 0.0,
            rotation: 0.0,
            health: 100,
            max_health: 100,
            mana: 50,
            max_mana: 50,
            level: 1,
            experience: 0,
            attack: 10,
            defense: 5,
        }
    }
}

/// Inventory slot data for persistence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InventorySlotData {
    pub slot: i16,
    pub item_id: i32,
    pub quantity: i32,
}

/// Get starter weapon ID for a character class
pub fn get_starter_weapon_id(class: CharacterClass) -> i32 {
    match class {
        CharacterClass::Ninja => 10,    // Shadow Dagger
        CharacterClass::Warrior => 12,  // Steel Claymore
        CharacterClass::Sura => 14,     // Cursed Scimitar
        CharacterClass::Shaman => 16,   // Oak Staff
    }
}

/// Teleport Ring item ID - every player gets one
const TELEPORT_RING_ID: i32 = 100;

/// Get starter items based on character class
/// All classes get a Teleport Ring in addition to their class-specific items
pub fn get_starter_items(class: CharacterClass) -> Vec<InventorySlotData> {
    let starter_weapon = get_starter_weapon_id(class);
    
    match class {
        CharacterClass::Ninja => vec![
            InventorySlotData { slot: 0, item_id: starter_weapon, quantity: 1 },  // Shadow Dagger
            InventorySlotData { slot: 1, item_id: 1, quantity: 10 }, // Health Potions
            InventorySlotData { slot: 2, item_id: TELEPORT_RING_ID, quantity: 1 }, // Teleport Ring
        ],
        CharacterClass::Warrior => vec![
            InventorySlotData { slot: 0, item_id: starter_weapon, quantity: 1 },  // Steel Claymore
            InventorySlotData { slot: 1, item_id: 1, quantity: 5 },  // Health Potions
            InventorySlotData { slot: 2, item_id: TELEPORT_RING_ID, quantity: 1 }, // Teleport Ring
        ],
        CharacterClass::Sura => vec![
            InventorySlotData { slot: 0, item_id: starter_weapon, quantity: 1 },  // Cursed Scimitar
            InventorySlotData { slot: 1, item_id: 1, quantity: 5 },  // Health Potions
            InventorySlotData { slot: 2, item_id: 2, quantity: 5 },  // Mana Potions
            InventorySlotData { slot: 3, item_id: TELEPORT_RING_ID, quantity: 1 }, // Teleport Ring
        ],
        CharacterClass::Shaman => vec![
            InventorySlotData { slot: 0, item_id: starter_weapon, quantity: 1 },  // Oak Staff
            InventorySlotData { slot: 1, item_id: 1, quantity: 3 },  // Health Potions
            InventorySlotData { slot: 2, item_id: 2, quantity: 10 }, // Mana Potions
            InventorySlotData { slot: 3, item_id: TELEPORT_RING_ID, quantity: 1 }, // Teleport Ring
        ],
    }
}

/// Database connection wrapper
#[derive(Clone)]
pub struct Database {
    pool: PgPool,
}

impl Database {
    /// Connect to the database
    pub async fn connect(url: &str) -> Result<Self, sqlx::Error> {
        let pool = PgPoolOptions::new()
            .max_connections(10)
            .connect(url)
            .await?;
        
        Ok(Self { pool })
    }
    
    // =========================================================================
    // Account Operations
    // =========================================================================
    
    /// Register a new player account
    pub async fn register_player(
        &self,
        username: &str,
        password: &str,
    ) -> Result<i64, RegisterError> {
        // Check if username exists
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM players WHERE username = $1)"
        )
            .bind(username)
            .fetch_one(&self.pool)
            .await
            .map_err(|e| RegisterError::Database(e.to_string()))?;
        
        if exists {
            return Err(RegisterError::UsernameTaken);
        }
        
        // Hash password
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();
        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| RegisterError::PasswordHash(e.to_string()))?
            .to_string();
        
        // Insert player account (no default character/state anymore)
        let player_id: i64 = sqlx::query_scalar(
            "INSERT INTO players (username, password_hash) VALUES ($1, $2) RETURNING id"
        )
            .bind(username)
            .bind(&password_hash)
            .fetch_one(&self.pool)
            .await
            .map_err(|e| RegisterError::Database(e.to_string()))?;
        
        Ok(player_id)
    }
    
    /// Authenticate a player
    pub async fn authenticate_player(
        &self,
        username: &str,
        password: &str,
    ) -> Result<i64, AuthError> {
        let row = sqlx::query(
            "SELECT id, password_hash FROM players WHERE username = $1"
        )
            .bind(username)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| AuthError::Database(e.to_string()))?;
        
        let row = row.ok_or(AuthError::InvalidCredentials)?;
        
        let player_id: i64 = row.get("id");
        let stored_hash: String = row.get("password_hash");
        
        // Verify password
        let parsed_hash = PasswordHash::new(&stored_hash)
            .map_err(|e| AuthError::PasswordHash(e.to_string()))?;
        
        Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .map_err(|_| AuthError::InvalidCredentials)?;
        
        Ok(player_id)
    }
    
    /// Update last login timestamp
    pub async fn update_last_login(&self, player_id: i64) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE players SET last_login = NOW() WHERE id = $1")
            .bind(player_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }
    
    // =========================================================================
    // Character Operations
    // =========================================================================
    
    /// Get all characters for a player account
    pub async fn get_characters(&self, player_id: i64) -> Result<Vec<CharacterInfo>, sqlx::Error> {
        let rows = sqlx::query(
            "SELECT c.id, c.name, c.class, c.gender, c.empire, COALESCE(s.level, 1) as level
             FROM characters c
             LEFT JOIN player_state s ON s.character_id = c.id
             WHERE c.player_id = $1
             ORDER BY c.created_at"
        )
            .bind(player_id)
            .fetch_all(&self.pool)
            .await?;
        
        Ok(rows.iter().map(|r| {
            let class_val: i16 = r.get("class");
            let gender_val: i16 = r.get("gender");
            let empire_val: i16 = r.get("empire");
            let level: i32 = r.get("level");
            
            CharacterInfo {
                id: r.get::<i64, _>("id") as u64,
                name: r.get("name"),
                class: CharacterClass::from_u8(class_val as u8).unwrap_or(CharacterClass::Warrior),
                gender: Gender::from_u8(gender_val as u8).unwrap_or(Gender::Male),
                empire: Empire::from_u8(empire_val as u8).unwrap_or(Empire::Red),
                level: level as u32,
            }
        }).collect())
    }
    
    /// Create a new character
    pub async fn create_character(
        &self,
        player_id: i64,
        name: &str,
        class: CharacterClass,
        gender: Gender,
        empire: Empire,
    ) -> Result<CharacterInfo, CharacterError> {
        // Check character count
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM characters WHERE player_id = $1"
        )
            .bind(player_id)
            .fetch_one(&self.pool)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        if count >= MAX_CHARACTERS_PER_ACCOUNT as i64 {
            return Err(CharacterError::MaxCharactersReached);
        }
        
        // Validate name (alphanumeric, max 32 chars)
        if name.is_empty() || name.len() > 32 {
            return Err(CharacterError::InvalidName("Name must be 1-32 characters".to_string()));
        }
        if !name.chars().all(|c| c.is_alphanumeric()) {
            return Err(CharacterError::InvalidName("Name must be alphanumeric only".to_string()));
        }
        
        // Check if name is taken
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM characters WHERE name = $1)"
        )
            .bind(name)
            .fetch_one(&self.pool)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        if exists {
            return Err(CharacterError::NameTaken);
        }
        
        // Start transaction
        let mut tx = self.pool.begin().await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        // Insert character
        let character_id: i64 = sqlx::query_scalar(
            "INSERT INTO characters (player_id, name, class, gender, empire) 
             VALUES ($1, $2, $3, $4, $5) RETURNING id"
        )
            .bind(player_id)
            .bind(name)
            .bind(class.as_u8() as i16)
            .bind(gender.as_u8() as i16)
            .bind(empire.as_u8() as i16)
            .fetch_one(&mut *tx)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        // Create initial state based on class
        let state = PlayerStateData::new_for_class(class, empire);
        sqlx::query(
            "INSERT INTO player_state (character_id, position_x, position_y, position_z, rotation,
                                       health, max_health, mana, max_mana, level, experience, attack, defense)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)"
        )
            .bind(character_id)
            .bind(state.position_x)
            .bind(state.position_y)
            .bind(state.position_z)
            .bind(state.rotation)
            .bind(state.health)
            .bind(state.max_health)
            .bind(state.mana)
            .bind(state.max_mana)
            .bind(state.level)
            .bind(state.experience)
            .bind(state.attack)
            .bind(state.defense)
            .execute(&mut *tx)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        // Give starter items based on class
        let starter_items = get_starter_items(class);
        for item in &starter_items {
            sqlx::query(
                "INSERT INTO player_inventory (character_id, slot, item_id, quantity) VALUES ($1, $2, $3, $4)"
            )
                .bind(character_id)
                .bind(item.slot)
                .bind(item.item_id)
                .bind(item.quantity)
                .execute(&mut *tx)
                .await
                .map_err(|e| CharacterError::Database(e.to_string()))?;
        }
        
        // Create equipment record with starter weapon auto-equipped
        let starter_weapon_id = get_starter_weapon_id(class);
        sqlx::query(
            "INSERT INTO character_equipment (character_id, weapon_slot) VALUES ($1, $2)"
        )
            .bind(character_id)
            .bind(starter_weapon_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        tx.commit().await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        Ok(CharacterInfo {
            id: character_id as u64,
            name: name.to_string(),
            class,
            gender,
            empire,
            level: 1,
        })
    }
    
    /// Delete a character
    pub async fn delete_character(
        &self,
        character_id: i64,
        player_id: i64,
        confirm_name: &str,
    ) -> Result<(), CharacterError> {
        // Verify ownership and name
        let row = sqlx::query(
            "SELECT name FROM characters WHERE id = $1 AND player_id = $2"
        )
            .bind(character_id)
            .bind(player_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        let row = row.ok_or(CharacterError::NotFound)?;
        let actual_name: String = row.get("name");
        
        if actual_name != confirm_name {
            return Err(CharacterError::NameMismatch);
        }
        
        // Delete character (cascade will delete state and inventory)
        sqlx::query("DELETE FROM characters WHERE id = $1")
            .bind(character_id)
            .execute(&self.pool)
            .await
            .map_err(|e| CharacterError::Database(e.to_string()))?;
        
        Ok(())
    }
    
    /// Get full character data (for select)
    pub async fn get_character(&self, character_id: i64, player_id: i64) -> Result<Option<CharacterData>, sqlx::Error> {
        let row = sqlx::query(
            "SELECT c.id, c.player_id, c.name, c.class, c.gender, c.empire, COALESCE(s.level, 1) as level
             FROM characters c
             LEFT JOIN player_state s ON s.character_id = c.id
             WHERE c.id = $1 AND c.player_id = $2"
        )
            .bind(character_id)
            .bind(player_id)
            .fetch_optional(&self.pool)
            .await?;
        
        Ok(row.map(|r| {
            let class_val: i16 = r.get("class");
            let gender_val: i16 = r.get("gender");
            let empire_val: i16 = r.get("empire");
            
            CharacterData {
                id: r.get("id"),
                player_id: r.get("player_id"),
                name: r.get("name"),
                class: CharacterClass::from_u8(class_val as u8).unwrap_or(CharacterClass::Warrior),
                gender: Gender::from_u8(gender_val as u8).unwrap_or(Gender::Male),
                empire: Empire::from_u8(empire_val as u8).unwrap_or(Empire::Red),
                level: r.get("level"),
            }
        }))
    }
    
    // =========================================================================
    // Character State Operations (updated to use character_id)
    // =========================================================================
    
    /// Load character state from database
    pub async fn load_character_state(&self, character_id: i64) -> Result<Option<PlayerStateData>, sqlx::Error> {
        let row = sqlx::query(
            "SELECT zone_id, position_x, position_y, position_z, rotation, 
                    health, max_health, mana, max_mana, 
                    level, experience, attack, defense
             FROM player_state WHERE character_id = $1"
        )
            .bind(character_id)
            .fetch_optional(&self.pool)
            .await?;
        
        Ok(row.map(|r| PlayerStateData {
            zone_id: r.get::<Option<i32>, _>("zone_id").unwrap_or(1),
            position_x: r.get("position_x"),
            position_y: r.get("position_y"),
            position_z: r.get("position_z"),
            rotation: r.get("rotation"),
            health: r.get("health"),
            max_health: r.get("max_health"),
            mana: r.get("mana"),
            max_mana: r.get("max_mana"),
            level: r.get("level"),
            experience: r.get("experience"),
            attack: r.get("attack"),
            defense: r.get("defense"),
        }))
    }
    
    /// Save character state to database
    pub async fn save_character_state(&self, character_id: i64, state: &PlayerStateData) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO player_state (character_id, zone_id, position_x, position_y, position_z, rotation,
                                       health, max_health, mana, max_mana, level, experience, attack, defense)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
             ON CONFLICT (character_id) DO UPDATE SET
                zone_id = EXCLUDED.zone_id,
                position_x = EXCLUDED.position_x,
                position_y = EXCLUDED.position_y,
                position_z = EXCLUDED.position_z,
                rotation = EXCLUDED.rotation,
                health = EXCLUDED.health,
                max_health = EXCLUDED.max_health,
                mana = EXCLUDED.mana,
                max_mana = EXCLUDED.max_mana,
                level = EXCLUDED.level,
                experience = EXCLUDED.experience,
                attack = EXCLUDED.attack,
                defense = EXCLUDED.defense"
        )
            .bind(character_id)
            .bind(state.zone_id)
            .bind(state.position_x)
            .bind(state.position_y)
            .bind(state.position_z)
            .bind(state.rotation)
            .bind(state.health)
            .bind(state.max_health)
            .bind(state.mana)
            .bind(state.max_mana)
            .bind(state.level)
            .bind(state.experience)
            .bind(state.attack)
            .bind(state.defense)
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    /// Load character inventory from database
    pub async fn load_character_inventory(&self, character_id: i64) -> Result<Vec<InventorySlotData>, sqlx::Error> {
        let rows = sqlx::query(
            "SELECT slot, item_id, quantity FROM player_inventory WHERE character_id = $1 ORDER BY slot"
        )
            .bind(character_id)
            .fetch_all(&self.pool)
            .await?;
        
        Ok(rows.iter().map(|r| InventorySlotData {
            slot: r.get("slot"),
            item_id: r.get("item_id"),
            quantity: r.get("quantity"),
        }).collect())
    }
    
    /// Save character inventory to database (replaces all slots)
    pub async fn save_character_inventory(&self, character_id: i64, inventory: &[InventorySlotData]) -> Result<(), sqlx::Error> {
        let mut tx = self.pool.begin().await?;
        
        sqlx::query("DELETE FROM player_inventory WHERE character_id = $1")
            .bind(character_id)
            .execute(&mut *tx)
            .await?;
        
        for slot in inventory {
            sqlx::query(
                "INSERT INTO player_inventory (character_id, slot, item_id, quantity) VALUES ($1, $2, $3, $4)"
            )
                .bind(character_id)
                .bind(slot.slot)
                .bind(slot.item_id)
                .bind(slot.quantity)
                .execute(&mut *tx)
                .await?;
        }
        
        tx.commit().await?;
        Ok(())
    }
    
    // =========================================================================
    // Item Operations
    // =========================================================================
    
    /// Load all items from the database
    pub async fn load_all_items(&self) -> Result<HashMap<u32, ItemDef>, sqlx::Error> {
        let rows = sqlx::query(
            "SELECT id, name, description, item_type, rarity, max_stack, 
                    damage, attack_speed, class_restriction, effects
             FROM items"
        )
            .fetch_all(&self.pool)
            .await?;
        
        let mut items = HashMap::new();
        
        for row in rows {
            let id: i32 = row.get("id");
            let item_type_val: i16 = row.get("item_type");
            let rarity_val: i16 = row.get("rarity");
            let damage: Option<i32> = row.get("damage");
            let attack_speed: Option<f32> = row.get("attack_speed");
            let class_restriction: Option<i16> = row.get("class_restriction");
            let effects_json: serde_json::Value = row.get("effects");
            
            // Parse item type
            let item_type = match item_type_val {
                0 => ItemType::Consumable,
                1 => ItemType::Weapon,
                2 => ItemType::Armor,
                3 => ItemType::Material,
                4 => ItemType::Quest,
                _ => ItemType::Material,
            };
            
            // Parse rarity
            let rarity = match rarity_val {
                0 => ItemRarity::Common,
                1 => ItemRarity::Uncommon,
                2 => ItemRarity::Rare,
                3 => ItemRarity::Epic,
                4 => ItemRarity::Legendary,
                _ => ItemRarity::Common,
            };
            
            // Parse effects from JSON
            let effects = Self::parse_item_effects(&effects_json);
            
            // Parse weapon stats if present
            let weapon_stats = if let (Some(dmg), Some(spd)) = (damage, attack_speed) {
                Some(WeaponStats {
                    damage: dmg as u32,
                    attack_speed: spd,
                    class_restriction: class_restriction.and_then(|c| CharacterClass::from_u8(c as u8)),
                })
            } else {
                None
            };
            
            items.insert(id as u32, ItemDef {
                id: id as u32,
                name: row.get("name"),
                description: row.get("description"),
                item_type,
                rarity,
                max_stack: row.get::<i32, _>("max_stack") as u32,
                effects,
                weapon_stats,
            });
        }
        
        Ok(items)
    }
    
    /// Parse item effects from JSON
    fn parse_item_effects(json: &serde_json::Value) -> Vec<ItemEffect> {
        let mut effects = Vec::new();
        
        if let Some(arr) = json.as_array() {
            for effect in arr {
                if let Some(obj) = effect.as_object() {
                    if let Some(val) = obj.get("RestoreHealth") {
                        if let Some(amount) = val.as_u64() {
                            effects.push(ItemEffect::RestoreHealth(amount as u32));
                        }
                    } else if let Some(val) = obj.get("RestoreMana") {
                        if let Some(amount) = val.as_u64() {
                            effects.push(ItemEffect::RestoreMana(amount as u32));
                        }
                    } else if let Some(val) = obj.get("IncreaseAttack") {
                        if let Some(amount) = val.as_u64() {
                            effects.push(ItemEffect::IncreaseAttack(amount as u32));
                        }
                    } else if let Some(val) = obj.get("IncreaseDefense") {
                        if let Some(amount) = val.as_u64() {
                            effects.push(ItemEffect::IncreaseDefense(amount as u32));
                        }
                    } else if let Some(val) = obj.get("IncreaseSpeed") {
                        if let Some(amount) = val.as_f64() {
                            effects.push(ItemEffect::IncreaseSpeed(amount as f32));
                        }
                    }
                }
            }
        }
        
        effects
    }
    
    // =========================================================================
    // Equipment Operations
    // =========================================================================
    
    /// Load character equipment from database
    pub async fn load_character_equipment(&self, character_id: i64) -> Result<Option<u32>, sqlx::Error> {
        let row = sqlx::query(
            "SELECT weapon_slot FROM character_equipment WHERE character_id = $1"
        )
            .bind(character_id)
            .fetch_optional(&self.pool)
            .await?;
        
        Ok(row.and_then(|r| {
            let weapon_slot: Option<i32> = r.get("weapon_slot");
            weapon_slot.map(|w| w as u32)
        }))
    }
    
    /// Save character equipment to database
    pub async fn save_character_equipment(&self, character_id: i64, weapon_id: Option<u32>) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO character_equipment (character_id, weapon_slot)
             VALUES ($1, $2)
             ON CONFLICT (character_id) DO UPDATE SET
                weapon_slot = EXCLUDED.weapon_slot,
                updated_at = NOW()"
        )
            .bind(character_id)
            .bind(weapon_id.map(|w| w as i32))
            .execute(&self.pool)
            .await?;
        
        Ok(())
    }
    
    // =========================================================================
    // Zone Operations
    // =========================================================================
    
    /// Load all zones from database
    /// Returns: Vec<(id, name, empire, scene_path, is_default_spawn)>
    pub async fn load_zones(&self) -> Result<Vec<(i32, String, Option<i16>, String, bool)>, sqlx::Error> {
        let rows = sqlx::query(
            "SELECT id, name, empire, scene_path, is_default_spawn FROM zones ORDER BY id"
        )
            .fetch_all(&self.pool)
            .await?;
        
        Ok(rows.iter().map(|r| (
            r.get("id"),
            r.get("name"),
            r.get("empire"),
            r.get("scene_path"),
            r.get("is_default_spawn"),
        )).collect())
    }
    
    /// Load all zone spawn points from database
    /// Returns: Vec<(id, zone_id, name, x, y, z, is_default)>
    pub async fn load_zone_spawn_points(&self) -> Result<Vec<(i32, i32, String, f32, f32, f32, bool)>, sqlx::Error> {
        let rows = sqlx::query(
            "SELECT id, zone_id, name, position_x, position_y, position_z, is_default 
             FROM zone_spawn_points ORDER BY zone_id, id"
        )
            .fetch_all(&self.pool)
            .await?;
        
        Ok(rows.iter().map(|r| (
            r.get("id"),
            r.get("zone_id"),
            r.get("name"),
            r.get("position_x"),
            r.get("position_y"),
            r.get("position_z"),
            r.get("is_default"),
        )).collect())
    }
    
    /// Load all zone enemy spawns from database
    /// Returns: Vec<(id, zone_id, enemy_type, x, y, z, respawn_time_secs)>
    pub async fn load_zone_enemy_spawns(&self) -> Result<Vec<(i32, i32, i16, f32, f32, f32, i32)>, sqlx::Error> {
        let rows = sqlx::query(
            "SELECT id, zone_id, enemy_type, position_x, position_y, position_z, respawn_time_secs
             FROM zone_enemy_spawns ORDER BY zone_id, id"
        )
            .fetch_all(&self.pool)
            .await?;
        
        Ok(rows.iter().map(|r| (
            r.get("id"),
            r.get("zone_id"),
            r.get("enemy_type"),
            r.get("position_x"),
            r.get("position_y"),
            r.get("position_z"),
            r.get("respawn_time_secs"),
        )).collect())
    }
}

/// Registration errors
#[derive(Debug)]
pub enum RegisterError {
    UsernameTaken,
    PasswordHash(String),
    Database(String),
}

impl std::fmt::Display for RegisterError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UsernameTaken => write!(f, "Username already taken"),
            Self::PasswordHash(e) => write!(f, "Password hashing failed: {}", e),
            Self::Database(e) => write!(f, "Database error: {}", e),
        }
    }
}

impl std::error::Error for RegisterError {}

/// Authentication errors
#[derive(Debug)]
pub enum AuthError {
    InvalidCredentials,
    PasswordHash(String),
    Database(String),
}

impl std::fmt::Display for AuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidCredentials => write!(f, "Invalid username or password"),
            Self::PasswordHash(e) => write!(f, "Password verification failed: {}", e),
            Self::Database(e) => write!(f, "Database error: {}", e),
        }
    }
}

impl std::error::Error for AuthError {}

/// Character operation errors
#[derive(Debug)]
pub enum CharacterError {
    MaxCharactersReached,
    NameTaken,
    InvalidName(String),
    NotFound,
    NameMismatch,
    Database(String),
}

impl std::fmt::Display for CharacterError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MaxCharactersReached => write!(f, "Maximum characters reached"),
            Self::NameTaken => write!(f, "Character name already taken"),
            Self::InvalidName(msg) => write!(f, "Invalid name: {}", msg),
            Self::NotFound => write!(f, "Character not found"),
            Self::NameMismatch => write!(f, "Character name does not match"),
            Self::Database(e) => write!(f, "Database error: {}", e),
        }
    }
}

impl std::error::Error for CharacterError {}
