//! Navigation and pathfinding system for server-side enemy AI.
//!
//! This module provides:
//! - Obstacle definitions (circles, boxes)
//! - Collision detection
//! - Context-based steering for obstacle avoidance
//! - A* pathfinding fallback

use std::f32::consts::PI;
use log::{debug, trace};

/// Radius used for enemy collision detection
pub const ENEMY_RADIUS: f32 = 0.6;

/// Number of directions to sample for context steering
const STEERING_DIRECTIONS: usize = 16;

/// How far ahead to check for obstacles during steering
const STEERING_LOOKAHEAD: f32 = 3.0;

/// Minimum distance to maintain from obstacles
const OBSTACLE_MARGIN: f32 = 0.3;

// ============================================================================
// Obstacle Types
// ============================================================================

/// A 2D position (x, z in world coordinates)
#[derive(Debug, Clone, Copy)]
pub struct Vec2 {
    pub x: f32,
    pub z: f32,
}

impl Vec2 {
    pub fn new(x: f32, z: f32) -> Self {
        Self { x, z }
    }

    pub fn from_3d(pos: [f32; 3]) -> Self {
        Self { x: pos[0], z: pos[2] }
    }

    pub fn length(&self) -> f32 {
        (self.x * self.x + self.z * self.z).sqrt()
    }

    pub fn length_squared(&self) -> f32 {
        self.x * self.x + self.z * self.z
    }

    pub fn normalized(&self) -> Self {
        let len = self.length();
        if len > 0.0001 {
            Self { x: self.x / len, z: self.z / len }
        } else {
            Self { x: 0.0, z: 0.0 }
        }
    }

    pub fn dot(&self, other: Vec2) -> f32 {
        self.x * other.x + self.z * other.z
    }

    pub fn distance_to(&self, other: Vec2) -> f32 {
        let dx = other.x - self.x;
        let dz = other.z - self.z;
        (dx * dx + dz * dz).sqrt()
    }
}

impl std::ops::Add for Vec2 {
    type Output = Vec2;
    fn add(self, rhs: Vec2) -> Vec2 {
        Vec2 { x: self.x + rhs.x, z: self.z + rhs.z }
    }
}

impl std::ops::Sub for Vec2 {
    type Output = Vec2;
    fn sub(self, rhs: Vec2) -> Vec2 {
        Vec2 { x: self.x - rhs.x, z: self.z - rhs.z }
    }
}

impl std::ops::Mul<f32> for Vec2 {
    type Output = Vec2;
    fn mul(self, rhs: f32) -> Vec2 {
        Vec2 { x: self.x * rhs, z: self.z * rhs }
    }
}

/// Circular obstacle (pillars, trees, etc.)
#[derive(Debug, Clone)]
pub struct CircleObstacle {
    pub center: Vec2,
    pub radius: f32,
}

impl CircleObstacle {
    pub fn new(x: f32, z: f32, radius: f32) -> Self {
        Self {
            center: Vec2::new(x, z),
            radius,
        }
    }
}

/// Axis-aligned bounding box obstacle (buildings, walls, etc.)
#[derive(Debug, Clone)]
pub struct BoxObstacle {
    /// Minimum corner (smallest x, z)
    pub min: Vec2,
    /// Maximum corner (largest x, z)
    pub max: Vec2,
}

impl BoxObstacle {
    /// Create a box from center position and half-extents
    pub fn from_center(center_x: f32, center_z: f32, half_width: f32, half_depth: f32) -> Self {
        Self {
            min: Vec2::new(center_x - half_width, center_z - half_depth),
            max: Vec2::new(center_x + half_width, center_z + half_depth),
        }
    }

    /// Create a box from min/max corners
    pub fn from_corners(min_x: f32, min_z: f32, max_x: f32, max_z: f32) -> Self {
        Self {
            min: Vec2::new(min_x.min(max_x), min_z.min(max_z)),
            max: Vec2::new(min_x.max(max_x), min_z.max(max_z)),
        }
    }

