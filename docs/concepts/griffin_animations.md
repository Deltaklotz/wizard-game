# Griffin – model and animation list

> **Shelved (2026-10-24):** the griffin won't be made (no model/animations). The Griffin's Den was removed; its hidden
> forest spot is reserved for a secret village instead.

What the griffin (boss / familiar) and the baby griffin need, for the user to model and animate.
Concept: `griffin.md`. The game plays clips through an AnimationTree like the player avatar
(`PlayerModel.gd`): blend spaces for locomotion, transitions between states, one-shots for attacks.

## Export (same pipeline as the player)

- **One GLB per creature**: `assets/creatures/griffin.glb`, `assets/creatures/griffin_baby.glb`.
  Extra clips may also come as separate files in `assets/creatures/griffin/animations/<name>.glb/.fbx`
  (same rig, no mesh) – the loader skips missing ones.
- **Facing +Z or −Z** – just tell me which; any scale (I scale it in code). Rough target size: body ~3.5 m
  long, **wingspan ~10–12 m**, back ~2 m high. Baby: about the size of a cat (0.5 m).
- **All clips in place** (no root motion). Movement comes from the game; flight height too.
- **Loops** marked as loops (or tell me which ones loop) – listed below as *(loop)*.
- **Bones I need to find by name** (any names, just tell me):
  - `saddle` – where the rider sits (the player is attached there while riding).
  - `head` – look-at / where screeches and bites come from.
  - `claw_l`, `claw_r` (front talons) – swipe and grab hit points.
  - Baby: `grip` – where the player's hands hold on while gliding.
- Optional: separate material for the feathers/fur vs. beak/claws so I can tint or add effects
  (damage flash, gravity-field glow).

## Griffin (boss and ridden familiar) – 30 clips (18 of them priority A)

Priority: **A** = needed for the first playable version, **B** = makes it feel good, **C** = polish.

### Ground
| Clip | Pri | Notes |
|---|---|---|
| `idle` *(loop)* | A | Standing, breathing, tail flicks, looks around. |
| `walk` *(loop)* | A | Four-legged walk (lion hind legs, eagle front talons). |
| `run` *(loop)* | A | Gallop, wings slightly open for balance. |
| `turn_l`, `turn_r` | C | Turning on the spot (otherwise it just rotates while idling). |
| `sleep` *(loop)* | A | Curled up on/around the nest, head tucked under a wing, slow breathing. |
| `wake` | A | Head snaps up, rises, shakes feathers (sleeping → alert, when it notices a thief). |
| `sit_alert` *(loop)* | B | Awake guarding the nest, head turning, suspicious. |

### Flight
| Clip | Pri | Notes |
|---|---|---|
| `takeoff` | A | Crouch, leap, first big wing beats (ground → air, ~1 s). |
| `fly` *(loop)* | A | Steady flapping. |
| `glide` *(loop)* | A | Wings spread, slight adjustments (cruising, and the slow descent when ride time runs out). |
| `fly_fast` *(loop)* | B | Fast, short wingbeats (chasing / dash while ridden). |
| `hover` *(loop)* | B | Beating in place, body upright-ish (before a dive, over the nest). |
| `bank_l`, `bank_r` *(loop)* | C | Leaning into turns (blended in by turn rate). |
| `dive` *(loop)* | A | Wings folded, head down (swoop attack, diving at a target). |
| `land` | A | Wings braking, legs forward, touchdown. |

### Combat
| Clip | Pri | Notes |
|---|---|---|
| `screech` | A | Rears up, wings spread, beak open (aggro / phase change). |
| `claw_swipe` | A | Front talon swipe on the ground (melee). |
| `bite` | B | Lunging beak snap. |
| `wing_buffet` | B | Big wing beat that blasts players back (knock-back attack). |
| `swoop_grab` | B | End of a dive: talons forward, grabs/strikes and pulls up. |
| `hit` | A | Flinch (small, additive-friendly – plays often). |
| `knocked_down` | A | Struck out of the sky / slammed by the Gravity Field: crash, tumble, lies stunned. |
| `stunned` *(loop)* | A | Lying dazed (the forced-cooldown state; this is the window to tame or hit it). |
| `get_up` | A | Recovering from stunned. |
| `death` | A | Final fall (whether it dies or just yields is still undecided – a clip that ends lying down works for both). |

### Taming and riding
| Clip | Pri | Notes |
|---|---|---|
| `submit` | A | Lowers head and wings, bows to the tamer (tamed moment). |
| `ride_idle` *(loop)* | B | Like idle but calmer, rider on its back (can reuse `idle`). |
| `exhausted_glide` *(loop)* | C | Tired glide when flight time is running out (heavier, drooping; else `glide`). |

## Baby griffin (familiar, can't fly) – 8 clips (3 of them priority A)

| Clip | Pri | Notes |
|---|---|---|
| `idle` *(loop)* | A | Fluffy chick, wobbly, preening. |
| `walk` *(loop)* | A | Waddling (follows its owner around). |
| `hop` | B | Little hop / failed flap attempt (keeping up, jumping). |
| `held_flap` *(loop)* | A | Gripped above the player (Space while airborne): flapping furiously, straining – it slows the fall but can't lift. Needs the `grip` bone where the hands go. |
| `appear` | B | Pops out / unfolds into the held pose (start of the glide). |
| `tired` | C | Flops after a long glide. |
| `sleep` *(loop)* | C | Curled up (as an idle variation / in the satchel preview). |
| `hatch` | B | Breaking out of the egg (when a stolen egg hatches). Egg shell as a separate mesh in the file, or I can make it. |

## What I build around them (no clips needed)

- Head look-at towards targets (IK on `head`), wing-fold blending between `fly` and `glide` by speed/climb,
  banking by turn rate (procedural lean if `bank_*` are missing).
- Rider placement on `saddle`; the player's own camera rides along (first person stays first person).
- Hit flashes, feathers flying off, dust on landing, wind gusts from `wing_buffet` – as effects.
- Server-side AI, health, sleep/wake detection, egg theft, taming item, ownership transfer (see `griffin.md`).
