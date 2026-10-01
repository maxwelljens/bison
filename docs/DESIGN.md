# Bison — Design

Holistic design context for `AGENTS.md`. The decisions here were settled
in a grilling session on 2026-09-27 and are binding for feature scope
unless explicitly reopened. Open/deferred items are marked **[OPEN]**.

---

## 1. Axioms

- **Genre fusion:** Rain World-style fragile-protagonist survival and
  cycle pressure, fused with extraction-shooter looting (Tarkov-style
  chest rummage and item curation).
- **Permadeath:** death ends the run — total loss of haul, position and
  builds. No lineage, no soft deaths; every run is a fresh colony.
- **Every cycle is one day**, 06:00 (day start) to 21:00 (dusk/night
  start) on a visible **digital clock**. After dusk, roaming night
  killers make the wilds essentially lethal and the warren is the only
  shelter, so every day is a race home.
- **The world is the same every run** (hand-authored; mastery is
  knowledge, which fits the no-map navigation). Past runs leave no
  physical trace.
- **Art destination:** 1-bit aesthetic with CRT/scanline presentation
  (the repo's CRT shader already leans this way). Current assets are
  placeholders while systems are built.
- **Tone:** quiet melancholy, nature-documentary register. A hushed
  piano score over an ambient bed of creature calls and wind.
- **Title** "Bison" is a dev-side placeholder with no in-fiction
  meaning committed.

## 2. Protagonist and colony

- The protagonist is a **Mok** (pl. *the Moks*): a small horned blob
  creature; placeholder art today, 1-bit eventually.
- It belongs to a **colony of Moks** living in **the warren**, a hidden
  burrow system. The outer world is too wild; the warren hides.
- The colony consumes essentials. Collecting them is the protagonist's
  daily job — the core loop of the game.
- **[OPEN]** Colony presentation (ambient pool / simple rations /
  named cast) is undecided; v1 only requires the colony to be visible
  with a failure state the player can clearly read.

## 3. The loop, in order

1. Morning (06:00): the protagonist leaves the warren. The player may
   go back inside immediately and end the day — but the toll is the
   reason to stay out.
2. **Rising tolls:** every day the colony requires **more** resources
   than the last. Days are identical; there is **no entity difficulty
   ramp** — cost escalation is the only rising curve in a run.
3. The day is **one expedition** (single trip; weight is the sorter,
   not the clock): travel out, rummage chests, curate the haul, race
   the clock home before 21:00.
4. Night (21:00–06:00): home-only shelter. A **separate night-only
   bestiary** hunts the wilds; caught outside at night is near-certain
   death. Inside the warren, night is a pass-time settlement phase:
   haul is banked, tolls settle, sleep to the next morning.
5. A missed toll causes **proportional grace damage** — small shortfalls
   are small setbacks, big shortfalls accelerate collapse. Full colony
   collapse ends the run. **[OPEN]** The exact failure/health model
   (fail-health pool, member counts) is deliberately unspecified.

## 4. Economy

- **Resources:** Fruit (food) · Ember (fuel) · Salve (medicine) ·
  Slate (materials). Rare **specials** are one-off relic items used to
  build colony structures.
- **Chests are the only loot containers** until the loop is proven
  (no caches, corpses, precursor machines for now).
- **Chests fully respawn each cycle** (steady supply). The squeeze is
  cost: the rising toll forces wider looting range as days pass.
- **Looting is Tarkov-style:** rummaging a chest reveals contents over
  time; the protagonist can move away freely mid-rummage
  (**pause-on-leave** — progress holds and resumes on return). Once
  revealed, loot is taken **item-by-item with a weight audit**
  (loot-screen curation under time pressure).
- Cargo is **continuous weight**: total carried weight degrades speed
  and jump smoothly. Haul light and stay free; haul heavy and become
  huntable.
- **[OPEN]** Colony build acquisition (found relic = the build /
  spend-menu / relic-unlocks + resource costs) is deferred.

## 5. Threats

- The protagonist is **one-touch mortal**: contact with a predator
  kills outright (no health pool, no health UI).
- The first threat is a **sensing hunter** (daytime) detecting by
  **line of sight** only (no sound/memory for v1). It is **slower than
  the player**, so pure flight wins in open ground; chases become
  dangerous in **corners and dead-ends** — level design is the
  difficulty. The existing Bot/pathfinding stack will power it.
- After dusk, the **night bestiary** (separate night-only creatures)
  hunts fast, relentless and lethal. Which bodies implement it
  (dedicated spawners vs transformed day creatures) is an
  implementation choice; the *feel* is settled.
- Stealth for v1 is breaking line of sight; movement noise is ignored.

## 6. Fauna — the Mauser

- The **Mauser** is territorial fauna: docile, roving, and not of the
  Mok's kind. It is dangerous only where the player makes it so.
- **Personal space:** a bubble around its body. While the player is
  inside it *and* the Mauser has line of sight (solid tiles occlude;
  one-way platforms do not), its agitation rises; hidden or out of
  reach, it settles. Breaking line of sight genuinely defuses it — the
  §5 stealth rule holds for fauna too.
- **It turns, it does not escalate:** once the bubble has been invaded
  for too long the Mauser drops its docility and comes for the player.
  A wary beat (it stops, watches, colours) warns first.
- **Provoked it is lethal** (one-touch mortality, §5) and **faster than
  the player** — but its anger is a fixed budget that burns down; break
  contact or outlast the charge and it forgets you. It **never climbs
  ladders**, so chains are a way out.
- Its body is **not solid**: it neither blocks nor is blocked. NPCs are
  not solid by default.
- **[OPEN]** Whether "Mauser" is its in-fiction name; its place in the
  ecology (prey? pest? rival?); herds and nesting; whether anything
  can kill it.

## 7. World and navigation

- **One continuous connected world** (no zone-per-cycle, no hub metro):
  the warren is the single retreat point.
- **Geometry is interlocked:** horizontal biome rings spreading outward
  from the warren **plus vertical depth tiers** — deeper is richer and
  more lethal.
- **Falls hurt, without a health pool** (§5 stands): landing tiers
  resolve from the drop below the flight's apex — safe landings do
  nothing, hard landings stun (momentum slide, brief control lockout),
  lethal drops kill outright. Cargo-weight scaling is deferred to the
  weight increment (§4).
- **No map, no compass, no navigation aids:** navigation is a skill;
  landmarks and player knowledge carry it. The warren entrance is the
  trip's anchor (leave from there, return there by 21:00).
- **Precursors are deliberately ambiguous, hints only:** ruins, chests,
  machines. Nothing is explained directly; the world implies a grander
  past that came to ruin long ago.

## 8. Audio direction

- A continuous piano score (`Audio/Music/` — 9 pieces, ~40 minutes,
  sequential rotation) plays from boot at a hushed level over an
  ambient bed: wind, drips, distant calls. Sparse creature sounds
  carry the melancholy register.
- Music does not stand down under threat — a chase keeps the score
  running.
- **[OPEN]** Chase-reactive music: shifting track or mood while
  pursued. The music API permits it; nothing is committed.

## 9. End of run

- Death shows an **obituary**: days survived, hauls gathered, cause of
  death. It also teaches the player, through loss, where not to go.
- (No persistence of remains: every run starts a pristine world.)

## 10. Open axes (deliberate, recorded from session)

- Fauna beyond the Mauser (species, herds, ecology, in-fiction name) —
  undecided.
- Colony presentation: ambient pool / simple ration decisions / named
  cast with needs — undecided.
- Colony build acquisition mechanism — undecided (see §4).
- Colony failure/health model details — undecided (see §3).
- Species traits beyond "small horned blob"; deeper Mok lore —
  intentionally thin for now.
- Precursor hint content (what the ruins actually hold) — unwritten.