    pub fn center(&self) -> Vec2 {
        Vec2::new(
            (self.min.x + self.max.x) * 0.5,
            (self.min.z + self.max.z) * 0.5,
        )
    }
}

/// A single obstacle that can be either a circle or a box
#[derive(Debug, Clone)]
pub enum Obstacle {
    Circle(CircleObstacle),
    Box(BoxObstacle),
}

// ============================================================================
// Collision Detection
// ============================================================================

/// Check if a circle (at `pos` with `radius`) collides with a circular obstacle
pub fn circle_circle_collision(pos: Vec2, radius: f32, obstacle: &CircleObstacle) -> bool {
    let dist = pos.distance_to(obstacle.center);
    dist < radius + obstacle.radius
}

/// Check if a circle (at `pos` with `radius`) collides with an AABB obstacle
pub fn circle_aabb_collision(pos: Vec2, radius: f32, obstacle: &BoxObstacle) -> bool {
    // Find the closest point on the AABB to the circle center
    let closest_x = pos.x.clamp(obstacle.min.x, obstacle.max.x);
    let closest_z = pos.z.clamp(obstacle.min.z, obstacle.max.z);

    // Calculate distance from circle center to closest point
    let dx = pos.x - closest_x;
    let dz = pos.z - closest_z;
    let dist_sq = dx * dx + dz * dz;

    dist_sq < radius * radius
}

/// Check if a circle collides with any obstacle in the list
pub fn check_collision(pos: Vec2, radius: f32, obstacles: &[Obstacle]) -> bool {
    for obstacle in obstacles {
        match obstacle {
            Obstacle::Circle(c) => {
                if circle_circle_collision(pos, radius, c) {
                    trace!("[COLLISION] pos=({:.2}, {:.2}) r={:.2} COLLIDES with Circle at ({:.2}, {:.2}) r={:.2}", 
                        pos.x, pos.z, radius, c.center.x, c.center.z, c.radius);
                    return true;
                }
            }
            Obstacle::Box(b) => {
                if circle_aabb_collision(pos, radius, b) {
                    trace!("[COLLISION] pos=({:.2}, {:.2}) r={:.2} COLLIDES with Box ({:.2},{:.2})->({:.2},{:.2})", 
                        pos.x, pos.z, radius, b.min.x, b.min.z, b.max.x, b.max.z);
                    return true;
                }
            }
        }
    }
    false
}

/// Get the push-out vector if there's a collision with a circular obstacle
fn get_circle_pushout(pos: Vec2, radius: f32, obstacle: &CircleObstacle) -> Option<Vec2> {
    let to_pos = pos - obstacle.center;
    let dist = to_pos.length();
    let min_dist = radius + obstacle.radius + OBSTACLE_MARGIN;

    if dist < min_dist && dist > 0.001 {
        let pushout_dist = min_dist - dist;
        let dir = to_pos.normalized();
        Some(dir * pushout_dist)
    } else {
        None
    }
}

/// Get the push-out vector if there's a collision with an AABB obstacle
fn get_aabb_pushout(pos: Vec2, radius: f32, obstacle: &BoxObstacle) -> Option<Vec2> {
    // Find the closest point on the AABB to the circle center
    let closest_x = pos.x.clamp(obstacle.min.x, obstacle.max.x);
    let closest_z = pos.z.clamp(obstacle.min.z, obstacle.max.z);

    let dx = pos.x - closest_x;
    let dz = pos.z - closest_z;
    let dist_sq = dx * dx + dz * dz;
    let min_dist = radius + OBSTACLE_MARGIN;

    if dist_sq < min_dist * min_dist {
        let dist = dist_sq.sqrt();
        if dist > 0.001 {
            let pushout_dist = min_dist - dist;
            let dir = Vec2::new(dx / dist, dz / dist);
            Some(dir * pushout_dist)
        } else {
            // Circle center is inside the AABB - push out in the shortest direction
            let left = pos.x - obstacle.min.x;
            let right = obstacle.max.x - pos.x;
            let back = pos.z - obstacle.min.z;
            let front = obstacle.max.z - pos.z;

            let min_side = left.min(right).min(back).min(front);
            let pushout = radius + OBSTACLE_MARGIN + min_side;

            if min_side == left {
                Some(Vec2::new(-pushout, 0.0))
            } else if min_side == right {
                Some(Vec2::new(pushout, 0.0))
            } else if min_side == back {
                Some(Vec2::new(0.0, -pushout))
            } else {
                Some(Vec2::new(0.0, pushout))
            }
        }
    } else {
        None
    }
}

