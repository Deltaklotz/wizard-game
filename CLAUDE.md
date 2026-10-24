# Wizard Game

First-person fantasy wizard game in **Godot 4.7.2** (Forward+ renderer, GDScript). Almost everything is
**procedural and built at startup**: terrain, textures (baked offline), trees, rocks, grass, floating sky
islands, a lake, and a hand-drawn relief map. The only hand-authored asset is the map's player pin OBJ.

Deeper pipeline notes: `docs/world_generation.md`.

## Running

The Godot executables live in the project root (not in git):

```bash
./Godot_v4.7.2-stable_win64_console.exe --path .                                   # play
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --import               # (re)import after adding files/shaders
./Godot_v4.7.2-stable_win64_console.exe --headless --path server -- --seed 1234     # multiplayer server (= run_server.bat)
```

Compute shaders need a real GPU: **never use `--headless` for anything that generates the world or bakes
textures** (headless has no RenderingDevice; terrain generation then fails with an error).
Startup builds the world behind a loading screen (~3 s on an RTX 3060).

Main scene is `scenes/Title.tscn` (title → connect page → `Main.tscn`). Running `Main.tscn` directly
(editor F6, dev tools) plays **offline** with `TerrainSettings.seed`.

## Scene layout (`scenes/Main.tscn`)

- `WorldEnvironment` (stylized sky shader, ACES, SSAO+SSIL, glow, aerial fog + height mist, volumetric
  fog for light shafts, saturation boost), `DirectionalLight3D` (warm sun, soft shadows, 250 m),
  `Atmosphere` (`scripts/world/Atmosphere.gd`, cloud noise textures, wind, global uniforms).
- `World` (`scripts/world/World.gd`) – orchestrates generation in `_ready` (async), then places the player.
- `MagicOrb` – decorative glowing sphere moved near the spawn.
- `Player` (CharacterBody3D, `scripts/Player.gd`) → `Camera3D` → `Grimoire` (`scripts/Grimoire.gd`).
  No visible body mesh (the old placeholder capsule was removed: with the interpolated camera trailing the
  body by up to a tick, a dash put the camera behind it). Others see the `PlayerModel` avatar.
- `Hud` (CanvasLayer 5, `scripts/ui/Hud.gd`) – mana/health bars, dash screen effect.
- `PauseMenu` (CanvasLayer, `scripts/ui/PauseMenu.gd`).
- `MapOverlay` (CanvasLayer, `scripts/map/MapOverlay.gd`).
- `RemotePlayers` (`scripts/net/RemotePlayers.gd`) – other players' wizards; returns to title on disconnect.
- `NetHud` (`scripts/ui/NetHud.gd`) – join/leave message feed.
- `InventoryUI` (CanvasLayer 30, `scripts/ui/InventoryUI.gd`) – hotbar + satchel (last in the tree so it
  gets Esc before the pause menu).
- Autoloads `Settings` (`scripts/settings/Settings.gd`), `Net` (`scripts/net/Net.gd`) and `Balance`
  (`scripts/settings/Balance.gd`), in `project.godot`.
- Global shader uniforms in `project.godot [shader_globals]`: `player_position` (set by `Terrain.gd`),
  `cloud_weather` / `cloud_params` / `sun_direction` (set by `Atmosphere.gd`), `world_time` (set by `Net`).

World build order (`World.gd`): terrain generation (or download, see Multiplayer) → lake carve
(`LakeShape`) → start site find + flatten (`StartSite`) → `Terrain` → `StartSite.build` → `Vegetation` +
`GrassField` + `ShroomField` → `Lake` → `IslandField` → `MapOverlay.build(world)` → spawn player on the start site
(spread by player id, facing the pillar); the `MagicOrb` floats above the pillar.

## Systems

### Grimoire (`scripts/Grimoire.gd`, `scripts/Spell.gd`)
- Procedural open book held at the right of the view (no hand – removed on request). Covers, spine with
  bands, headbands, brass corners, clasp strap with a gem, bookmark ribbon, page stacks whose thickness
  follows the current page, and a bending page-flip leaf (`shaders/grimoire_leaf.gdshader`).
- One spell per two-page spread, **10 pages = the hotbar**. `spells: Array[Spell]` (null = blank page). Pages are intentionally
  empty; `Spell.page_texture` / `set_face_texture()` can draw on them later.
- Mouse wheel flips; number keys jump (`go_to_page`). Both set `_target_page`; a flip turns **all** pages
  between current and target at once – one leaf per page (pooled MeshInstances, own material each),
  staggered so they fan over; a single page takes `flip_duration`, any jump ≤ 1.25× that. Wheel ticks
  during a flip add up and the next flip turns the rest together. Left click → `try_cast(caster, dir)`, which checks
  flipping / empty page / cooldown / mana (`has_mana`, `spend_mana` on the player) / `Spell.can_cast()`
  and emits `spell_cast` or `cast_failed(spell, CastBlock)`.
- Sway/bob: `add_look_sway()`, `set_move_amount()` (scaled by the "view_bob" setting).
- **Spell pages = frame + one symbol** (SVGs in `assets/spells/`, symbol centred at 180,255, accents in the
  spell's colour; the old detailed illustrations were dropped on request – no page glow, it looked bad).
  Behind the symbol the page shader draws a procedural **arcane circle** (`arcane_circle` in
  `grimoire_parchment.gdshaderinc`: rings, 8 nodes, rune-tick band, counter-turning hexagram) in the spell's
  `Spell.theme_color` (own colour per spell, not rarity: sniper red, minigun purple, shields light blue, chain
  green-yellow, …). **It shows the cooldown**: `_start_cooldown` spins it at `CIRCLE_START_SPEED` (4 rev/s) and
  it coasts to a stop exactly when the spell is ready (cubic ease-out over the cooldown, like a spun wheel;
  `circle_angle(spell)`, per-spell rest angle kept); `circle_blur` smears it while fast (no strobing); when it
  stops it flashes once in its colour (`circle_flash`, only cooldowns > `FLASH_MIN_COOLDOWN` 3 s). The flip
  leaf draws the circle too (front_/back_circle_*), set in `_apply_face`.
- Pages / flipping leaf light themselves with `page_diffuse` (parchment include): direct light is softly
  compressed – facing away from the sun the near-white paper caught it head-on, bloomed and washed out the ink.

### Player (`scripts/Player.gd`)
Rebindable actions only (no hard-coded keys): move_*, jump, sprint (×1.7), cast, next_page, prev_page,
toggle_map, inventory (Tab), interact (E), page_1..page_10 (number keys 1–0 → `Grimoire.go_to_page`); "pause" is fixed to Esc.
Spell hooks: `move_boost` (speed factor), `slam(speed)` (forced fall), `bounce(v)` (Bounceshroom launch). Mana 100, regen 8/s –
**no regen while casting** (any Grimoire channel, aiming, held fire) **and for `REGEN_DELAY` 1 s after the last
mana spent** (`_regen_wait`); health 100 (`take_damage` / `heal`). `add_lift(dv, max_up)` = upward thrust.
**View angles live in `_yaw` / `_pitch`** and `_apply_look()` writes body = (0, yaw, 0), camera =
(pitch, 0, roll) every frame – never use `rotate_*` on the player/camera (user saw inverted movement and a
skewed view; cause not pinned down, incremental rotations were the suspect). **Camera position is
interpolated** between the last two physics positions every frame (`_place_camera`, `_phys_prev`,
`Engine.get_physics_interpolation_fraction`): the body moves at 60 ticks/s but the view turns per frame, so at
high fps the view stepped/"doubled" while moving (smooth on max settings only because fps ≈ 60). Physics code
writes the eye height to `_cam_y`, never `camera.position` directly. Spawn/respawn use
`set_look()`; pause menu "Reset View" → `reset_view()` (levels view, stops momentum/dash/scope, no teleport). Applies FOV / view distance / sensitivity / invert-Y from Settings; FOV widens +7° while
sprinting and up to +16° during a dash. `STARTING_SPELLS` fills the grimoire pages (dash, sniper, chain, sword wall, minigun, dome, hex ward, black hole, fireball, inferno). `cast_direction`
is what `Net.send_cast` sends (view direction by default; a spell may overwrite it in `cast()`).
The `hit` event may carry extras the target applies: `burn` + `bdps` (→ `ignite`) and `push` (→ `add_knockback`).

### Spells (`scripts/spells/`, resources in `spells/`, page art in `assets/spells/`)
- A spell = `Spell` subclass script + `.tres` (must be a saved resource so remotes can `load()` it) +
  optional editable SVG page artwork (`page_texture`, ink on transparent, 360×510).
- **Dash** (`DashSpell`, `spells/dash.tres`: 20 mana, 0.8 s cooldown, 9 m in 0.24 s): straight along the
  view direction (up/down included). `Player.start_dash` suspends gravity, runs a speed profile
  (full → 30 % over the last 45 %), then carries 35 % as decaying horizontal momentum (+ a little upward
  velocity after upward dashes). `dash_fx` (0..1) drives FOV,
  view lean, book trailing and the HUD screen effect.
- `DashFx` (shared by local cast and `cast_remote`): ground rune circle + upright shockwaves
  (`shaders/vfx/spell_ring.gdshader`, `instance uniform progress`), spark burst, flash light (remote only –
  it blew out the held book), a ring ahead of the eyes to burst through (local), arrival puff.
  `DashTrail`: first person = soft motes spawned in a ring ~5 m ahead that the player rushes through
  (screen speed lines and first-person streaks were removed on request – felt unpleasant); remote = streak/mote comet tail + afterimages (`dash_ghost.gdshader` on
  `RemotePlayer.get_body_mesh()`). Particles: `spell_particle.gdshader` (additive, streak or billboard mote).
- `SpellFx` (shared helpers: effect roots, `ring`, `particles`, `flash`) + `SpellFx.prewarm` renders
  every spell's effects once in an offscreen SubViewport during loading (called from `Player._ready`) –
  without it the first cast stalls on shader/pipeline compilation. Add new spells' effects there.
- **Aimed spells** (`Spell.aimed`, `min_aim_time`, `aim_zoom`, `aim_move_factor`): press cast →
  `Grimoire.start_aim` (checks mana/cooldown, spends on fire), release → `release_aim`; it fires once
  `min_aim_time` is reached (an early release waits – no quick-scopes). Page flips are blocked while
  aiming; opening a menu cancels. `Player.scope` (0..1) drives zoom (true magnification via tan), slower
  mouse, slower movement, the book dropping out of view and the HUD scope overlay.
- **Sniper Beam** (`SniperSpell`, `spells/sniper.tres`, page 2: 45 mana, 1.5 s cooldown, 2 s minimum aim,
  4× zoom, 70 damage, 2 km range). Hitscan decided by the shooter: physics ray vs. world + capsule test
  vs. `RemotePlayer` avatars; a hit sends event `{"kind": "hit", "target", "damage"}` which the target's
  `Player` applies (`take_damage` → `damaged` / `died` signals). Cast message carries direction × beam
  length so replays end where the shot did. `SniperFx`: 3 nested cylinders (`sniper_beam.gdshader`:
  core / glow with pulses / two spiral strands), motes along the beam, streaks racing down it, muzzle
  rings (not in first person – they filled the zoomed view), impact rune ring + shockwaves + sparks +
  embers + flash scaled with viewer distance. While aiming, others see a spinning red crosshair
  (`sniper_crosshair.gdshader`, charge arc) in front of the shooter's eyes (`FLAG_AIMING`, pitch now
  interpolated in `RemotePlayer`).
