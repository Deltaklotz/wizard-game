# Concept: The Griffin (boss, familiar) and baby griffins

> **Shelved (2026-10-24):** the griffin won't be made (no model/animations). The Griffin's Den was removed; its hidden
> forest spot is reserved for a secret village instead.

Status: **concept only – not implemented.** Written down from the user's description so it can be built
later. Sections marked *Notes* are implementation thoughts, not decisions.

## The Griffin – a unique boss

- There is **one** griffin in the world. It is a boss that players can either **fight** or **tame**.
- **Only one player** can tame it.
- **Fighting** it requires powerful magic.
- **Taming** it requires a **special item that is hard to get**.

## The Griffin as a familiar (after taming)

- The player who tamed it can choose it as their **familiar**.
- With the griffin as familiar the player can **ride on its back**, flying through the map with no effort.
- **Limited flight:** it can only fly for a limited time; after that it **slowly descends** and goes into a
  **cooldown** (no flying until it is over).
- **Being shot down:** the cooldown can be forced early by
  - **striking the griffin down** during flight, or
  - a **Gravity Field** pulling it to the ground (the exact use case the Gravity Field was made for).
  A forced landing starts the cooldown, but in that case the **cooldown is shorter**.

## The nest and the eggs

- The griffin has a **nest**. While the griffin is **asleep**, sneaky players can **steal an egg** from it.
- A stolen egg **hatches into a baby griffin**.

## Baby griffins – small familiars

- Baby griffins can also be chosen as **familiars**.
- They **never grow up** and **cannot fly**.
- With a baby griffin selected: press **Space while airborne** and it **appears for the player to hold onto**.
  It **can't lift the player's weight**, but it **slows the fall**, which makes aiming in the air easier
  (a counterpart to scoping or casting mid-jump / after dashes, Bounceshroom launches, etc.).

## Ownership rules

- **Tamer leaves the server:** the griffin returns to its boss position, ready to be fought (or tamed) again.
- **Tamer dies:** the familiar is **transferred to the killer** – the griffin is a boss, so someone always
  has it.
- **Baby griffins are different:** when their owner dies they are **not** transferred; they **drop as a
  familiar token** (an item lying in the world that anyone can pick up). How familiars are represented while
  not in use (token item, inventory slot, ...) is not decided yet.

## Stealing eggs

- A sleeping griffin **notices a player who gets too close** (natural proximity detection).
- So eggs have to be taken without walking up to the nest, e.g.:
  - **grabbing an egg with the Spectral Chain** from a distance (eggs as `chainable` objects),
  - a **camouflage spell** (new spell idea) to sneak in,
  - **distracting the griffin with a Decoy**.
- **A Decoy can drive the griffin away** from the nest (it chases the illusion).
- **When the griffin leaves its nest** (tamed and ridden away, chasing a decoy, or fought away from it), the
  **eggs lie there unprotected** – so a player fighting or taming the griffin is a perfect window for
  someone else to snatch an egg.

## The nest: Griffin's Crown

- A ring of leaning rock spires with gaps, the nest on a rock pedestal in the middle (shape preview:
  https://claude.ai/artifact/LFFdVtSfkAJxbxzZon9za7).
- **Hidden inside a forest:** it sits in a sunken hollow deep in a big forest. You find it by following the
  forest – you suddenly stumble on something else.
- **Client-side hiding:** each client only shows the Crown (spires, pedestal, nest, eggs, bones, light shafts)
  while its own player is **inside the forest within a zone radius** of the nest (~85 m in the prototype).
  Everyone else gets **stand-in trees** over the opening instead, so from outside (meadows, mountains, the air)
  it is plain forest. This applies **always**, also after it was discovered – you can only ever see the nest
  while in the forest. The swap happens deep enough in the forest that the trunks hide the pop. (Gameplay
  collision, eggs and the griffin stay real on the server; only the visuals swap.) Game-look prototype:
  https://claude.ai/artifact/MVPbFh5yZMQfHBw5J6Sg3Q
- **Discovery:** on the map the forest is drawn fully filled over it. When a player first steps within a
  certain radius of the nest, it is **revealed on everyone's map** (inked in) with a **notification**
  ("<name> discovered Griffin's Crown").

## Open questions

- **Where is the nest?** (A tall peak was suggested; the user isn't sure the peak is the right place. The
  stealth role suggests a sheltered spot with cover and approach routes rather than an exposed summit.)
- **What happens when the griffin is fought (defeated) instead of tamed – not decided yet.** Respawn? Reward?
- What is the special taming item, and how is it obtained?
- Detection details: radius, line of sight, does casting / noise / running wake it?
- How familiars are represented when not in use (the "familiar token" for baby griffins).
- How many eggs are there, and how often do they come back?
- Can a rider cast spells while flying? Can other players hit the rider and/or the griffin separately?
- Does a familiar slot hold one familiar at a time (griffin *or* baby griffin)?

## Notes (implementation thoughts, not decisions)

- **Networking:** the griffin is the first server-side creature. The server should own it (AI, position,
  health, who tamed it, sleeping state, eggs) in `server.gd` `_tick()` and broadcast its state like
  player states; clients interpolate it like `RemotePlayer`. Taming / egg theft = "first asker wins",
  like world-item pickups.
- **Riding:** while mounted, the rider's client drives the griffin (like its own player body) and sends its
  state; the server relays and keeps ownership. Flight time / cooldown live on the rider's client but are
  sent so others see the descent.
- **Gravity Field / strikes:** the Gravity Field already forces `Player.slam`; a mounted rider inside it
  would end the flight and start the shortened cooldown. "Striking down" needs a hit threshold or a damage
  burst during flight.
- **Baby griffin glide:** in `Player._physics_process`, while airborne and Space held with the baby
  familiar, clamp the downward velocity (e.g. −2…−3 m/s) and show the baby above the player's hands
  (first person) / above the avatar (others: a state flag like `FLAG_GLIDING`).
- **Familiars** suggest a general system (a familiar slot in the inventory UI, an item type for eggs /
  taming items) that other creatures can reuse later.
- The nest, its eggs and the griffin's territory fit the planned **reserved structure plots** in world
  generation.