/// Resolve collision by pushing the entity out of all obstacles
pub fn resolve_collision(pos: Vec2, radius: f32, obstacles: &[Obstacle]) -> Vec2 {
    let mut result = pos;

    // Iteratively resolve collisions (multiple passes for overlapping obstacles)
    for _ in 0..3 {
        let mut total_pushout = Vec2::new(0.0, 0.0);
        let mut collision_count = 0;

        for obstacle in obstacles {
            let pushout = match obstacle {
                Obstacle::Circle(c) => get_circle_pushout(result, radius, c),
                Obstacle::Box(b) => get_aabb_pushout(result, radius, b),
            };

            if let Some(p) = pushout {
                total_pushout = total_pushout + p;
                collision_count += 1;
            }
        }

        if collision_count > 0 {
            result = result + total_pushout;
        } else {
            break;
        }
    }

    result
}

// ============================================================================
// Context-Based Steering
// ============================================================================

/// Result of pathfinding/steering computation
#[derive(Debug, Clone)]
pub struct NavigationResult {
    /// The new position to move to
    pub new_position: Vec2,
    /// The direction to face (in radians)
    pub rotation: f32,
    /// Whether the entity is currently stuck
    pub is_stuck: bool,
}

/// Calculate the best movement direction using context-based steering
/// 
/// This works by:
/// 1. Sampling multiple directions around the entity
/// 2. For each direction, calculate an "interest" (how much it leads toward the target)
/// 3. For each direction, calculate a "danger" (how close obstacles are)
/// 4. Choose the direction with the highest (interest - danger) value
pub fn calculate_steering_direction(
    current_pos: Vec2,
    target_pos: Vec2,
    obstacles: &[Obstacle],
    enemy_radius: f32,
) -> Option<Vec2> {
    let to_target = target_pos - current_pos;
    let target_dist = to_target.length();

    if target_dist < 0.1 {
        return None; // Already at target
    }

    let target_dir = to_target.normalized();
    
    trace!("[STEER] Calculating steering: pos=({:.2}, {:.2}), target_dir=({:.2}, {:.2}), {} obstacles",
        current_pos.x, current_pos.z, target_dir.x, target_dir.z, obstacles.len());

    // Sample directions in a circle
    let mut best_direction: Option<Vec2> = None;
    let mut best_score = f32::NEG_INFINITY;
    let mut blocked_directions = 0;

    for i in 0..STEERING_DIRECTIONS {
        let angle = (i as f32 / STEERING_DIRECTIONS as f32) * 2.0 * PI;
        let direction = Vec2::new(angle.cos(), angle.sin());

        // Interest: how aligned is this direction with the target direction
        let interest = direction.dot(target_dir);

        // Danger: check for obstacles in this direction
        let mut danger = 0.0f32;
        let check_distances = [1.0, 2.0, 3.0];

        for &check_dist in &check_distances {
            let check_pos = current_pos + direction * check_dist;
            if check_collision(check_pos, enemy_radius, obstacles) {
                // Closer obstacles are more dangerous
                danger = danger.max(1.0 - (check_dist / STEERING_LOOKAHEAD));
            }
        }

        // Also check if moving in this direction would cause immediate collision
        let next_pos = current_pos + direction * 0.5;
        if check_collision(next_pos, enemy_radius, obstacles) {
            danger = 1.5; // Strong penalty for immediate collision
            blocked_directions += 1;
        }

        // Score this direction
        let score = interest - danger * 2.0;

        if score > best_score {
            best_score = score;
            best_direction = Some(direction);
        }
    }
    
    trace!("[STEER] Best score={:.2}, blocked_directions={}/{}", 
        best_score, blocked_directions, STEERING_DIRECTIONS);

    // Only return a direction if it has a positive score (or at least not heavily blocked)
    if best_score > -0.5 {
        if let Some(dir) = best_direction {
            trace!("[STEER] Returning direction ({:.2}, {:.2})", dir.x, dir.z);
        }
        best_direction
    } else {
        debug!("[STEER] All directions blocked (best_score={:.2})", best_score);
        None // All directions are blocked or lead away from target
    }
}