- **Spectral Chain** (`ChainSpell`, `spells/chain.tres`, page 3: 1 mana per 3 m while growing, `mana_cost` 4 =
  minimum to start, holding is free). `ChainCast` (local) grows the head at 32 m/s, turning at most
  `turn_rate` towards the crosshair point (steerable mid-flight) + noise wander; homes onto players /
  `chainable` nodes within 5 m (in sight). Hit a surface → `ANCHORED` (grapple: `Player.set_pull("grapple")`);
  hit a player / chainable → `TOWING`. Chain straightens on attach (`ChainCast.straighten`). Snaps (burst)
  on cast pressed again (`Grimoire` channel: `begin_channel`/`cancel_channel`, flips blocked), out of mana,
  > 70 m, caster death or being overpowered `ChainSpell.BREAK_TIME` 3 s; fades quietly on arrival /
  target lost / stuck. **Pulls are forces on the pulled body** (`Player._update_pulls`): velocities summed
  with the body's own motion; a pull is "overpowered" while own motion + other pulls leave it < 25 % of its
  speed along the chain (sprint away = slowed only, a dash or own chain the opposite way = overpowered).
  Pull speed 13 m/s (sprint 8.5, dash ~45). The towed player's own client applies the pull (event
  `{"kind": "chain", "st", "pts", "tg", "sp"}` ~15×/s from the caster) and answers `chain_break` when it broke
  free; `chain_end` ends it everywhere. Remotes draw it with `ChainRemote` (avatar hand =
  `RemotePlayer.get_hand_position`). Visual `ChainFx`: one procedural link mesh in a MultiMesh laid from
  the far end back (feeds out of the book / reels in at the hand), `chain_link.gdshader` (translucent
  ghost, fresnel rim), burst = links tumble ~1.5 m and fade + sparks. HUD `chain_screen.gdshader`: quick (~0.3 s), thin
  border of chain links at the moment of the grab only (caster: `chain_caught`, also for chainables;
  caught player: `chained`); no effect while being pulled.
  Future monsters/items: join group `chainable`, implement `get_chain_point()` and
  `chain_pull(dir, speed, delta)` (optional `get_chain_overpower()`).
- **Sword Wall** (`SwordSpell`, `spells/sword.tres`, page 4: 35 mana, 6 s cooldown, 40 damage, 38 s
  lifetime). Aimed without scope (`Spell.aim_scope` = false; only the sniper sets it – it gates zoom, HUD
  lens, sprint block and `FLAG_AIMING`). While held, `Spell.make_preview` → `SwordPreview` (golden ghost
  sword + footprint `Decal`, freed by the Grimoire when the aim ends). `find_landing`: crosshair hit (or max
  range) clamped to 5–45 m horizontally, dropped onto the ground, ignoring existing walls. `SwordWall`
  (all clients; cast message = landing point as origin + direction, facing = that vector flattened):
  rune ring + footprint on the ground while it falls 140 m in 0.9 s, impact FX, `StaticBody3D` (group
  `sword_wall`: blade box, guard box, hilt cylinder), vibration, then a noise dissolve. A player it lands
  on is damaged and shoved out (`Player.add_knockback`) by their **own** client; the local caster only gets
  hit markers. `Player.add_shake` for players within 30 m. Model `SwordModel` (procedural, cached
  ArrayMesh): lens-section blade with edge bevel + fuller (13 m, 6 m wide, 3.8 m visible above ground),
  scroll crossguard, gem collar, banded grip, crowned pommel; `shaders/vfx/sword.gdshader` (`part`
  0 blade / 1 gold / 2 gems, instance uniforms `dissolve`, `glow`), preview `sword_ghost.gdshader`.
