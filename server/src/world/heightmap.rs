//! Heightmap loading and sampling for terrain height queries.
//!
//! Loads heightmap data exported from Godot's terrain generator.
//! Provides bilinear interpolation for smooth height sampling at any world position.

use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;
use log::{info, warn, error};
use serde::Deserialize;

/// Heightmap metadata structure (matches Godot export format)
#[derive(Debug, Deserialize)]
struct HeightmapMetadata {
    version: u32,
    width: u32,
    height: u32,
    world_min_x: f32,
    world_max_x: f32,
    world_min_z: f32,
    world_max_z: f32,
    terrain_size: f32,
}

/// Heightmap data for a single zone
#[derive(Debug)]
pub struct Heightmap {
    /// Width of the heightmap in pixels
    width: u32,
    /// Height of the heightmap in pixels  
    height: u32,
    /// Minimum world X coordinate
    world_min_x: f32,
    /// Maximum world X coordinate
    world_max_x: f32,
    /// Minimum world Z coordinate
    world_min_z: f32,
    /// Maximum world Z coordinate
    world_max_z: f32,
    /// Raw height data (row-major, Z then X)
    heights: Vec<f32>,
}

impl Heightmap {
    /// Load a heightmap from JSON metadata and binary data files
    pub fn load<P: AsRef<Path>>(json_path: P) -> Result<Self, String> {
        let json_path = json_path.as_ref();
        
        // Load metadata
        let json_file = File::open(json_path)
            .map_err(|e| format!("Failed to open metadata file {:?}: {}", json_path, e))?;
        let reader = BufReader::new(json_file);
        let metadata: HeightmapMetadata = serde_json::from_reader(reader)
            .map_err(|e| format!("Failed to parse metadata {:?}: {}", json_path, e))?;
        
        if metadata.version != 1 {
            return Err(format!("Unsupported heightmap version: {}", metadata.version));
        }
        
        // Derive binary path from JSON path
        let bin_path = json_path.with_extension("bin");
        
        // Load binary height data
        let mut bin_file = File::open(&bin_path)
            .map_err(|e| format!("Failed to open binary file {:?}: {}", bin_path, e))?;
        
        let expected_size = (metadata.width * metadata.height * 4) as usize;
        let mut buffer = vec![0u8; expected_size];
        bin_file.read_exact(&mut buffer)
            .map_err(|e| format!("Failed to read binary data {:?}: {}", bin_path, e))?;
        
        // Convert bytes to f32 (little-endian)
        let heights: Vec<f32> = buffer
            .chunks_exact(4)
            .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
            .collect();
        
        if heights.len() != (metadata.width * metadata.height) as usize {
            return Err(format!(
                "Height data size mismatch: expected {}, got {}",
                metadata.width * metadata.height,
                heights.len()
            ));
        }
        
        info!(
            "Loaded heightmap {}x{} covering world ({}, {}) to ({}, {})",
            metadata.width, metadata.height,
            metadata.world_min_x, metadata.world_min_z,
            metadata.world_max_x, metadata.world_max_z
        );
        
        Ok(Self {
            width: metadata.width,
            height: metadata.height,
            world_min_x: metadata.world_min_x,
            world_max_x: metadata.world_max_x,
            world_min_z: metadata.world_min_z,
            world_max_z: metadata.world_max_z,
            heights,
        })
    }
    
    /// Sample height at a world position using bilinear interpolation
    /// Returns the terrain height at the given (x, z) world coordinates
    pub fn get_height(&self, world_x: f32, world_z: f32) -> f32 {
        // Convert world coordinates to normalized (0-1) coordinates
        let norm_x = (world_x - self.world_min_x) / (self.world_max_x - self.world_min_x);
        let norm_z = (world_z - self.world_min_z) / (self.world_max_z - self.world_min_z);
        
        // Clamp to valid range
        let norm_x = norm_x.clamp(0.0, 1.0);
        let norm_z = norm_z.clamp(0.0, 1.0);
        
        // Convert to pixel coordinates
        let px = norm_x * (self.width - 1) as f32;
        let pz = norm_z * (self.height - 1) as f32;
        
        // Get integer and fractional parts
        let x0 = px.floor() as u32;
        let z0 = pz.floor() as u32;
        let x1 = (x0 + 1).min(self.width - 1);
        let z1 = (z0 + 1).min(self.height - 1);
        let fx = px.fract();
        let fz = pz.fract();
        
        // Sample the four surrounding heights
        let h00 = self.get_pixel_height(x0, z0);
        let h10 = self.get_pixel_height(x1, z0);
        let h01 = self.get_pixel_height(x0, z1);
        let h11 = self.get_pixel_height(x1, z1);
        
        // Bilinear interpolation
        let h0 = h00 * (1.0 - fx) + h10 * fx;
        let h1 = h01 * (1.0 - fx) + h11 * fx;
        h0 * (1.0 - fz) + h1 * fz
    }
    
    /// Get height at a specific pixel coordinate
    fn get_pixel_height(&self, x: u32, z: u32) -> f32 {
        let index = (z * self.width + x) as usize;
        self.heights.get(index).copied().unwrap_or(0.0)
    }
    
    /// Check if a world position is within the heightmap bounds
    pub fn contains(&self, world_x: f32, world_z: f32) -> bool {
        world_x >= self.world_min_x && world_x <= self.world_max_x &&
        world_z >= self.world_min_z && world_z <= self.world_max_z
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_bilinear_interpolation() {
        // Create a simple 2x2 heightmap for testing
        let heightmap = Heightmap {
            width: 2,
            height: 2,
            world_min_x: 0.0,
            world_max_x: 10.0,
            world_min_z: 0.0,
            world_max_z: 10.0,
            heights: vec![0.0, 10.0, 10.0, 20.0], // [0,0]=0, [1,0]=10, [0,1]=10, [1,1]=20
        };
        
        // Test corners
        assert!((heightmap.get_height(0.0, 0.0) - 0.0).abs() < 0.001);
        assert!((heightmap.get_height(10.0, 0.0) - 10.0).abs() < 0.001);
        assert!((heightmap.get_height(0.0, 10.0) - 10.0).abs() < 0.001);
        assert!((heightmap.get_height(10.0, 10.0) - 20.0).abs() < 0.001);
        
        // Test center (should be average of all four = 10)
        assert!((heightmap.get_height(5.0, 5.0) - 10.0).abs() < 0.001);
    }
}