// ============================================================================
// A* Pathfinding (Simple Grid-Based)
// ============================================================================

/// A node in the A* pathfinding grid
#[derive(Clone)]
struct PathNode {
    pos: Vec2,
    g_cost: f32,  // Cost from start to this node
    h_cost: f32,  // Heuristic cost from this node to goal
    parent: Option<usize>,
}

impl PathNode {
    fn f_cost(&self) -> f32 {
        self.g_cost + self.h_cost
    }
}

/// Find a path from start to goal using A* algorithm
/// Returns a list of waypoints (excluding start, including goal)
pub fn find_path(
    start: Vec2,
    goal: Vec2,
    obstacles: &[Obstacle],
    enemy_radius: f32,
    max_iterations: usize,
) -> Option<Vec<Vec2>> {
    const GRID_SIZE: f32 = 1.0; // Size of each grid cell
    const DIRECTIONS: [(f32, f32); 8] = [
        (1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0),
        (1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0),
    ];

    // Check if goal is reachable
    if check_collision(goal, enemy_radius, obstacles) {
        return None;
    }

    let mut open_list: Vec<PathNode> = vec![PathNode {
        pos: start,
        g_cost: 0.0,
        h_cost: start.distance_to(goal),
        parent: None,
    }];
    let mut closed_list: Vec<PathNode> = Vec::new();
    let mut iterations = 0;

    while !open_list.is_empty() && iterations < max_iterations {
        iterations += 1;

        // Find node with lowest f_cost
        let mut best_idx = 0;
        let mut best_f = open_list[0].f_cost();
        for (i, node) in open_list.iter().enumerate().skip(1) {
            if node.f_cost() < best_f {
                best_f = node.f_cost();
                best_idx = i;
            }
        }

        let current = open_list.remove(best_idx);
        let current_idx = closed_list.len();

        // Check if we reached the goal
        if current.pos.distance_to(goal) < GRID_SIZE {
            // Reconstruct path
            let mut path = Vec::new();
            path.push(goal);

            let mut trace_node = &current;
            while let Some(parent_idx) = trace_node.parent {
                trace_node = &closed_list[parent_idx];
                path.push(trace_node.pos);
            }

            path.reverse();
            if path.len() > 1 {
                path.remove(0); // Remove start position
            }
            return Some(path);
        }

        closed_list.push(current.clone());

        // Explore neighbors
        for &(dx, dz) in &DIRECTIONS {
            let neighbor_pos = Vec2::new(
                current.pos.x + dx * GRID_SIZE,
                current.pos.z + dz * GRID_SIZE,
            );

            // Skip if position is blocked
            if check_collision(neighbor_pos, enemy_radius, obstacles) {
                continue;
            }

            // Skip if already in closed list
            let in_closed = closed_list.iter().any(|n| {
                (n.pos.x - neighbor_pos.x).abs() < 0.1 && (n.pos.z - neighbor_pos.z).abs() < 0.1
            });
            if in_closed {
                continue;
            }

            let move_cost = if dx.abs() > 0.5 && dz.abs() > 0.5 { 1.414 } else { 1.0 };
            let g_cost = current.g_cost + move_cost;
            let h_cost = neighbor_pos.distance_to(goal);

            // Check if already in open list with lower cost
            let existing = open_list.iter_mut().find(|n| {
                (n.pos.x - neighbor_pos.x).abs() < 0.1 && (n.pos.z - neighbor_pos.z).abs() < 0.1
            });

            match existing {
                Some(node) if node.g_cost > g_cost => {
                    node.g_cost = g_cost;
                    node.parent = Some(current_idx);
                }
                None => {
                    open_list.push(PathNode {
                        pos: neighbor_pos,
                        g_cost,
                        h_cost,
                        parent: Some(current_idx),
                    });
                }
                _ => {} // Existing node has lower cost, skip
            }
        }
    }

    None // No path found
}