- **Arcane Minigun** (`MinigunSpell`, `spells/minigun.tres`, page 5: 1 mana + 1 damage per orb, purple/blue).
  `Spell.hold_fire`: while cast is held, `Player` calls `spell.hold()` every frame (no single cast); the
  spell's `MinigunRig` (child of the Player, top_level, follows the camera, only while its page is open)
  spins up (0.45 s), fires via `Grimoire.try_cast` at 7→14 shots/s, heat +1 per shot, cools 22/s after
  0.3 s off the trigger, rig drawn bottom centre of the view (camera space, clear of the book), overheats at 100 → 5 s vent (no firing, steam/sparks, heat drains). Spread grows
  with heat. Orbs `MagicBolt` (50 m/s, one 2-quad mesh: camera-facing swirl orb + axial streak, shader
  `magic_bolt.gdshader` with `world_vertex_coords`), traced per physics step; shooter sends `hit` events.
  Every orb is a cast message; remotes replay visual-only orbs + muzzle flash (`Spell.cast_gesture` =
  false skips the avatar's cast animation, `Spell.cast_kick` keeps the book still). HUD: `heat_gauge.gdshader`
  arc around the crosshair (heat right, spin left) + "OVERHEATED" label. Damage flashes scale with the
  amount now (1-damage hits only flicker).
- **Hex shields** (`Shield` base, `HexShieldMesh`, `shaders/vfx/hex_shield.gdshader`): tile meshes carry per-tile
  centre/random (CUSTOM0), tile UVs and rim/reveal order (UV2) so the shader reveals, ripples (6 recent hits,
  set from CPU with ages), cracks (jagged branching lines, more tiles as `damage` rises, flicker when
  critical) and shatters (tiles fly out along their normals) per tile. Bodies on `Shield.LAYER` (layer 5):
  players don't collide (mask 1), every spell trace does. Own shots pass the own Hex Ward
  (`Shield.excludes_for(owner)`), but **domes block everyone's shots incl. the owner's**, also from inside
  (`Shield.dome_exit` – physics rays ignore a shape they start in); aiming rays pass all own shields
  (`excludes_for(owner, true)`). Shared shader look: energy waves sweeping in reveal order, glinting tiles,
  inner hex outlines, `tint` gradient, struck tiles dent in (`dent`); `Shield._hit_fx` sparks + ring
  (≤ 1 per 50 ms). Shooter decides shield hits → `report_hit` → event `shield_hit` (all clients
  apply); owner ends with `shield_end` {shield, broke}. Sniper/minigun are blocked, a chain grapples onto a
  shield, the sword's ground ray uses mask 1.
  - **Aegis Dome** (`ShieldBubbleSpell`/`ShieldDome`, page 6: 40 mana, 12 s cooldown, 150 HP, `lifetime` 120 s (owner
    ends it → `shield_end`; also until broken / recast / owner leaves); **a Sword Wall landing on it shatters it**
    (`SwordWall._shatter_domes`, footprint vs. radius, run by every client), r 7.2 m, 4× subdivided):
    Goldberg dome (dual of a 3× subdivided icosahedron) rising from the ground at the caster's feet,
    stationary, sphere collider (rays from inside pass out); fades to 35 % while the camera is inside;
    turning rune circle at its base + motes drifting up the surface.
  - **Hex Ward** (`ShieldWallSpell`/`ShieldWall`, page 7: free to raise and hold): Grimoire channel – cast
    again lowers it, wheel = rings 0–4 (1/7/19/37/61 tiles, `Player` routes wheel to `channel.scroll()`).
    Mana only when blocking: 1.0 × (1 + 0.5 × rings) per damage point (ring 4 = 3/point), no regen while up
    (channel); a blow it can't pay for shatters it. Size remembered for the next raise (`ShieldWall.last_rings`,
    sent deferred as `shield_wall` so it arrives after the cast message). Flat grid 1.7 m + 0.5 m per ring in front of the eyes (remote: avatar eye + `RemotePlayer.get_look_direction()`), cylinder
    collider; owner sees it at 45 % opacity. Remote ring changes via event `shield_wall`.
