//! Chat command system for admin and player commands.

use mmo_shared::{ServerMessage, get_item_definitions};
use crate::entities::ServerPlayer;
use crate::world::GameWorld;

/// Result of executing a command
pub struct CommandResult {
    /// Whether the command was successful
    pub success: bool,
    /// Message to display to the user
    pub message: String,
    /// Optional StatsUpdate message to send if stats changed
    pub stats_update: Option<ServerMessage>,
    /// Optional GoldUpdate message if only gold changed
    pub gold_update: Option<ServerMessage>,
    /// Optional InventoryUpdate if inventory changed
    pub inventory_update: Option<ServerMessage>,
}

impl CommandResult {
    pub fn success(message: impl Into<String>) -> Self {
        Self {
            success: true,
            message: message.into(),
            stats_update: None,
            gold_update: None,
            inventory_update: None,
        }
    }
    
    pub fn error(message: impl Into<String>) -> Self {
        Self {
            success: false,
            message: message.into(),
            stats_update: None,
            gold_update: None,
            inventory_update: None,
        }
    }
    
    pub fn with_stats_update(mut self, player: &ServerPlayer) -> Self {
        self.stats_update = Some(ServerMessage::StatsUpdate {
            level: player.level,
            experience: player.experience,
            experience_to_next_level: player.get_experience_to_next_level(),
            max_health: player.max_health,
            max_mana: player.max_mana,
            attack: player.attack_power,
            defense: player.defense,
            gold: player.gold,
            health: player.health,
            mana: player.mana,
        });
        self
    }
    
    pub fn with_gold_update(mut self, gold: u64) -> Self {
        self.gold_update = Some(ServerMessage::GoldUpdate { gold });
        self
    }
    
    pub fn with_inventory_update(mut self, player: &ServerPlayer) -> Self {
        self.inventory_update = Some(ServerMessage::InventoryUpdate {
            slots: player.get_inventory_slots(),
        });
        self
    }
}

/// Parse and execute a chat command
/// Returns None if it's not a command (doesn't start with /)
pub fn parse_and_execute(
    content: &str,
    player_id: u64,
    is_admin: bool,
    world: &mut GameWorld,
) -> Option<CommandResult> {
    // Check if it starts with /
    if !content.starts_with('/') {
        return None;
    }
    
    // Parse command and arguments
    let parts: Vec<&str> = content[1..].split_whitespace().collect();
    if parts.is_empty() {
        return Some(CommandResult::error("Invalid command"));
    }
    
    let command = parts[0].to_lowercase();
    let args = &parts[1..];
    
    // Execute command
    Some(match command.as_str() {
        // === All player commands ===
        "help" => cmd_help(is_admin),
        "items" => cmd_items(),
        "pos" => cmd_pos(player_id, world),
        
        // === Admin-only commands ===
        "lvl" | "level" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_level(player_id, args, world)
            }
        }
        "hp" | "health" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_hp(player_id, args, world)
            }
        }
        "mp" | "mana" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_mp(player_id, args, world)
            }
        }
        "gold" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_gold(player_id, args, world)
            }
        }
        "god" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_god(player_id, world)
            }
        }
        "kill" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_kill(player_id, args, world)
            }
        }
        "item" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_item(player_id, args, world)
            }
        }
        "tp" | "teleport" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_teleport(player_id, args, world)
            }
        }
        "xp" | "exp" | "experience" => {
            if !is_admin {
                CommandResult::error("This command requires admin privileges")
            } else {
                cmd_xp(player_id, args, world)
            }
        }
        
        _ => CommandResult::error(format!("Unknown command: /{}", command)),
    })
}

// =============================================================================
// All Player Commands
// =============================================================================

fn cmd_help(is_admin: bool) -> CommandResult {
    let mut help = String::from("Available commands:\n");
    help.push_str("  /help - Show this help message\n");
    help.push_str("  /items - List all items with IDs\n");
    help.push_str("  /pos - Show your current position\n");
    help.push_str("  /clear - Clear chat (client-side)\n");
    
    if is_admin {
        help.push_str("\nAdmin commands:\n");
        help.push_str("  /lvl <level> - Set your level\n");
        help.push_str("  /xp <amount> - Set experience points\n");
        help.push_str("  /hp [amount] - Restore HP (full if no amount)\n");
        help.push_str("  /mp [amount] - Restore MP (full if no amount)\n");
        help.push_str("  /gold <amount> - Add gold\n");
        help.push_str("  /god - Toggle invincibility\n");
        help.push_str("  /kill <target_id> - Kill a target\n");
        help.push_str("  /item get <id> [qty] - Add item to inventory\n");
        help.push_str("  /tp <x> <y> <z> - Teleport to coordinates\n");
    }
    
    CommandResult::success(help)
}

