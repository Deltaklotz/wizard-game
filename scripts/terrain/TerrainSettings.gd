class_name TerrainSettings
extends Resource
## Every knob of the terrain pipeline. Save variants as .tres to get different worlds.

@export var seed: int = 1337
## Heightmap vertices per side. (resolution - 1) must be a multiple of 64 (chunk size).
@export var resolution: int = 1025
@export var cell_size: float = 1.0

@export_group("Noise layers")
@export var base_height: float = 40.0
@export var continent_freq: float = 0.0016
@export var continent_amp: float = 28.0
@export var hill_freq: float = 0.006
@export var hill_amp: float = 30.0
@export var mountain_freq: float = 0.0035
@export var mountain_amp: float = 130.0
@export var mountain_mask_freq: float = 0.0018
@export_range(0.0, 1.0) var mountain_coverage: float = 0.45
@export var warp_freq: float = 0.003
@export var warp_amp: float = 70.0
@export var valley_depth: float = 12.0
@export var border_width: float = 140.0
@export var border_amp: float = 150.0
@export var detail_freq: float = 0.05
@export var detail_amp: float = 1.2

@export_group("Hydraulic erosion")
## Large-scale erosion runs on a grid this many times coarser, carving valleys and drainage.
@export var coarse_factor: int = 4
@export var coarse_droplets: int = 40000
@export var coarse_lifetime: int = 80
@export var coarse_radius: int = 2
## Fine erosion adds small rills on top at full resolution.
@export var fine_droplets: int = 150000
@export var fine_lifetime: int = 30
@export var fine_radius: int = 2
@export var fine_strength: float = 0.4
## Droplets per GPU batch (fine / coarse). Droplets in one batch don't see each other's
## changes (that keeps erosion deterministic), so batches must stay small relative to the grid.
@export var droplet_batch: int = 8192
@export var coarse_batch: int = 1024
@export var height_scale: float = 80.0
@export var inertia: float = 0.3
@export var capacity_factor: float = 0.25
@export var min_capacity: float = 0.0005
@export var erode_speed: float = 0.3
@export var deposit_speed: float = 0.3
@export var evaporate_speed: float = 0.012
@export var gravity: float = 4.0

@export_group("Thermal erosion")
@export var thermal_iterations: int = 30
## Maximum stable slope (rise over run). 0.9 is roughly 42 degrees.
@export var talus: float = 0.9
@export var thermal_rate: float = 0.5

@export_group("Rock outcrops")
@export var outcrops_enabled := true
## Slope (rise over run) where bedrock starts / fully breaks through.
@export var outcrop_slope_start: float = 0.42
@export var outcrop_slope_end: float = 0.62
## How much random patchiness adds outcrops on gentler slopes too.
@export var outcrop_patchiness: float = 0.3
@export var terrace_height: float = 3.5
@export var outcrop_relief: float = 2.2

@export_group("Erosion maps")
@export var erosion_norm: float = 4.0
@export var deposit_norm: float = 3.0
@export var flow_norm: float = 2000.0
@export var concavity_scale: float = 0.6


func world_size() -> float:
	return (resolution - 1) * cell_size