- **Event Horizon / black hole** (`BlackHoleSpell`, `BlackHole`, page 8: all mana (≥ 50), 120 s cooldown, 30 s).
  Sequence: spark (`bh_spark.gdshader`) drifts up in a fairy spiral 3.2 s to 45 m above / 6 m ahead of
  the caster → CHARGE 1.5 s (swells, spins ever faster, shrinks to a point) → hole manifests (flash,
  rings, opens over 0.45 s) → ACTIVE → collapse + final flash. `black_hole.gdshader` on the inside of a
  sphere (22 rs): per-pixel Schwarzschild ray march (shadow, photon ring, lensed far side of the disk),
  bending faded out beyond `lens_fade` rs; accretion disk to 20 rs = 5 flared, lumpy layers (crossings
  composited front to back), each dark absorbing gas (darkens the background) + bright ridged-noise
  streaks, flow-blended so it streams round; subtle beaming; fades out within 8–32 m of the viewer
  (otherwise its near side fills the screen up close / underneath). Background read from the screen
  (mip 0 only – mips are dark where foliage is cut). **Disk orientation is per viewer**
  (`_orient_disk`: 8° above the plane, rolled −16° on screen; when looking steeply up/down the screen-up
  reference is held from the previous frame and the normal slerps, so it doesn't spin underneath).
  Infall/debris particles `bh_infall.gdshader`. Gameplay per client: `Player.set_pull("black_hole_<id>")`
  with speed ramping 9→32 m/s over its life, falloff (1 − d/110)², kill within 1.35 rs; caster immune.
  **"Fancy black hole" setting off** (`fancy_black_hole`, Very Low/Low presets): no ray march – `black_hole_lens.gdshader`
  (camera-facing quad, thin-lens warp `b − E²/b` with one screen read, shadow, photon ring, lensed far-disk arc
  thin secondary image under the shadow) + `black_hole_disk.gdshader` (subdivided PlaneMesh in the per-viewer
  disk basis, tilted 14° instead of 8° since it has no thickness; **far-half vertices are lensed in the vertex
  shader** to their primary image θ = (β + √(β²+4E²))/2 in camera-angle units, minus `arc_pull`/θ so the arc
  hugs the photon ring – that bends the far disk up over the shadow in one piece; cutting it out left gaps),
  shared noise in `bh_lite_common.gdshaderinc`; infall particles behind / near the shadow hidden via
  `spell_particle.gdshader`'s `hole` uniform; HUD uses 6 roots. Switches live (`_build_visual`), both prewarmed.
  Cost on an RTX 3060: fancy +8–24 ms (the viewer is usually *inside* its 59 m sphere), simple ≈ +0–1.5 ms.
  HUD `black_hole_screen.gdshader`: soft CA mask (no tint) = edge band + 16 roots, wide at the edge, tapering,
  forking, writhing; the colour split eases in with the mask; roots creep in
  from the screen edges with `BlackHole.screen_intensity()`.
- **Fireball** (`FireballSpell`, `Fireball`, `FirePatch`, `FireFx`, page 9: 30 mana, 1.2 s cooldown, Eldritch).
  Thrown at the crosshair point at 38 m/s, falls under its own gravity 7 m/s² (the drop-off), traced per
  physics step (world, shields incl. `dome_exit`, player capsules). Shooter decides the impact → event
  `{"kind": "fireball", "p", "n"}`; every client runs `Fireball.explode` (blast fx, damage 45 → 10 over
  4 m to its own player – caster takes 50 %, none through a dome – knock-back, shake, hit markers for the
  caster, ends the matching visual replay) and lays a `FirePatch` (r 4 m, 7 s) + scorch decal on the ground
  below. Standing in the fire → `Player.ignite(burn_time, burn_dps, by)`: 8 dps for 3.5 s, refreshed while
  inside, water puts it out; `FLAG_BURNING` → `RemotePlayer` shows flames on the body; HUD
  `burn_screen.gdshader` (flames rising from the bottom and sides). Shaders: `fireball_core` (swirling
  ball), `fire_flame` (alpha-blended torn teardrop particles for explosion/trail/licks – additive washed
  out to white in daylight), `fire_smoke` (tinted by particle colour: lit orange low, grey higher).
  **FirePatch layers**: ember bed = disc mesh draped over the ground by raycasts (`ember_bed.gdshader`:
  charcoal, Voronoi glowing cracks, drifting hot spots, ragged edge); ~30 flame **sheets** (Y-billboard
  quads rooted on the ground, `fire_sheet.gdshader`: domain-warped fbm scrolling up, density beats a
  height-rising threshold → torn tongues, blackbody colour, only hot cores pushed to HDR – earlier
  versions were white gumdrops; depth-soft at the ground; instance `strength` shrinks them as it
  dies); turbulent rising embers; smoke column; `heat_haze.gdshader` billboards; two flickering lights. Use the sine-free hash in noise shaders (the sin() hash turns blocky at large coords).
- **Infernal Torrent** (`InfernoSpell`, `InfernoBeam`, `spells/inferno.tres`, page 10: 60 mana, 14 s cooldown,
  Celestial). Look follows a hand-drawn anime hellfire reference: crimson flame, black smoke with indigo
  patches, red-rimmed cel edges, pale rose crescent slashes, dashed white sparks. Phases: CHARGE 0.55 s
  (sigil + embers sucked in + whirling crescents) → FIRE 3 s (erupt: shockwaves, spark burst, flash; the
  head shoots out at 230 m/s to the first surface or 90 m and follows the aim with `turn_rate` lag;
  Grimoire channel – cast again cuts it short) → FADE 0.8 s (the tail flies off via `cut`,
  shapes erode). Cone radius `muzzle_radius` + `spread`·d (0.35 + 0.21/m). Visuals: 3 nested **opaque
  alpha-scissor** cone shells on one unit tube mesh (`inferno_shell.gdshader`: layer 0 smoke / 1 flame /
  2 core; noise in log-radius coordinates so shapes grow and stream outwards; rounded head; erosion by
  `intensity`, `cut`, open end, near the camera, inside faces and `aim_clear` around the view centre for
  the caster) – the scissor gives hard anime edges and correct depth sorting; additive haze
  `inferno_glow`; world-space cel billows `inferno_puff` (also scissor; they bend away when the caster
  sweeps); crescents = MultiMesh of one helix arc, `inferno_slash.gdshader` widens the line towards the
  camera (NORMAL holds the tangent), hooked barbs on the outer edge; `inferno_spark` dashed streaks;
  impact splash/smoke/sparks sized by the cone radius there + `FireFx.scorch` marks; red lights along it.
  **Keep the cel colours at ≤ ~1.5 HDR and `fog_disabled`** – brighter reds turned pink under ACES, fog
  washed them to salmon. Gameplay (the caster decides every 0.2 s): players within 0.8 × the radius with
  a clear ray from the muzzle get `hit` events with `burn`/`bdps` and `push`; a shield on the axis takes
  the damage, domes block (`dome_exit`); the caster is pushed back gently and, aimed at the ground, lifted like a
  rocket (`lift` 24 m/s² × down^1.5, none when level, capped at `lift_max_speed` 12 m/s → `Player.add_lift`). Remotes follow
  `RemotePlayer.get_hand_position` / `get_look_direction` and end on event `inferno_end` / caster death.
  HUD `inferno_screen.gdshader` (smoke curling in from the edges + crimson grade) only for players caught
  inside someone's torrent (`InfernoBeam.screen_intensity`) – and not when a shield / wall stands between the
  axis and the camera (`_sheltered`: ray + `dome_exit`). Smoke/flame/spark particles are cut where the beam
  currently ends (`beam_origin/dir/len` uniforms on `inferno_puff` / `inferno_spark`, set in `_set_shells`), so
  they don't fly through shields, walls or the ground.
- **Satchel spells** (`Player.STARTING_BAG` puts them in the bag – the 10 pages are full; drag onto a page):
  - **Money Rain** (`MoneyRainSpell`/`MoneyRain`, legendary): cloud 9 m above the caster's ground point (sunlit
    `smoke_cloud.gdshader` puffs), shaft of light (`godray.gdshader` open cone + SpotLight – the CylinderMesh is
    centred, so the shader's height runs −h/2..h/2; it fades out before the rim, else a hard ring showed), banknotes
    only (`money.gdshader`, 0.62 m, GPUParticles, rotate_y + vertex flutter), gold rune circle. Every client heals its own
    player inside (r 4.5) by `heal_rate` 5/s for 10 s – everyone, foes included.
  - **Smoke Bomb** (`SmokeSpell`/`SmokeBomb`/`SmokeCloud`): lobbed orb, bounces on layer 1 only (deterministic, no
    event), bursts after `fuse` / at rest into puffs that brake to a stop across r 7 m for 14 s.
    `SmokeCloud.density_at(p)` → HUD `smoke_screen.gdshader`; `SmokeCloud.blocks(a, b)` hides `RemotePlayer` name tags.
  - **Spinjitzu** (`SpinjitzuSpell`/`Spinjitzu`): Grimoire channel toggled by cast; Ninjago-style funnel in the
    player's colour = 26 stacked shallow funnel-lip rings (`spinjitzu.gdshader`, the simple black hole disk's
    streaming filaments from `bh_lite_common`), widening upwards, each swaying/tilting/pulsing on its own
    (`_animate_layers`) + an inner open funnel (`spinjitzu_core.gdshader`, same filaments, 0.72 × the radius, up to
    0.86 × the height so the top rings stay above it – density without more layers) + mote rings whirled at three heights. Angle 0 = local −Z: on the middle layers a
    thin-filament "window" with bright seams faces the look direction; `inside` dims the caster's own. Inner ring
    edges are faint (all layers' rims line up in the view centre and added up to a white column). `Player.move_boost` ×1.6, drains 12 mana/s, every 0.2 s `hit` events
    with `push` to avatars inside `radius_at(h)`. Remote: `spin_end` event / avatar death.
  - **Gravity Field** (`GravityFieldSpell`/`GravityField`): aimed up to 120 m (snaps under an avatar near the
    crosshair line), preview = the same node with `preview = true`. 1500 m column (`gravity_column.gdshader`, mesh
    y = metres above ground), streaks pouring down. While active anyone airborne inside → `Player.slam(40)` (cuts
    dashes/grapples, `velocity.y = −40` before move_and_slide).
  - **Decoy** (`DecoySpell`/`Decoy` **extends RemotePlayer**): same avatar/name/map pin, so all hit tests target it.
    Fake id `Decoy.make_id` (≤ −1000). Owner runs the brain (sprint, turn from walls/slopes/water, jump, dash via
    `DashSpell.cast_remote`, fake sniper aim = `FLAG_AIMING` at the nearest player, rarer: panicked scope – looks
    around wildly, then a harmless beam anywhere via `SniperSpell.cast_remote`, event field `shot`) and sends `decoy`
    events 10×/s;
    others create it in `Decoy.handle_event` (forwarded by `RemotePlayers`). Any hit pops it (`Player.confirm_hit` →
    `Decoy.struck`, or a `hit` event at its id) → `decoy_pop`. Own spells can hit own decoys (only missiles skip them).
  - **Magic / Homing Missiles** (one `MissileSpell` script). `Missile.volley` spawns one every `spawn_interval`
    (0.5 s) from the caster's current position. `magic_missile.tres`: 3 × 20 dmg out of the book at 12.75 m/s,
    `max_distance` 45 m, without a target they follow the caster's live crosshair (`follow_crosshair`).
    `homing_missile.tres`: 5 × explosive 40→12 over 3.5 m at 24 m/s, `launch_behind` (from behind the head,
    arcing over it), without a target they land on the point aimed at when cast (= cast message origin +
    direction). Lock-on: player nearest the line towards the aim point (`lock_angle`, range, LOS). Replays seek the
    same way (candidates = everyone but the caster, incl. the local player; remote crosshair = avatar look ray).
    Explosive → `missile_boom` event, `Missile.explode` on every client (like the fireball).
- Spell lights set `light_volumetric_fog_energy = 0` (with volumetric fog on, they glowed as white balls).
- Death: health 0 → `died`, event `{"kind": "death", "by"}` (kill feed in `NetHud`), knock-back away
  from the attacker, view falls onto the back, no control for `Player.DEATH_TIME` 3 s (`FLAG_DEAD`:
  others play the `death` clip = Mixamo "Flying Back Death", once, holding the pose; dead players can't be
  hit and show no crosshair), then respawn at the waystone circle via `World.place_player`. HUD: `scope.gdshader` (lens, reticle,
  charge arc turning gold when ready), `damage_screen.gdshader` (hit flash + low-health pulse), hit marker,
  "Struck down by" message.

### Balance config (`config/balance.cfg`, `Balance` autoload)
- ConfigFile, one section per spell (= file name in `res://spells/`) + `[player]` (max_health, max_mana,
  mana_regen). Any exported spell property can be set; shared keys: `rarity` (rare/epic/legendary/
  primordial), `mana_cost`, `hp_cost` (life per cast; `Grimoire` refuses with `NOT_ENOUGH_LIFE` if it
  would kill, `Player.spend_health`), `cooldown`. `Balance.apply(dict)` writes values into the cached spell
  resources and **holds references** (an unheld resource is freed and reloads from disk unbalanced).
- Offline the game's copy is applied at startup; the server loads `../config/balance.cfg` (or
  `--balance <file>`) and sends it in `welcome` → `Balance.apply`; `Net.leave()` → `reset_to_local()`.
- Tooltip stats: `Spell.get_stats()` (mana via `_mana_text()`, life, cooldown) + per-spell `_stats()`.

### Inventory (`scripts/inventory/`, `scripts/ui/InventoryUI.gd`)
- `Inventory` (child of Player, `player.inventory`): containers HOTBAR (= grimoire pages, spells only –
  `Inventory.accepts`) and BAG (24). `move` swaps (blocked for the open page while aiming/channeling –
  `is_locked`), `add` (spells → free page first), `drop` → `WorldItem` 2.2 m ahead on the ground.
  Pick up with the `interact` action (E, rebindable) within 2.6 m (nearest, preferring the one looked at:
  `get_pickup_target()`); InventoryUI shows "[E] Pick up <name>" / "No room" (`Inventory.full`).
  Items are Resources identified by `resource_path` (spells now; future items go in the bag).