fn cmd_items() -> CommandResult {
    let items = get_item_definitions();
    let mut msg = String::from("Items:\n");
    
    for item in items {
        msg.push_str(&format!("  [{}] {} - {}\n", item.id, item.name, item.description));
    }
    
    CommandResult::success(msg)
}

fn cmd_pos(player_id: u64, world: &GameWorld) -> CommandResult {
    if let Some(player) = world.get_player(player_id) {
        CommandResult::success(format!(
            "Position: x={:.2}, y={:.2}, z={:.2} (zone {})",
            player.position[0], player.position[1], player.position[2], player.zone_id
        ))
    } else {
        CommandResult::error("Player not found")
    }
}

// =============================================================================
// Admin Commands
// =============================================================================

fn cmd_level(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if args.is_empty() {
        return CommandResult::error("Usage: /lvl <level>");
    }
    
    let level: u32 = match args[0].parse() {
        Ok(l) if l >= 1 => l,
        _ => return CommandResult::error("Level must be a positive number"),
    };
    
    if let Some(player) = world.get_player_mut(player_id) {
        let old_level = player.level;
        player.level = level;
        player.recalculate_stats_for_level();
        
        CommandResult::success(format!(
            "Level changed from {} to {}. Stats recalculated: HP={}, MP={}, ATK={}, DEF={}",
            old_level, level, player.max_health, player.max_mana, player.attack_power, player.defense
        )).with_stats_update(player)
    } else {
        CommandResult::error("Player not found")
    }
}

fn cmd_hp(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if let Some(player) = world.get_player_mut(player_id) {
        if args.is_empty() {
            // Restore to full
            player.health = player.max_health;
            CommandResult::success(format!("HP restored to {}/{}", player.health, player.max_health))
                .with_stats_update(player)
        } else {
            // Restore specific amount
            let amount: u32 = match args[0].parse() {
                Ok(a) => a,
                Err(_) => return CommandResult::error("Invalid amount"),
            };
            player.health = (player.health + amount).min(player.max_health);
            CommandResult::success(format!("Restored {} HP. Now {}/{}", amount, player.health, player.max_health))
                .with_stats_update(player)
        }
    } else {
        CommandResult::error("Player not found")
    }
}

fn cmd_mp(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if let Some(player) = world.get_player_mut(player_id) {
        if args.is_empty() {
            // Restore to full
            player.mana = player.max_mana;
            CommandResult::success(format!("MP restored to {}/{}", player.mana, player.max_mana))
                .with_stats_update(player)
        } else {
            // Restore specific amount
            let amount: u32 = match args[0].parse() {
                Ok(a) => a,
                Err(_) => return CommandResult::error("Invalid amount"),
            };
            player.mana = (player.mana + amount).min(player.max_mana);
            CommandResult::success(format!("Restored {} MP. Now {}/{}", amount, player.mana, player.max_mana))
                .with_stats_update(player)
        }
    } else {
        CommandResult::error("Player not found")
    }
}

fn cmd_gold(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if args.is_empty() {
        return CommandResult::error("Usage: /gold <amount>");
    }
    
    let amount: i64 = match args[0].parse() {
        Ok(a) => a,
        Err(_) => return CommandResult::error("Invalid amount"),
    };
    
    if let Some(player) = world.get_player_mut(player_id) {
        if amount >= 0 {
            player.gold = player.gold.saturating_add(amount as u64);
        } else {
            player.gold = player.gold.saturating_sub(amount.unsigned_abs());
        }
        
        CommandResult::success(format!("Gold updated. You now have {} gold.", player.gold))
            .with_gold_update(player.gold)
    } else {
        CommandResult::error("Player not found")
    }
}

fn cmd_god(player_id: u64, world: &mut GameWorld) -> CommandResult {
    if let Some(player) = world.get_player_mut(player_id) {
        player.is_invincible = !player.is_invincible;
        if player.is_invincible {
            CommandResult::success("God mode ENABLED. You are now invincible.")
        } else {
            CommandResult::success("God mode DISABLED. You can take damage again.")
        }
    } else {
        CommandResult::error("Player not found")
    }
}