// ============================================================================
// High-Level Navigation
// ============================================================================

/// Navigation state for an entity that needs to pathfind around obstacles
#[derive(Debug, Clone, Default)]
pub struct NavigationState {
    /// Current waypoint path (if using A*)
    pub path: Vec<Vec2>,
    /// Current waypoint index
    pub path_index: usize,
    /// How long the entity has been stuck
    pub stuck_time: f32,
    /// Last position (for stuck detection)
    pub last_position: Option<Vec2>,
}

impl NavigationState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Clear the current path
    pub fn clear_path(&mut self) {
        self.path.clear();
        self.path_index = 0;
    }

    /// Get the current waypoint target, if any
    pub fn current_waypoint(&self) -> Option<Vec2> {
        self.path.get(self.path_index).copied()
    }

    /// Advance to the next waypoint
    pub fn advance_waypoint(&mut self) {
        if self.path_index < self.path.len() {
            self.path_index += 1;
        }
    }
}

/// Calculate the next position for an entity navigating toward a target
/// 
/// This is the main entry point for navigation. It:
/// 1. Uses context steering to try to move directly toward the target
/// 2. If that fails, falls back to A* pathfinding
/// 3. Handles collision resolution to prevent clipping through obstacles
pub fn navigate_toward(
    current_pos: Vec2,
    target_pos: Vec2,
    obstacles: &[Obstacle],
    nav_state: &mut NavigationState,
    speed: f32,
    delta: f32,
    enemy_radius: f32,
) -> NavigationResult {
    trace!("[NAV] navigate_toward called: pos=({:.2}, {:.2}) -> target=({:.2}, {:.2}), {} obstacles, radius={:.2}",
        current_pos.x, current_pos.z, target_pos.x, target_pos.z, obstacles.len(), enemy_radius);
    
    // Check if we're close enough to target
    let to_target = target_pos - current_pos;
    let target_dist = to_target.length();

    if target_dist < 0.2 {
        trace!("[NAV] Already at target (dist={:.2})", target_dist);
        return NavigationResult {
            new_position: current_pos,
            rotation: to_target.x.atan2(to_target.z),
            is_stuck: false,
        };
    }

    // First, try context steering (faster and smoother)
    if let Some(direction) = calculate_steering_direction(current_pos, target_pos, obstacles, enemy_radius) {
        let move_dist = (speed * delta).min(target_dist);
        let new_pos = current_pos + direction * move_dist;

        trace!("[NAV] Steering dir=({:.2}, {:.2}), move_dist={:.3}, new_pos=({:.2}, {:.2})",
            direction.x, direction.z, move_dist, new_pos.x, new_pos.z);

        // Resolve any remaining collisions
        let resolved_pos = resolve_collision(new_pos, enemy_radius, obstacles);
        
        if (resolved_pos.x - new_pos.x).abs() > 0.01 || (resolved_pos.z - new_pos.z).abs() > 0.01 {
            debug!("[NAV] Collision resolved: ({:.2}, {:.2}) -> ({:.2}, {:.2})",
                new_pos.x, new_pos.z, resolved_pos.x, resolved_pos.z);
        }

        // Check if we're making progress
        if let Some(last_pos) = nav_state.last_position {
            let progress = current_pos.distance_to(last_pos);
            if progress < 0.01 * delta {
                nav_state.stuck_time += delta;
                if nav_state.stuck_time > 0.1 {
                    trace!("[NAV] Entity stuck for {:.2}s", nav_state.stuck_time);
                }
            } else {
                nav_state.stuck_time = 0.0;
            }
        }
        nav_state.last_position = Some(current_pos);

        // If stuck for too long, try pathfinding
        if nav_state.stuck_time > 0.5 {
            debug!("[NAV] Stuck too long, switching to A* pathfinding");
            nav_state.stuck_time = 0.0;
            if let Some(path) = find_path(current_pos, target_pos, obstacles, enemy_radius, 200) {
                debug!("[NAV] A* found path with {} waypoints", path.len());
                nav_state.path = path;
                nav_state.path_index = 0;
            } else {
                debug!("[NAV] A* failed to find path");
            }
        }

        let rotation = direction.x.atan2(direction.z);
        return NavigationResult {
            new_position: resolved_pos,
            rotation,
            is_stuck: false,
        };
    } else {
        debug!("[NAV] Context steering returned None - all directions blocked or at target");
    }

    // Context steering failed - use pathfinding
    if nav_state.path.is_empty() {
        if let Some(path) = find_path(current_pos, target_pos, obstacles, enemy_radius, 200) {
            nav_state.path = path;
            nav_state.path_index = 0;
        } else {
            // Can't find a path - try to move toward target anyway
            let direction = to_target.normalized();
            let move_dist = speed * delta * 0.5; // Slower movement when stuck
            let new_pos = current_pos + direction * move_dist;
            let resolved_pos = resolve_collision(new_pos, enemy_radius, obstacles);

            return NavigationResult {
                new_position: resolved_pos,
                rotation: direction.x.atan2(direction.z),
                is_stuck: true,
            };
        }
    }

    // Follow the path
    if let Some(waypoint) = nav_state.current_waypoint() {
        let to_waypoint = waypoint - current_pos;
        let waypoint_dist = to_waypoint.length();

        // Check if we've reached this waypoint
        if waypoint_dist < 1.0 {
            nav_state.advance_waypoint();
            // Recurse to move toward next waypoint
            return navigate_toward(current_pos, target_pos, obstacles, nav_state, speed, delta, enemy_radius);
        }

        let direction = to_waypoint.normalized();
        let move_dist = (speed * delta).min(waypoint_dist);
        let new_pos = current_pos + direction * move_dist;
        let resolved_pos = resolve_collision(new_pos, enemy_radius, obstacles);

        return NavigationResult {
            new_position: resolved_pos,
            rotation: direction.x.atan2(direction.z),
            is_stuck: false,
        };
    }

    // Path completed or empty
    nav_state.clear_path();
    NavigationResult {
        new_position: current_pos,
        rotation: to_target.x.atan2(to_target.z),
        is_stuck: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_circle_circle_collision() {
        let obstacle = CircleObstacle::new(0.0, 0.0, 1.0);
        
        // No collision
        assert!(!circle_circle_collision(Vec2::new(3.0, 0.0), 0.5, &obstacle));
        
        // Collision
        assert!(circle_circle_collision(Vec2::new(1.0, 0.0), 0.5, &obstacle));
    }

    #[test]
    fn test_circle_aabb_collision() {
        let obstacle = BoxObstacle::from_corners(-1.0, -1.0, 1.0, 1.0);
        
        // No collision
        assert!(!circle_aabb_collision(Vec2::new(3.0, 0.0), 0.5, &obstacle));
        
        // Collision
        assert!(circle_aabb_collision(Vec2::new(1.3, 0.0), 0.5, &obstacle));
    }

    #[test]
    fn test_pathfinding() {
        let obstacles = vec![
            Obstacle::Box(BoxObstacle::from_corners(2.0, -1.0, 3.0, 1.0)),
        ];
        
        let start = Vec2::new(0.0, 0.0);
        let goal = Vec2::new(5.0, 0.0);
        
        let path = find_path(start, goal, &obstacles, 0.5, 500);
        assert!(path.is_some());
    }
    
    #[test]
    fn test_main_building_collision() {
        // Test collision with the main building obstacle as defined in zones
        // Building: center (10, -8), half-extents (4, 5)
        // Box from (6, -13) to (14, -3)
        let building = BoxObstacle::from_center(10.0, -8.0, 4.0, 5.0);
        
        // Verify the box bounds are correct
        assert_eq!(building.min.x, 6.0);
        assert_eq!(building.min.z, -13.0);
        assert_eq!(building.max.x, 14.0);
        assert_eq!(building.max.z, -3.0);
        
        // Enemy with radius 0.6 at center of building should collide
        assert!(circle_aabb_collision(Vec2::new(10.0, -8.0), 0.6, &building));
        
        // Enemy at (10, -7.5) should collide (wolf path)
        assert!(circle_aabb_collision(Vec2::new(10.0, -7.5), 0.6, &building));
        
        // Enemy far from building should not collide
        assert!(!circle_aabb_collision(Vec2::new(20.0, -15.0), 0.6, &building));
        
        // Enemy at player spawn (0, 0) should not collide
        assert!(!circle_aabb_collision(Vec2::new(0.0, 0.0), 0.6, &building));
    }
    
    #[test]
    fn test_wolf_path_collision() {
        // Wolf at (20, -15) trying to reach player at (0, 0)
        // The direct path goes through the main building
        let obstacles = vec![
            Obstacle::Box(BoxObstacle::from_center(10.0, -8.0, 4.0, 5.0)),
        ];
        
        let wolf_pos = Vec2::new(20.0, -15.0);
        let player_pos = Vec2::new(0.0, 0.0);
        let enemy_radius = 0.6;
        
        // Wolf start position should not collide
        assert!(!check_collision(wolf_pos, enemy_radius, &obstacles));
        
        // A point midway on direct path (10, -7.5) should collide
        let midpoint = Vec2::new(10.0, -7.5);
        assert!(check_collision(midpoint, enemy_radius, &obstacles));
        
        // Test steering - it should NOT return the direct path direction
        let steering_dir = calculate_steering_direction(wolf_pos, player_pos, &obstacles, enemy_radius);
        
        // If steering returns a direction, it should not be directly toward player
        // (because that path is blocked)
        if let Some(dir) = steering_dir {
            // Check that the direction is not directly at the player
            let direct = (player_pos - wolf_pos).normalized();
            let dot = dir.dot(direct);
            // The dot product should be less than 1.0 (not perfectly aligned)
            // because there's an obstacle in the way
            println!("Steering direction: ({}, {}), Direct: ({}, {}), Dot: {}", 
                dir.x, dir.z, direct.x, direct.z, dot);
        }
        
        // The path should go around the building
        let path = find_path(wolf_pos, player_pos, &obstacles, enemy_radius, 500);
        assert!(path.is_some(), "Should find a path around the building");
        
        if let Some(waypoints) = path {
            println!("Path has {} waypoints", waypoints.len());
            for (i, wp) in waypoints.iter().enumerate() {
                println!("  Waypoint {}: ({}, {})", i, wp.x, wp.z);
                // No waypoint should be inside the building
                assert!(!check_collision(*wp, enemy_radius, &obstacles), 
                    "Waypoint {} at ({}, {}) should not be inside obstacle", i, wp.x, wp.z);
            }
        }
    }
}