- **World items are server-owned**: `drop` → server assigns id, broadcasts `item` (all incl. dropper);
  `pickup` → first asker wins, broadcast `item_gone` {by}; `welcome.items` for late joiners. Offline the
  Inventory does both locally. `WorldItem`: hovering, turning page (`world_page.gdshader`, rarity rim,
  primordial = scorched page) + **rarity aura** (one camera-facing billboard, not turning with the page,
  pushed 0.45 m away from the camera and rescaled so it never clips the page; the light radiates from a
  narrow capsule core hidden behind the page – no frame lines, faded out before the plane's edges;
  `world_page_aura.gdshader`) +
  **light pillar** (`loot_beam.gdshader`, Y-billboard pushed 0.5 m behind the page like the aura, brighter with
  distance – rarity visible from afar)
  + light + motes; `collect()` flies to the taker.
- Rarities (`Spell.Rarity`): RARE "Arcane" blue, EPIC "Eldritch" purple, LEGENDARY "Celestial" gold,
  PRIMORDIAL "Primordial" (god tier). The flashy auras are **only on dropped pages in the world**
  (`world_page_aura.gdshader`: blue sheen; + sparkles; + shining gold rays; primordial: pulsing black
  fire tongues with violet seams, dark aura, white "event horizon" line, orbiting sparks, embers). In the
  UI cards just get a thin rarity-coloured outline (`InventoryUI._style_card`); primordial ink glows via
  `primordial_ink.gdshader`.
- UI: hotbar bottom centre **only while the inventory is open** (in play you flip the book; keys 1-0
  still jump to pages), open page lifted, satchel 4×6 top left, opened
  with the `inventory` action (Tab); mouse free, controls blocked (`Player.is_input_blocked`), no pause.
  Drag & drop via `set_drag_forwarding`; drop outside the panels = throw into the world. Layout in a
  1080-high virtual space scaled to the window; hotbar kept right of the mana bars (`BARS_RIGHT`).
  `Player.is_menu_open()` (pause/map only) hides HUD/hotbar; the inventory doesn't hide the HUD.

### HUD (`scripts/ui/Hud.gd`, `scripts/ui/MagicBar.gd`)
Crosshair: `shaders/ui/crosshair.gdshader` on a ColorRect – centre dot, three turning arcs + four inward
diamonds with a dark outline and glow, tinted in the open spell's `theme_color`; kicks out and spins on every
cast (`spell_cast`); hidden while scoped / dead / inventory open.
Compass strip top centre (`scripts/ui/CompassBar.gd`, drawn in `_draw`): headings scroll past a centre notch, north =
world −Z like the map (`heading_from_yaw`), diamond markers for places (Waystone Circle, `Hud._update_compass`).
Mana bar above health bar, bottom left (gem caps on the outer side); hidden while paused. `MagicBar` = ColorRect with
`shaders/ui/magic_bar.gdshader`: gilded stadium frame (SDF + perimeter coordinate), flowing liquid, lagging
"ghost" of losses, diamond gem cap, two golden filigree threads winding around the frame + sparks running
along it. `pulse()` flashes/shakes it (mana bar on `NOT_ENOUGH_MANA`). Full-screen dash effect:
`shaders/ui/dash_screen.gdshader` (radial blur towards the dash direction, chromatic fringes, tinted
vignette).

### Textures (`tools/bake_textures.gd`, `shaders/compute/texture_bake.glsl`)
Offline GPU bake to `textures/*_albedo.png` / `*_normal.png`: grass, rock, dirt, snow, moss, bark_oak,
bark_pine, leaves, needles (cards with alpha), macro (variation), detail (linear heights, lossless import),
water (wave normals). Tiling uses lattice-periodic noise → exact seams (verified numerically).
Albedo alpha = height for height blending. The baker writes `.import` files (VRAM + mipmaps; normal maps
RG-compressed; detail lossless). `BAKE_ONLY=rock,grass` rebakes a subset; run `--import` afterwards.

### Lighting & sky ("AAA stylized", Horizon-like: warm sun, cool sky-lit shadows, saturated)
- `shaders/sky/stylized_sky.gdshader`: blue gradient → hazy horizon, warm sun glow + disc, **painterly 2.5D
  clouds**: density fields on stacked horizontal layers (`cloud_layers`, 3D noise textures sliced + the
  shared weather map), lit by a short march towards the sun *within the layer* + thickness-darkened
  undersides + silver linings, plus a thin cirrus layer. A raymarched volume was tried first and dropped:
  without temporal accumulation it showed grain (jitter) or slice banding. Cubemap pass (ambient/reflections)
  uses the same clouds without detail and ~40 % desaturated so shadows are cool, not icy.
- `shaders/include/stylized_light.gdshaderinc`, used via `light()` in terrain, grass, foliage, rock_common
  (rocks/orbit rocks), island and reed shaders: wrapped diffuse + warm terminator band, translucency
  (grass/leaves/reeds glow when backlit), sun-coloured rim, soft Blinn-Phong (keep strengths tiny – it isn't
  tinted by albedo, large values gave white blotches), and `cloud_shadow()` (weather map projected along the
  sun) multiplied into the directional light's attenuation. Materials with a custom light() ignore BACKLIGHT.
  **Ground (terrain soil/grass/moss, grass blades) must stay matte**: roughness 1, low SPECULAR, rim 0 –
  the ground is seen at grazing angles, so rim or sky reflections turn into a plastic sheen. Only rock,
  snow and wet mud keep a little specular.
- Environment values are in `Main.tscn` (`Env_main`). Fog sun-scatter / volumetric anisotropy wash out
  everything towards the sun quickly – keep them low. Settings: "Clouds" (`cloud_quality` → layers/sun
  samples via `Settings.CLOUD_STEPS`), "Light shafts" (`volumetric_fog`), "Ambient occlusion"
  (`ambient_occlusion`: off / SSAO / SSAO + SSIL).

### Resource packs (`resource_packs/`, `scripts/util/ResourcePacks.gd`)
- A pack = `resource_packs/<id>/pack.cfg` (`[pack]` name/description/author, `[bake]` shader, strip, jobs)
  + `textures/` with the same file names as `res://textures/`; missing files fall back to the default.
- **All material textures load through `ResourcePacks.texture("rock_albedo.png")`** (Terrain, IslandField,
  VegetationAssets, Lake) – never `load("res://textures/...")` directly. Active pack = setting
  `resource_pack` ("" = default), picked in Settings → Graphics; applied when the world is built
  (in game: "Apply now" reloads the scene; `VegetationAssets` cache rebuilds when the pack changes).
- `realistic` pack: own bake shader `resource_packs/realistic/bake/texture_bake.glsl` (2048² for most,
  2×2 supersampled, central-difference normals with strength per 1024 px, BC7 import): scattered primitives
  (grass blades with thatch/soil/pebbles, pebbles/twigs/leaf litter in dirt, moss fronds), Voronoi border
  distance for joints/plates, oak furrows from zero crossings of stretched noise, flaking pine plates.
  Bake: `PACK=realistic` (+ `BAKE_ONLY=...`) with `tools/bake_textures.gd`, then `--import`. Dispatches run
  in row strips (`strip` in pack.cfg) to stay under the GPU timeout; grass/rock take ~20 s each.
  Keep every lookup lattice-periodic (integer frequencies, `wrap_cell` on cell hashes) or seams appear.

### Terrain (`scripts/terrain/`)
- `TerrainSettings` (all knobs; `seed` for a new world), `TerrainData` (heights, control map, rock map,
  lakes, sampling helpers), `TerrainGenerator` (GPU pipeline via `scripts/util/GpuCompute.gd`).
- Pipeline (compute shaders in `shaders/compute/`): noise layers (warp, continents, hills, masked ridged
  ranges, valleys, border mountain ring) → **coarse** droplet erosion on a 4× coarser grid → B-spline
  upsample of the erosion delta → light fine erosion → thermal → **outcrops** (terraced risers/ledges +
  ridged relief on steep/patchy ground, writes rock mask) → finalize.
- Control map RGBA8: R deposit, G flow, B erosion, A concavity. Rock map R8.
- `Terrain.gd`: 64 m chunks, 5 LOD rings (0.5/1/2/4/8 m) sharing flat grid meshes displaced in the vertex
  shader; skirts hide LOD cracks; one `HeightMapShape3D` for collision; distant backdrop mountain ring.
