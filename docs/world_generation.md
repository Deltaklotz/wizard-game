# World generation pipeline



Everything is generated at startup by `scripts/world/World.gd` (node `World` in `Main.tscn`).

Total build time is about 2–3 s on an RTX 3060, most of it vegetation placement.



## 1. Textures (offline bake)



`tools/bake_textures.gd` renders every material with a compute shader

(`shaders/compute/texture_bake.glsl`) into `textures/*.png` (albedo + normal).

All tiling textures use lattice-periodic noise, so they wrap exactly. The alpha channel of

tiling albedos holds a height value used for height-based blending.



```

Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/bake_textures.gd

```



Set `BAKE_ONLY=rock,grass` to rebake a subset. Materials live in `mat_*` functions in the shader.



## 2. Terrain (GPU, `scripts/terrain/TerrainGenerator.gd`)



| Stage | Shader | What it does |

|---|---|---|

| Noise layers | `terrain_height.glsl` | domain warp, continents, hills, ridged mountain ranges (masked), river valleys, border mountains, detail |

| Coarse erosion | `terrain_erosion.glsl` | droplet hydraulic erosion on a 4x coarser grid -> valleys, drainage, sediment fans (deterministic: droplets read a per-batch snapshot, add integer deltas) |

| Upsample | `terrain_apply_coarse.glsl` | B-spline upsamples the coarse erosion delta onto the full-res noise map |

| Fine erosion | `terrain_erosion.glsl` | short-lived droplets at full res -> small rills |

| Thermal | `terrain_thermal.glsl` | talus slumping -> scree slopes |

| Outcrops | `terrain_outcrop.glsl` | bedrock breaks through on steep/patchy ground: terraced risers and ledges, ridged stone relief, rock mask |

| Finalize | `terrain_finalize.glsl` | float heights + control map (R deposit, G flow, B erosion, A concavity) |



All knobs are in `TerrainSettings.gd`; assign a `.tres` of it to `World.terrain_settings` to

make different worlds (change `seed` for a new map). `tools/preview_terrain.gd` writes a

hillshade + control map PNG without starting the game (`SET="seed=7,coarse_droplets=20000"`

overrides settings).



Rendering (`Terrain.gd`, `shaders/terrain.gdshader`): 64 m chunks in 5 LOD rings (0.5 m to 8 m

vertex spacing) share flat grid meshes displaced by the heightmap in the vertex shader.

Within ~35-75 m of the player a baked detail texture (`detail_albedo.png`: soil bumps,

fractured stone) adds extra displacement that fades out with distance; the fade centre is the

global shader uniform `player_position`, set by `Terrain.gd` each frame. Height and material

logic are shared with the grass in `shaders/include/terrain_common.gdshaderinc`.

The fragment shader picks grass/rock/dirt/moss/snow per pixel: rock switches on sharply on

steep ground and on the risers of outcrop zones, while outcrop ledges keep soil, gravel and moss.

Collision is a single `HeightMapShape3D`. A distant mountain ring hides the map edge.



## 3. Vegetation and greebles (`scripts/vegetation/`)



`VegetationAssets` builds 4 broadleaf + 4 pine tree variants (`TreeGenerator`, 3 LODs each),

8 rocks, 6 boulders and 5 sticks (`RockGenerator`) once. `Vegetation` scatters them using a

forest-mask noise, slope, altitude (pines higher up) and the control map (no trees in stream

beds, rocks on eroded slopes, pebbles on sediment, sticks under trees). Instances are batched

per spatial cell into MultiMeshes with visibility ranges; trunks/boulders get colliders on the

PhysicsServer directly.



Ground cover (`GrassField.gd`, `shaders/grass.gdshader`): layers of short grass, tall grass

bundles, seed grass and three flower types. Each layer is a MultiMesh grid snapped to the

camera; the shader hashes world cells for stable placement, reads terrain height/weights so

cover only grows where the ground is grass, fades with distance, sways in wind and parts

around the player. Tune the `LAYERS` table for spacing, reach, density and clumping.



Trees have three LODs: full (0-60 m), every third card enlarged (60-260 m), and trunk plus

~14 large cards without shadows (260 m+).



## Lake (`scripts/water/`)

`LakeShape.find` scores sites for flatness, low height and absence of rock, then `carve` digs an
irregular basin into the heightmap (with a bank so water can't spill), raises a small island,
and paints mud / wet shore into the control map - before the terrain, collision and scatter are
built, so everything follows it. `Lake` adds the water surface (`shaders/water.gdshader`: depth
colour, refraction, reflections, shore foam), lily pad clusters with the odd flower, reed beds
(plumes and cattails) on a few shore arcs and part of the island, and island trees and rocks.
Vegetation and grass skip anything underwater. Disable with `World.build_lake`.

## 4. Floating islands (`scripts/islands/`)



`IslandField` spreads groups with Poisson-disk spacing and gives each group a composition

(monolith, twins, archipelago, shard spiral, lone) plus extra skyline groups outside the map.

`IslandShape` makes every island unique (outline, cliff, lopsided underside, hanging spires,

gullies, optional rocky crown). `FloatingIsland` adds trees, rocks, hanging roots, underside

crystals, GPU-animated orbiting rocks (`shaders/orbit_rock.gdshader`) and magic motes. Islands

under 12 m radius bob gently.



## World map (`scripts/map/`)

`MapOverlay` (key M, rebindable) shows a hand-drawn relief map over a blurred still of the
paused game; the live 3D world is switched off while it is open. `MapBuilder` makes it from the
world at load time: relief from terrain height percentiles (lake bed pressed in, island raised),
paper inked once through Godot's 2D renderer (`InkCanvas`: parchment shader, hachures, stipple,
shoreline, compass, scale bar), upright billboard trees from real tree positions, floating
islands at their real positions, floating labels, and the player pin.
The pin is `assets/map/player_pin.obj` (map units, tip at the origin) - edit or replace it freely.
Camera feel: `STIFFNESS`, `DAMPING` and `SWAY` in `MapOverlay.gd`.

## Debug tools



`tools/screenshot.gd` renders views to PNG after generation:

`VIEWS="player;x,z,height,yaw,pitch;tree:1:5;island:3:2.5:-0.4" SHOT_DIR=...`

