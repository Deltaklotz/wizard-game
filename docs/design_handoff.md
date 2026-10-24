# Game Design Handoff — Magic Battle Royale

> Saved 2026-10-24 for later. A summary of a design conversation Corvin had with Claude in a separate chat.
> It is **not a task list or a spec**. Nothing here is decided unless marked as such. Treat it as shared
> background so we can keep discussing the design, and only move to code when Corvin asks for it.
>
> Provenance markers:
> - **[Corvin]** = Corvin's own idea or decision
> - **[Suggested]** = Claude's suggestion from that chat, not yet adopted
> - **[Open]** = unresolved question

---

## 1. Core concept

- **[Corvin]** Hunger-Games-style battle royale with magic. Everyone starts in a circle with nothing, runs out
  into the map, finds spells and equipment, and fights to the death until one player is left.
- **[Corvin]** Corvin's vision of the features and mechanics is clear. The struggle is keeping everything
  coherent and deciding what fits.
- **[Corvin]** Feedback from other people: they didn't understand the vision, or whether the game is PvE or PvP.

### Framing that came out of the chat
- **[Suggested]** It's a **PvP battle royale**. PvE exists only to feed PvP. Lead every pitch with the win condition.
  - Pitch draft: *"A magic battle royale. Loot spells from the world, combine them, be the last one standing."*
- **[Suggested]** Write 3 design pillars and run every feature through them. Draft:
  1. Fights are won by smart spell use, not luck
  2. Every match is a power climb from nothing
  3. A new player understands it in 30 seconds
- **[Suggested]** Next step: a one-page design doc (pitch, pillars, acquisition table) before adding more features.

---

## 2. Spell acquisition

- **[Corvin]** Wants bosses, dungeons, crafting, trading and random map spawns as ways to get spells.
- **[Corvin]** Worried this is too complex for new players to orient in.
- **[Corvin]** Considering replacing full crafting with **spell fusion**, but unsure if it's a bandaid. Concerned
  that crafting feels hollow when items are only crafting material and have no use of their own.

### Suggestions from the chat
- **[Suggested]** Every method gives the same thing (spells), but each has a distinct risk/reward role:

| Method | Risk | Reward | Role |
|---|---|---|---|
| Random ground spawns | low | common spells | early game, self-explanatory |
| Dungeons | medium | uncommon/rare | optional mid-game |
| Bosses | high, loud/visible | rare/legendary | creates PvP hotspots (airdrop-like) |
| Fusion | costs 2 spells | 1 stronger/hybrid spell | decisions, build depth |

- **[Suggested]** Fusion fits the genre better than crafting. Matches are short (~15–25 min), and there are no
  pure materials: every spell is usable on its own *and* an ingredient. The tension is "keep two decent spells
  vs. gamble on one strong one."
- **[Suggested]** Cut player-to-player trading: it barely makes sense in last-man-standing. Alternatives are an
  NPC shrine/merchant (trade a spell plus a risk for a random better one), or trading only in a future team mode.
- **[Suggested]** Teach progressively: ground loot needs no explanation, dungeons are visible landmarks, and
  fusion gets a prompt the first time a player holds two spells.
- **[Open]** Fusion rules (what combines with what, deterministic vs. random results).

---

## 3. Match opening / early deaths

- **[Corvin]** Concern: the map is fairly small, so players who run the same direction die early to someone who
  got lucky with a basic spell while they had no defense. This undermines the "clever spell battles" idea.
- **[Corvin — likes]** **No-damage timer that ends with a bell** at the start.
- **[Corvin — agrees]** **Starter kit** (weak attack plus one defensive tool like a shield or blink) and
  **high-risk/high-reward center loot** (Cornucopia-style). Together these make early deaths a *chosen* risk
  rather than bad luck.
- **[Suggested]** Low early lethality: common spells take several hits to kill, and real power comes from rare
  and fused spells.
- **[Suggested, alternative]** Launch or glide down from the sky islands and pick a landing spot instead of the
  start circle. Not adopted.

---

## 4. Dead players (playing with friends)

- **[Corvin]** Problem: in a 25-min round, dying at minute 5 is fine with random queueing (you just requeue),
  but with friends dead players need something to do.