- `shaders/terrain.gdshader` + `shaders/include/terrain_common.gdshaderinc` (shared with grass):
  close-range detail displacement fading 35–75 m around `player_position`; per-pixel material weights
  (rock abrupt on steep ground and outcrop risers, soil/gravel/moss on ledges, dirt on sediment/channels,
  snow high up).

### Vegetation (`scripts/vegetation/`)
- `VegetationAssets` (shared cache): 4 broadleaf + 4 pine trees (`TreeGenerator`, **3 LODs**: full 0–60 m,
  every 3rd card 60–260 m, trunk + ~14 cards without shadows 260 m+), rocks/boulders/sticks (`RockGenerator`).
- `Vegetation`: scatter by forest noise, slope, altitude, control/rock maps, skipping water;
  `ScatterBatch` bins into per-cell MultiMeshes with visibility ranges; trunk/boulder colliders via
  PhysicsServer3D directly. Exposes `tree_positions` / `tree_is_pine` (used by the map).
- `GrassField` + `shaders/grass.gdshader`: 8 GPU-placed layers (short grass near/far, tall bundles, tufts,
  seed grass, daisy/bell/umbel flowers). Each layer is a MultiMesh grid snapped to the camera; the shader
  hashes the **world cell** for stable placement, reuses terrain height/weights, fades with distance,
  wind + player push. Grid offsets must be whole cells (half-cell offsets caused flicker – fixed).