fn cmd_kill(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if args.is_empty() {
        return CommandResult::error("Usage: /kill <target_id>");
    }
    
    let target_id: u64 = match args[0].parse() {
        Ok(id) => id,
        Err(_) => return CommandResult::error("Invalid target ID"),
    };
    
    // Check if it's an enemy
    if world.has_enemy(target_id) {
        if let Some(enemy) = world.get_enemy_mut(target_id) {
            enemy.health = 0;
            return CommandResult::success(format!("Killed enemy {}", target_id));
        }
    }
    
    // Check if it's a player (can't kill self)
    if target_id == player_id {
        return CommandResult::error("You can't kill yourself with this command");
    }
    
    if let Some(target_player) = world.get_player_mut(target_id) {
        target_player.health = 0;
        return CommandResult::success(format!("Killed player {} ({})", target_player.name, target_id));
    }
    
    CommandResult::error(format!("Target {} not found", target_id))
}

fn cmd_item(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if args.is_empty() {
        return CommandResult::error("Usage: /item get <id> [quantity]");
    }
    
    match args[0].to_lowercase().as_str() {
        "get" => {
            if args.len() < 2 {
                return CommandResult::error("Usage: /item get <id> [quantity]");
            }
            
            let item_id: u32 = match args[1].parse() {
                Ok(id) => id,
                Err(_) => return CommandResult::error("Invalid item ID"),
            };
            
            let quantity: u32 = if args.len() >= 3 {
                match args[2].parse() {
                    Ok(q) if q > 0 => q,
                    _ => return CommandResult::error("Quantity must be a positive number"),
                }
            } else {
                1
            };
            
            // Verify item exists
            let item_defs = get_item_definitions();
            let item_name = match item_defs.iter().find(|i| i.id == item_id) {
                Some(item) => item.name.clone(),
                None => return CommandResult::error(format!("Item {} does not exist", item_id)),
            };
            
            if let Some(player) = world.get_player_mut(player_id) {
                if player.add_to_inventory(item_id, quantity) {
                    CommandResult::success(format!("Added {}x {} to inventory", quantity, item_name))
                        .with_inventory_update(player)
                } else {
                    CommandResult::error("Inventory is full")
                }
            } else {
                CommandResult::error("Player not found")
            }
        }
        _ => CommandResult::error("Unknown item subcommand. Use: /item get <id> [quantity]"),
    }
}

fn cmd_teleport(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if args.len() < 3 {
        return CommandResult::error("Usage: /tp <x> <y> <z>");
    }
    
    let x: f32 = match args[0].parse() {
        Ok(v) => v,
        Err(_) => return CommandResult::error("Invalid X coordinate"),
    };
    
    let y: f32 = match args[1].parse() {
        Ok(v) => v,
        Err(_) => return CommandResult::error("Invalid Y coordinate"),
    };
    
    let z: f32 = match args[2].parse() {
        Ok(v) => v,
        Err(_) => return CommandResult::error("Invalid Z coordinate"),
    };
    
    if let Some(player) = world.get_player_mut(player_id) {
        player.position = [x, y, z];
        CommandResult::success(format!("Teleported to ({:.2}, {:.2}, {:.2})", x, y, z))
    } else {
        CommandResult::error("Player not found")
    }
}

fn cmd_xp(player_id: u64, args: &[&str], world: &mut GameWorld) -> CommandResult {
    if args.is_empty() {
        return CommandResult::error("Usage: /xp <amount>");
    }
    
    let amount: u32 = match args[0].parse() {
        Ok(a) => a,
        Err(_) => return CommandResult::error("Invalid XP amount"),
    };
    
    if let Some(player) = world.get_player_mut(player_id) {
        let old_level = player.level;
        let old_xp = player.experience;
        let level_changed = player.set_experience(amount);
        
        let msg = if let Some(new_level) = level_changed {
            format!(
                "XP set to {} (was {}). Level changed from {} to {}. Stats recalculated.",
                amount, old_xp, old_level, new_level
            )
        } else {
            format!(
                "XP set to {} (was {}). Level: {} ({}/{})",
                amount, old_xp, player.level, player.experience, 
                player.get_experience_to_next_level()
            )
        };
        
        CommandResult::success(msg).with_stats_update(player)
    } else {
        CommandResult::error("Player not found")
    }
}