- **[Corvin] ideas:**
  - Dead players come back as **ghosts** that assist living players
  - **Respawn at spawn after a timer**, with the rule still last-man-standing: you have to eliminate the last
    player before new ones spawn
  - Dead players can **become very advanced spells** that act on their own when used
  - Dead players can **take over hostile creatures' bodies** to keep fighting

### Suggestions from the chat
- **[Suggested]** Avoid general respawn timers: if people keep coming back, the match never ends and
  elimination loses its weight.
- **[Suggested]** Layered system:
  1. **Early respawn window:** death in the first ~5–7 min gives one respawn at the map edge. This targets the
     early-death problem directly.
  2. **Ghost after that:** spectate, and **possess creatures**. Possessed creatures should be **hostile to
     everyone**, so friends in random lobbies can't effectively team up against solo players.
     - Optional **revenge bonus**: more damage against your killer.
  3. **Soul spell** (Corvin's "become a spell" idea): on death a soul spell drops. Whoever picks it up gets a
     powerful autonomous spell controlled by the dead player's ghost. An enemy might pick it up, and a "betray"
     option could create chaos and stories.
- **[Suggested]** Build order: 1 + 2 first, add 3 later.
- **[Open]** Exact respawn window, ghost abilities, possession rules, soul spell balance.

---

## 5. Zone / match escalation

- **[Corvin]** **The map marks every player**, so a shrinking zone isn't needed for finding people.
- **[Corvin]** Does **not** want it to feel like a copy-paste Fortnite.
- **[Suggested]** Seeing everyone solves *finding* but not *forcing* fights; careful players can avoid each other
  forever. Some escalation over time is still needed, but it doesn't have to be a circle.
- **[Suggested]** Hunger-Games-themed **arena events** (like the gamemakers):
  - Sky islands fall one by one (high ground disappears)
  - Mana storms sweep random regions and damage anyone caught in them
  - A final boss awakens in the center at minute X with the best loot
  - Night falls and creatures get aggressive
- **[Suggested, alternative]** Instead of showing everyone constantly, do location **pings every X seconds** that
  get more frequent as the match goes on. This builds tension and allows stealth plays.
- **[Open]** Whether to keep constant visibility or move to pings; which events to use.

---

## 6. Map

### Current state [Corvin]
- Square landscape generated from erosion maps plus Perlin noise
- Grouped forests and flying **sky islands** on top
- Fairly **open** and fairly **small**; lots of free space
- Worry: POIs will feel crammed onto the map instead of natural
- Agrees the map needs to be broken up into places for fighting, but unsure how, because it's not easy

### Placement suggestions
- **[Suggested]** Every POI needs a reason to be there. Use the terrain data to score locations per POI type
  (slope, height, distance to water): towers on peaks, villages in flat valleys by rivers, dungeons in cliffs,
  a boss in a crater.
- **[Suggested]** **Loot gradient**: poor at the edges, rich in the center, sky islands as the high-risk endgame
  (reachable via updrafts or portals).
- **[Suggested]** **3–5 huge landmarks** with distinct silhouettes, visible from anywhere, for orientation.
- **[Suggested]** Paths between POIs and rivers following the erosion, so it reads as a world.
- **[Suggested]** Keep empty space between POIs. Use Poisson disk sampling with a minimum distance so things
  don't clump.

### Breaking up open terrain for spell fights
- **[Suggested]** Ridged noise plus domain warping for ravines, ridges and cliffs, masked so some areas stay open.
- **[Suggested]** Rock/boulder clusters via Poisson disk sampling, denser near POIs.
- **[Suggested]** Ruin prefab kits (walls, pillars, broken towers) placed at POIs as cover.
- **[Suggested]** Deliberately different fight zones: open fields (long range), forests (close range), ruins
  (corner fights), sky islands (vertical, fall risk).
- **[Suggested]** Spells that create cover (earth wall, ice pillar, fog), so cover becomes part of the skill system.
- **[Suggested — tool idea]** A **sightline debug script**: sample random points, raycast in all directions, and
  color the map by average view distance. Red spots are too open, so add cover there. This turns "it feels open"
  into measurable data.

---

## 7. Misc context
- Corvin animates the game himself. Humans go well, animals are harder. He originally wanted a griffin as a
  creature (shelved – see `docs/concepts/griffin.md`).

## Possible next conversations
- Writing the one-page design doc / pillars
- Detailed fusion rules
- Detailed ghost / possession / soul spell rules
- Arena event system design
- Sightline debug script and procedural POI placement in the actual engine