### Forests (`scripts/world/ForestLayout.gd`)
Generated after `StartSite.flatten`, before the terrain is built (own seed `seed + 7919`): 4 big forests with
lobed outlines (the first, 165–185 m radius, holds the Griffin's Den site; others 115–150 m), away from the start
site and lake. Each has 3–5 glades and trails (Prim MST over entrances + glades (+ den) and one loop edge, winding
via `_wander`), painted as worn earth into the control map. A 2 m mask holds density (dense core, thinning edge,
patches), `blocked` (trails, glades, den clearing) and forest index. `Vegetation` uses `density_at` / `blocked_at` /
`pine_at`; inside forests trees also grow on slopes to n.y 0.8 and across rills (control G ≤ 0.93). Outside them
only small groves. The map labels forests by name, draws trails dashed, and samples more billboards in forests.

### Secret spot (`scripts/world/SecretSite.gd`) – reserved for the secret village
Site = `ForestLayout.secret` (flattest spot near the biggest forest's centre; a trail leads in, `secret_entry`).
`SecretSite.carve` (static, after ForestLayout, before the terrain) sinks an 8 m grassy hollow: flat floor r 30,
slopes to the rim r 46. Trees/rocks/shrooms skip it (`in_secret`); the map's relief is kept flat over it so it
doesn't show. The Griffin's Den that stood here was **removed** (user can't make the griffin model/animations;
`docs/concepts/griffin*.md` are shelved). Reusable plumbing from it: discovered places (`Net.send_discover` →
server `[discovered] <seed>` in server.cfg, `discovered` broadcast + list in `welcome`, `--reset-discovered`;
`Hud.announce(title, who)` banner). Client-side hiding (stand-in trees for players outside the forest) was in the
den's script – rebuild it for the village.

### Bounceshrooms (`scripts/world/ShroomField.gd`, `Bounceshroom.gd`)
36 mushroom clusters (own seed `seed + 4241`, not drawn from World's rng so other seeds stay put): one big
`Bounceshroom` standing along the averaged ground normal (sites: normal.y ≥ 0.9, dry, not rocky, outside
clearings, 3.5 m from trunks, 70 m apart; the first near the waystone circle) + 4–8 small decorative ones (3 cap
colours, 14-segment mesh, no collision). Lathed mesh (`mushroom.gdshader`, part in COLOR.r, `squash`/`glow`
instance uniforms, spring wobble) squashed to `TOP` 0.62 m so a jump (~1 m) gets onto it; cylinder collider.
Feet on the cap (checked in the shroom's own frame) → `Player.bounce(up × 22)`: vertical directly, horizontal
as `_dash_carry`, so tilted ones throw sideways.

### Floating islands (`scripts/islands/`)
`IslandField` places Poisson-spaced groups (monolith, twins, archipelago, shard spiral, lone) + skyline
groups outside the map. `IslandShape` = unique procedural body (outline, cliff ledges, lopsided underside,
spires, gullies, crags, optional rocky crown); `FloatingIsland` adds trees, rocks, hanging roots, crystals,
GPU-orbiting rocks (`shaders/orbit_rock.gdshader`, clearance via `lowest_underside_at`), motes; small ones bob.
Walkable (collision) islands get grass + flowers from `IslandGrass` (the terrain `GrassField` only knows the
heightmap): clumps scattered on the CPU over a 1 m `top_y` grid (inside 0.95 × rim, normal.y > 0.78),
binned into 16 m chunk MultiMeshes with visibility ranges; `shaders/island_grass.gdshader` colours them like
the island ground (island-local XZ in INSTANCE_CUSTOM, `strata_seed`), wind/push/fade like the terrain
grass; follows the "grass_density" setting. ~0.2 s at load for all islands. (Packed arrays fetched from a
Dictionary are copies – appending to them is lost; collect in plain Arrays.)
The map pin (`MapOverlay._pin_position`) stands on an island's miniature while the player is on/above it.
**Every island inside the map has collision** (trimesh); the small ones (r < 12) bob, so theirs is a
top-level `AnimatableBody3D` moved to the island's transform in `_physics_process` (an AnimatableBody only
carries riders when its *own* transform changes, not its parent's). **Orbiting rocks collide** too:
`AnimatableBody3D`s built lazily when the camera comes within `ORBITER_RANGE` of the swarm (extent includes
orbit height – rocks hang up to ~200 m below), disabled again beyond it; transforms from
`FloatingIsland.orbiter_transform()`, a CPU copy of the ORBIT vertex shader in `rock_common.gdshaderinc` –
**change both together**. One shared convex hull per rock mesh (`prewarm_hull` at load; per-rock scaled
point sets made the physics server rebuild a hull each, ~0.7 ms) with uniform scale on the shape node.
**Shared world clock**: all this motion is a pure function of `Net.world_time()` (server uptime, sent in
`welcome` + a 1 Hz `clock` message; the client keeps the largest server−local sample, decaying 2 ms/s;
offline = local uptime), also the global shader uniform `world_time` (set in `Net._process`). So moving
scenery needs no per-object network traffic – use it for any future deterministic world motion. Float
precision in the shader degrades after ~a day of server uptime.

### Lake (`scripts/water/`)
`LakeShape.find` picks the flattest low site, `carve` digs the basin + bank + island into the heightmap and
paints mud/wet shore into the control map **before** the terrain is built. `Lake` builds the water
(`shaders/water.gdshader`: depth colour, refraction, reflections, foam), lily pads/flowers, reed beds on a
few shore arcs (`WaterPlants`), island trees/rocks. Grass shader rejects underwater via `lake_params`.
Swimming: `Lake` builds an invisible collision floor `SWIM_FLOOR` (1.25 m) below the surface, a polygon
following the wobbly shoreline out to `SWIM_FLOOR_REACH` 1.1× (the carved bank is only guaranteed above the
water up to 1.2×; the old disc out to 1.5× stood up to 5 m above lowered terrain beyond the bank) and exposes `depth_at(feet)` (group "lake"). `Player` counts feet deeper than
`SWIM_DEPTH` as swimming: ×0.55 speed, no jump, eased camera bob/roll (also sent to other players), the
grimoire lifted out of the water via `Grimoire.hold_offset`.

### Start site (`scripts/world/StartSite.gd`)
"Waystone Circle": flattest dry spot near the centre (score = height std + rock + distance·0.012, away from
the lake). `flatten` levels the plaza (+`PAVE_LIFT` inside), blends out to 36 m, turns the clearing into
meadow, paints four worn dirt paths and appends to `TerrainData.clearings` (x, z, clear radius, paved
radius): Vegetation skips trees/rocks inside, grass and the terrain's close-range displacement skip the
paved radius (`flat_zone` uniform in `terrain_common`). Geometry: bedding disc, flagstone courses + kerb,
3-step octagonal dais, rune pillar, glowing rune ring, 12-slot menhir ring (`RockGenerator` stones, one
fallen), blue OmniLight. Collision is simplified: plaza disc, a convex ramp over the dais steps (too tall to
walk up), pillar cylinder, box per menhir. Marked on the map (inked symbol + paths, miniature, floating gem,
label).

### Multiplayer (`server/`, `scripts/net/`)
- **Server** = separate headless Godot project `server/` (`server.gd`, `Server.tscn`), started with
  `run_server.bat` (`--port 8910`, `--seed N`, `--new-world`; otherwise reuses the last seed from
  `user://server.cfg`). Prints its LAN addresses. WebSocket (TCPServer + WebSocketPeer), JSON text messages
  `{"t": ...}`: `hello`/`welcome`/`reject`, `join`/`leave`, `state` → batched `states` (20 Hz tick – put
  future server-side enemies in `_tick()`), `cast` and generic `event` relayed with the sender `id`.
  `clock` (1 Hz, server uptime → `Net.world_time()`).
  The nested `project.godot` makes the game project ignore the folder.
- **World generation is deterministic**: same seed → bit-identical terrain (heights, control, rock maps)
  and identical lake, start site, vegetation and islands, verified by fingerprinting two separate launches.
  Droplet erosion used to race (droplets read heights other droplets were changing: up to ~1.2 m
  difference run to run); now each batch reads a **snapshot** and only adds integer deltas with atomics
  (order-independent), the snapshot refreshed between batches by `GpuCompute.copy` (a compute pass –
  `RenderingDevice.buffer_copy` silently did nothing). Batches: `coarse_batch` 1024, `droplet_batch` 8192.
  **Keep it so**: world-gen code must only use seeded `RandomNumberGenerator`s / `FastNoiseLite` – never
  global `randf()` / `randi()` / `Array.shuffle()` / `pick_random()` (`IslandField` shuffled the island group
  kinds globally, so every client got different islands). Float maths may still differ between GPU
  vendors/drivers, so the terrain upload stays: the first player to join generates and uploads the raw terrain (`WorldBlob`: zstd heights +
  control + rock, ~7 MB) and the server caches it per seed/`Net.WORLD_VERSION` on disk
  (`AppData/Roaming/Godot/app_userdata/Wizard Game Server/worlds`) and streams it in 256 KB binary chunks
  (paced by outbound buffer). Everything after (lake, start site, vegetation, islands) is CPU + seeded →
  identical. Bump `Net.WORLD_VERSION` when terrain generation changes (old caches are then ignored).
- `Net` autoload: connect/leave, signals for world/players/states/casts/events, `send_state` (Player, 20 Hz),
  `send_cast` (Grimoire `spell_cast` → spell `resource_path`; remote side calls `Spell.cast_remote`),
  `send_event`. `last_error` is shown on the connect page after a failure/disconnect.
- `RemotePlayer`: `PlayerModel` avatar (name `Label3D`), snapshot interpolation 100 ms behind, cast flash.
- **Player character = `assets/player/player.glb`** (user-made, Mixamo rig; meshes face/hat/jacket/body,
  clips `idle` + `run`, both in place; faces +Z, ~10.3 units tall, the clips lift the rig ~5 units above
  its origin-centred T-pose). `scripts/net/PlayerModel.gd` scales it to 2 m, turns it to face -Z, tints the
  `body` material in the player colour, makes jacket opaque / face depth-prepassed (exported as blended),
  loops the clips. `make_ghost()` = frozen pose copy for dash afterimages. Used by `RemotePlayer` and
  the connect-page preview. `WizardModel.gd` (old procedural wizard) is no longer used.
- **Extra clips = Mixamo FBX (without skin, same rig) in `assets/player/animations/<name>.fbx`**:
  walk, jump, fall, land, cast, swim, dash, death (`PlayerModel.EXTRA_CLIPS`; missing files are skipped).
  Dash loops at `DASH_RATE` 1.5× (user: too slow as downloaded) while `FLAG_DASHING` is set, at least
  0.3 s, and cancels the cast gesture.
  `AnimRetarget.bake` retargets them at first use (~20 ms, cached statically): the GLB went through
  Blender so bone axes differ – world-space rotation deltas vs. T-pose rest are transferred, target
  rests aligned to the source bone directions (GLB arms droop 9°), hips height scaled by leg length.
  `face_forward` removes Mixamo's ~43° sideways turn of jump/fall/land. Jump starts at take-off and
  land at touchdown (custom timelines found from the hips height).
- AnimationTree: BlendSpace1D idle/walk/run by speed (run sped up beyond 5 m/s) → Transition
  ground/jump/fall/land/swim/dash/death → upper-body OneShot `cast` (filtered to spine/arms/head).
  `update_motion(delta, speed, vspeed, on_floor, swimming)`, `play_cast()`.
- State messages carry a 6th value, movement flags (`Net.FLAG_ON_FLOOR` – with 0.15 s grace –,
  `FLAG_SWIMMING`, `FLAG_DASHING`, `FLAG_AIMING`, `FLAG_DEAD`, `FLAG_BURNING`); server/clients also accept the old 5-value form. `RemotePlayer` takes vertical
  speed from the snapshot segment (not the interpolated position) so jumps are seen at take-off. Map shows them as coloured pins with names.
- Title screen (`scripts/ui/TitleScreen.gd`, backdrop `shaders/ui/title_backdrop.gdshader`): Start /
  Settings (PauseMenu in `title_mode`) / Quit; connect page with nickname, colour swatches + picker, turning
  avatar preview, server address (`ip` or `ip:port`). Profile saved in Settings (`PROFILE_KEYS`, kept by
  reset). Shared menu look: `UiTheme`.

### Graphics quality / low-end mode (`scripts/settings/GraphicsQuality.gd`)
- Measured (RTX 3060, 1080p, GPU): old lowest settings were still 4.2 ms / **5.2 M triangles** – mostly trees,
  drawn again into all 4 shadow cascades. Now: shadows "Low" = 2 cascades / 90 m, mid-range trees (LOD1) only
  cast shadows from "Medium" up, view distance scales tree/rock visibility ranges (ScatterBatch meta `vis`) –
  lowest options 2.3 ms. Presets (Settings → Graphics, `Settings.PRESETS`): High 9.3 ms, Medium 7.6, Low 3.3,
  Very Low 2.4 (keeps grass, shadows, clouds, bloom).
- **Performance shaders** (`performance_shaders`): `GraphicsQuality.use(mat, full, lite)` registers a material,
  swapped live on change (uniform values survive a shader swap). Lite variants = same body include with
  `#define LITE`: `terrain_lite` (`include/terrain_body`: only materials with weight sampled, one tiling scale,
  no normal maps except grass, no detail normals – ~12 reads instead of ~40), `rock_lite`/`orbit_rock_lite`,
  `foliage_lite` (`include/foliage_body`), `island_lite` (`include/island_body`). Also sky radiance updates
  incrementally instead of every frame. **Change full and lite together** (shared bodies).
- Grass density now changes the grid (`GrassField.SPACING_SCALE/RANGE_SCALE`): Low ≈ 22 % of the clumps.
- Settings keys renamed: `shadow_quality` → `shadows` (0 = Off), `ssao` → `ambient_occlusion` (Off / AO /
  AO + SSIL – SSIL is the expensive part); `load_settings` migrates old saves. `upscaler`: FSR 2 / FSR 1 /
  bilinear (FSR 2 itself costs a few ms on weak GPUs); render scale down to 40 %.

### Settings & pause menu
- `Settings` autoload: values + defaults, save/load `user://settings.cfg`, applies window mode, resolution,
  vsync, fps cap, render scale (FSR), AA, shadow quality, SSAO/glow/fog, brightness, grass density,
  view distance, audio buses (Master/Music/SFX – no audio in the game yet), FPS counter. Rebinding stores
  physical keycodes; rebinding to a used key swaps bindings. `setting_changed` / `keybinds_changed` signals.
- Pause menu and map pause the tree **offline only**; online the world keeps running and
  `Player.is_input_blocked()` (groups "pause_menu" / "map_overlay") just ignores the controls.
- `PauseMenu` (Esc): Continue / Reset View / Settings / Leave Game (→ title) / Quit; tabbed settings (Controls, Gameplay, Graphics, Audio),
  code-built UI with a custom theme over a blurred backdrop (`shaders/ui_blur.gdshader`). Auto-opens on
  focus loss. Ignores Esc while the map is open.

### World map (`scripts/map/`, `shaders/map/`)
- `MapOverlay` (key M): captures a still of the game → blurred backdrop (`ui_blur_texture.gdshader`),
  sets `get_viewport().disable_3d = true` and pauses; renders the map in its own SubViewport world.
  Unroll → relief rises; closing reverses. Camera eases exponentially towards the drag target (`EASE`, no overshoot)
  with the sheet leaning slightly with the turning speed (`SWAY`).
- `MapBuilder`: relief with the **waystone circle as ground zero** (`_relief_of`: higher ground rises, lower ground is
  pressed into the paper at the same eased scale, down to `MAX_DEPTH`; lake basin relative to its surface, water
  sheet at `water_relief`; hachures/shading on both); paper inked once
  with Godot 2D drawing via `InkCanvas` (parchment shader, hachures only – **no cross-hatching**, stipple,
  shoreline, compass in margin, scale bar); upright billboard trees (MultiMesh shader); floating islands
  as simple paper-shaded models with ink outline (**no hatching**); floating Label3D labels + cartouche
  sprite (labels face the camera fully, trees are Y-axis billboards); animated sunken lake; player pin.
- Labels carry a category (`_label(..., category)`: "location" = forests, lake, mountains; "landmark" = built
  places like the Waystone Circle). The **legend** (bottom left, `MapOverlay._build_legend`) toggles each kind
  (`MapOverlay.show_locations/show_landmarks`, session only); mouse events over it skip the map's input capture.
  Island-group names were removed on request.
- The local pin spins, so a flat triangle (`MapBuilder.pin_arrow`) at its foot points where the player faces.
- **Player pin = `assets/map/player_pin.obj`** (user-editable; map units, tip at origin, ~0.3 tall).
- An HTML prototype of the map was made first (published artifact
  https://claude.ai/artifact/QXG6wECCRchxaUVUUDjSDB); the in-game version follows it minus the table.

## Music (`music/`, has `.gdignore`)

Score-as-code: `music/lib/score.py` (notes in eighth-note units, 6/8, chord helpers, symbolic dynamics `dyn()`
→ CC2 for the SoundFont render, CC1 in the `*_daw.mid` export for DAW libraries), `music/lib/render.py`
(FluidSynth 2.6.1 in `music/bin/` + MuseScore_General.sf2 in `music/soundfonts/` → synthetic hall reverb in
numpy → WAV/OGG/MP3 via ffmpeg), `music/lib/harmony.py` (chord symbols, voice leading, phrase dynamics).
Pieces = one script each → `music/out/`: `main_theme.py` ("Where the Waystones Sleep", D major, the leitmotif),
`main_theme_v2.py` (second take at ♩=132: leaping theme, flute/violin call-and-response in B minor, quiet
solo-flute bridge, build modulating to E major, dance variation; `mel()` = dynamics follow the melody's pitch),
`battle_theme.py` ("Grimoires Drawn": flute + drums only, fast 6/8 jig in D Dorian at ♩=180, the theme's head
reworked; flute dynamics follow pitch + beat accents), `battle_theme_v2.py` (♩=200, D→E Dorian, drum breaks, quiet "stalking" section, two flutes in the finale),
`battle_theme_orchestral.py` (earlier full-orchestra
version, D minor ♩=156, kept for later).
**Electronic pieces** use `music/lib/synth.py` (numpy: polyBLEP saws, supersaw pad, reese bass, pluck, lead,
kick/snare, riser/impact, ping-pong delay, sidechain, crush, stutter, tape stop, `Bus.level(dB)` auto-balances
stems by RMS; **break chopping**: `chop(seq, src, slot)` with steps `(slice, retrig, pitch, reverse, gain)`).
`battle_breakcore.py` ("Overcast", 180 BPM 4/4, F# minor, new melody – user asked for a less medieval,
breakcore battle theme): break = Amen-style pattern rendered from the SoundFont room kit at 136 BPM, sped
up to 180 (pitches up like a sample), one sixteenth = exactly 4000 samples; flute (SoundFont) only in the
breakdown + doubling the lead in the last drop; prints a per-section stem level table.
Drums: channel 9, program 48 = Orchestra Kit.
SoundFont "Expr." presets (bank 17/21/26…: flute, violin sections, choir) take dynamics from **CC2 only**
(CC11 does nothing). **Style: Frieren-like** (Evan Call) – flute lead, string-heavy at times, airy, women's
choir for weight, harp; no piano (rarely) – a general palette, not every piece needs all of it. User
prefers action-packed, fast battle music with an energetic, fluctuating flute lead. Final tracks will go to `assets/music/`.

## Dev tools (`tools/`, run without `--headless`)

- `screenshot.gd`: loads the game, waits for generation, renders views to `$SHOT_DIR/shot_N.png` and prints
  fps (vsync disabled in the tool, though Settings may re-enable it).
  `VIEWS="player;x,z,height,yaw,pitch;tree:<pine0/1>:<n>;island:<i>:<dist>:<height>;lake:<dist>:<h>:<angle>;menu:main;menu:settings:<tab>;map;map:open[:yaw:pitch:dist]"`,
  `TOGGLES="noshadow,notrees,nossao,noislands,nograss,noterrain"` for profiling.
- `preview_terrain.gd`: hillshade/control/rock PNGs without starting the game (`PREVIEW_DIR`,
  `SET="seed=7,coarse_droplets=20000"`).
- `bake_textures.gd`: see Textures.
- Multiplayer test that worked: start the server, then a temp `SceneTree` script that calls
  `Net.connect_to_host`, switches to `Main.tscn` on `world_ready` and walks/screenshots; run two instances.
- Workflow that worked well: change → render shots → look → tune. Temporary test scripts (e.g. simulated
  input via `Input.parse_input_event`) go in `tools/_*.gd` and are deleted afterwards. In `SceneTree`
  scripts autoloads aren't compile-time identifiers – use `root.get_node("Settings")`.
- Spell VFX test that worked: a temp script casts via `player.grimoire.go_to_page(i)` + `try_cast` (clear
  `grimoire._cooldowns` between casts) for first-person shots, and spawns a remote-style copy
  (`_make(...)`, `_static = true`) in front of an extra Camera3D for side / wide / "caught inside" views.
  Note: Python `open()` on Windows defaults to cp1252 – pass `encoding="utf-8"` when editing these files.

## Gotchas learned

- Godot front faces are **clockwise**; procedural mesh helpers (`MeshUtil.tri`) orient by normal.
- GLSL `%` on negative ints is undefined – use floored division (periodic noise seams came from this).
- Droplet erosion is scale-sensitive: keep `capacity_factor` low (capacity-limited) and do large-scale
  erosion on the coarse grid; tune droplet count as visits-per-cell (~20–40).
- `visibility_range_*_margin` without fade caused holes between terrain LODs – margins are 0.
- Use a global `player_position` (not `CAMERA_POSITION_WORLD`) for displacement fades so shadow passes match.
- `SubViewport` with `UPDATE_ONCE` + two `frame_post_draw` awaits to read a one-off render (InkCanvas).
- Dev-tool `SceneTree` scripts can't name spell classes that use `Net` statically – `load()` them at runtime.
- Godot 4.7 shaders: no `return` in `fragment()` – put branches in a helper returning vec4. Built-ins
  (`CAMERA_POSITION_WORLD`, `INV_VIEW_MATRIX`, `COLOR`, ...) aren't visible inside such helpers – pass them in.
- Don't name a script method `_set`/`_get` (Object virtuals – signature clash parse error).
- Simulated GUI drags (`Input.parse_input_event`) need `InputEventMouseMotion.relative` set – the drag
  threshold accumulates `relative`.
- Type-inference errors (`:=` with Variant results, ternaries on Variants) are the most common parse errors.
- Foliage flicker while turning = alpha-tested leaf aliasing (measured with a sub-pixel-turn shimmer map,
  not a camera bug: rendering is not view-history dependent). FSR 1's sharpening nearly doubled it, so
  render scale < 1 uses **FSR 2**. TAA is the calmest option.
- Performance (RTX 3060, 720p, uncapped): ~105–170 fps in the world; trees were the main cost before LOD2.

## User preferences

- Wants realistic, varied procedural content (no obvious cloning), iterates visually with screenshots,
  and likes prototypes (HTML artifacts) before big features. Communicates partly in German terms
  (e.g. "Schilf" = reeds). Prefers editable source assets for things they may want to tweak.
- Not a git repository yet.
