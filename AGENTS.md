# AGENTS.md — Bison

Context and hard rules for AI agents (and humans) working in this repository.
Read this before touching anything.

## Project overview

**Bison** is a 2D pixel-art side-view platformer built from scratch.

- Engine: Godot 4.7.x (feature tag "4.7"; binary on this machine:
  `/usr/bin/godot`, 4.7.2 stable). Text scenes use `format=4`.
- Renderer: GL Compatibility (with a `d3d12` override for Windows).
- Pixel art: nearest-neighbour texture filtering
  (`rendering/textures/canvas_textures/default_texture_filter=0`),
  window stretch `canvas_items` with `expand` aspect.
- Scale: 16 px tiles; the player collision box is 12×11 px.
- Physics: 2D gravity comes from `physics/2d/default_gravity`, currently
  user-tuned to 500 px/s² — jump math must read it at runtime, never
  hardcode a value. The `3d/physics_engine="Jolt Physics"` setting is
  irrelevant to gameplay.

## Game design (read `docs/DESIGN.md`)

`docs/DESIGN.md` holds the holistic design document: genre fusion
(Rain World-like fragile survival × extraction-looter), cycle = one
day (06:00–21:00, digital clock, night is lethal, warren = only
shelter), permadeath, rising daily toll, one expedition per day,
Tarkov-style chest rummage with continuous cargo weight, one-touch
mortality, sensing-hunter threats powered by the existing
Bot/pathfinding stack, interlocked horizontal/vertical world, no map,
ambiguous precursor ruins, Mok (pl. the Moks) as the protagonist
species, Fruit/Ember/Salve/Slate as upkeep resources. Tone: quiet
melancholy, ambient-only audio, 1-bit art destination. Any feature
work must stay consistent with the loop and tone defined there;
open items in that doc are intentionally undecided — do not silently
commit them. The warren (hidden burrow system) is the colony home.

## Repository layout

- `project.godot` — engine config and input map.
- `Levels/` — level scenes. `test_level.tscn` is the main scene.
- `Scenes/` — reusable scenes: `player.tscn` (Player root: state-machine
  children, `AnimatedSprite2D`, collision, camera), `bot.tscn`
  (Bot root: `AnimatedSprite2D`, collision, `BotPathFollower`, `Pathfinder`),
  `chest.tscn` (Chest root: `Sprite2D`, `Trigger` Area2D, `Sfx`, `Vfx`)
  and `mauser.tscn` (Mauser root: `AnimatedSprite2D`, collision,
  `Pathfinder`, `Follower`, `Brain` with `Roam`/`Wary`/`Pursue` state
  children (plus `Roam/Wander`), `IdleLife`, `Animator`, `Sfx`,
  `SenseArea`/`ContactArea` detector areas,
  `DebugLabel`).
- `Scripts/` — GDScript sources: `Player/` (`player.gd`, `player_state.gd`,
  `grounded.gd`, `airborne.gd`, `player_animator.gd`,
  `player_sfx.gd`); `Pathfinding/`
  (`platformer_grid.gd`, `jump_profile.gd`, `path_data.gd`,
  `path_waypoint.gd`, `waypoint_classifier.gd`, `platformer_navigator.gd`,
  `path_tuning.gd`, `agent_kinematics.gd`, `platformer_pathfinder.gd`,
  `debug/grid_debug_draw.gd`); `Bot/`
  (`platformer_bot.gd`, `bot_path_follower.gd`); `NPC/`
  (`npc.gd`, `npc_state.gd`, `npc_brain.gd`, `npc_wander.gd`,
  `npc_roam.gd`, `npc_wary.gd`, `npc_pursue.gd`, `npc_idle_life.gd`,
  `npc_animator.gd`, `npc_sfx.gd`); `Mauser/`
  (`mauser.gd`); `Chest/`
  (`chest.gd`, `chest_sfx.gd`, `chest_vfx.gd`).
- `Textures/` — art: `Tilemap/` (tileset textures), `Tiles/Default` and
  `Tiles/Transparent` (individual tiles), `Sample.png`.
- `AGENTS.md` — this file.

## Current state (as of 2026-09-30)

- `Levels/test_level.tscn` — `TestLevel` (Node2D) contains:
  - `TileMapLayer` — tile data plus a `TileSet` with a physics layer on
	collision_layer 1 (the player's default collision mask matches it).
  - `Chest` (instance of `Scenes/chest.tscn`) — interactive loot chest:
	stand in its `Trigger` Area2D and press the `interact` action (E) to
	open. Opening swaps the sprite texture, plays a `ChestSfx` event,
	fires a `ChestVfx` particle/flash burst and emits `Chest.opened`.
	The chest stays open visually and remains interactable — every
	in-range press re-emits `opened` (the loot/inventory increment will
	hook the signal). The trigger detects the Player physics layer and filters `is Player`,
	so static tile collision never fakes proximity. Feedback components
	degrade silently when unassigned (no art/sound/refs = no errors).
	`texture_open` ships unassigned (open-chest art pending); texture
	slot defaults keep the sprite's own texture until assigned.
  - `Player` (instance of `Scenes/player.tscn`) with children:
    `StateMachine` (holds the `Grounded`/`Airborne`/`Stunned`/`Dead`/
    `Ladder` state nodes), `Animator`, `Sfx`, `AnimatedSprite2D`
    (SpriteFrames: idle/jump/run/stop/stun/dead; climb frames pending —
    the CLIMB intent falls back to idle), `CollisionShape2D`
    (RectangleShape2D 12×11 at (0, 2.5)), and `Camera2D` (follows the
    player for free by being a child).
- `Scripts/Player/` — player-driven state machine (`grounded.gd`,
  `airborne.gd`, `stunned.gd`, `dead.gd`, `ladder.gd`): the player
  gathers input once per frame (zeroed while stunned/dead), the current
  state runs the frame's physics and ends with `move_and_slide()`,
  transitions are evaluated on that fresh floor state (Grounded exits
  only when the floor is lost AND its coyote window expired, so jump
  launching stays inside it), and states emit animation intents
  (IDLE/RUN/STOP/AIR/CLIMB/STUN/DEAD) that `player_animator.gd` maps
  onto the SpriteFrames. Fall damage: the drop below the flight's apex
  resolves on the Airborne touchdown edge into safe / stun / lethal
  tiers (`stun_fall_distance`, `lethal_fall_distance`, no health pool);
  stun is a timed lockout with a friction slide, death freezes the body
  and closes any open loot session. Drop-through: one-way platform
  tiles live on their own fg-tileset physics layer (collision layer 2,
  project setting "One-way"); pressing down while standing masks that
  bit for `drop_through_time`, so the player sinks through one-ways
  while solid ground (layer 1) keeps colliding. Ladders (`ladder.gd`):
  holding up or down grabs the rung at the player's centre (no reach
  margin) — from the floor beside a chain or as a mid-fall catch that
  cancels the drop (down then descends) — up/down climb, release hangs,
  Space jumps off at full power, and left/right shimmies along the rung
  tile at run speed (moving out of the tile steps off). The grab keeps
  its x (no snap). The climb top stops at the first standable surface
  at/above the top rung (pull-up onto landings) or hangs at the chain
  edge; ladder frames reset the fall apex so catches and step-offs
  never measure the whole chain as one fall.
  `player_state.gd` is the base class
  (`setup`/`enter`/`exit`/`physics_process`).
- Sound effects: `player_sfx.gd` (`PlayerSfx`) sits under the player
  like the Animator and never touches audio from the states. The player
  forwards the state intent (`set_intent`), floor state (`set_grounded`)
  and events: Grounded sets `player.jumped_this_frame` at jump launch
  (the player plays JUMP and clears it), and the player plays LAND,
  HARD_LAND or DEATH by fall tier on the Airborne touchdown edge.
  Footsteps tick while RUN + grounded
  (fixed `footstep_interval`); STOP plays on its one-frame intent edge.
  Sounds play through a code-created round-robin pool of
  `voice_count` `AudioStreamPlayer`s (overlaps never cut). New events
  scale by adding an Event entry, an `@export` stream and a match arm in
  `_stream_for`. `sound_stop` ships unassigned (no skid asset in the
  Kenney pack); unassigned streams silently skip their event.
- Input map (`project.godot`): `move_left` (A/←), `move_right` (D/→),
  `jump` (Space only), `move_up` (W/↑, ladders only — inert elsewhere),
  `move_down` (S/↓). Keyboard only, no gamepad bindings.
- Tile colour system: both tilesets carry a Color custom data layer
  named `color` (TileSet editor → Custom Data Layers). Authoring a tile's
  colour there and running a bake applies it to rendering:
  `Scripts/Tilemap/tile_palette.gd` (`TilePalette`, `@tool` Node2D, one
  per TileMapLayer in the level) copies each placed tile's custom-data
  Color onto its `TileData.modulate` when the `bake` flag is toggled in
  the Inspector (self-resetting, so baking never runs on scene load —
  the tilesets are shared resources). Untagged tiles read the layer
  default `Color(0, 0, 0, 1)` and are reset to white on bake, so pure
  black is not authorable as a tint. Custom data is the source of truth;
  modulate is derived — re-bake after editing values. No runtime code,
  no shader; per-cell variation is deliberately out of scope (per-tile
  modulate is shared by every cell placing that tile).
- Ladder tiles: fg-tileset tiles carrying a `ladder` bool custom data
  layer — the flag alone makes a rung, no collision is required (rungs
  hang in open air). A run of contiguous flagged cells in a column is
  a chain. Standing surfaces are optional: a tile with any collision
  polygon (e.g. a one-way platform) at or directly above a chain's top
  rung is the landing the player pulls up onto. The block's rung and
  bottom tiles carry the flag; caps like (0, 3) are decoration
  (`z_index` only).
  `Scripts/Tilemap/ladder_map.gd` (`LadderMap`) is the single query API
  (is-ladder, run extents, cell edges, standable tops) used by the
  player, the grid, the pathfinder and the bot.
- Physics layers (`project.godot`): 1 `World` (solid tiles), 2 `One-way`,
  3 `NPC`, 4 `Player`. NPC and Player bodies mask only World+One-way, so
  **NPCs are not solid** — creatures and the player pass through each
  other while both collide with tiles. Detector areas that care about the
  player (chest `Trigger`, Mauser `SenseArea`/`ContactArea`) mask the
  Player layer and filter `body is Player`.
- NPC framework (`Scripts/NPC/`) — a generic finite-state-machine stack
  mirroring the player's (`player_state.gd` pattern): `npc_state.gd`
  (`NpcState` base: `setup`/`enter`/`exit`/`update_pressure` plus a
  custom `physics_process` that is never engine-ticked), `npc_brain.gd`
  (`NpcBrain`: the machine host — senses the player (bubble + LOS ray on
  the World layer only), owns the 0..1 pressure value and cross-state
  rates, executes transitions (states call `brain.request(next)`,
  applied after the state's frame, like the player's post-state
  transition block), drives the tint lerp and debug label),
  `npc.gd` (`Npc extends PlatformerBot`: generic body — `aggressive`
  flag and touch-kill through the overridable `on_contact_player` hook,
  the seam for non-lethal species), `npc_wander.gd` (`NpcWander`:
  reusable wander component), `npc_idle_life.gd` (`NpcIdleLife`:
  breathing bob and look-around component), and three reusable states: `npc_roam.gd`
  (wander + agitation accumulation), `npc_wary.gd` (wary beat: face, tint, give ground),
  `npc_pursue.gd` (chase + rage drain — a fixed chase budget; `calm_at`
  stands it down with the meter reset to 0). Presentation mirrors the
  player's split: `npc_animator.gd` (`NpcAnimator`: Intent enum
  IDLE/WALK/CHARGE/WARY/RETREAT/JUMP, exported animation-name-per-intent
  map with missing→idle fallback, and `set_facing` — it OWNS `flip_h`
  for NPCs; the motor's heading writes are corrected by the brain's
  end-of-tick forwarding) and `npc_sfx.gd` (`NpcSfx extends AudioStreamPlayer2D` — SPATIAL: the node is the
  carrier and voice 0, plus `voice_count - 1` spatial child voices
  mirroring its native knobs (`volume_db`, `bus`, `max_distance`,
  `attenuation`, `panning_strength`); round-robin pool so events never
  cut each other, `NONE`/null-stream silent skip, LAND floor-edge / STEP
  cadence / IDLE_CALL gated by `not npc.aggressive` — silence under
  threat).
  States declare `intent` (rewritten each frame), `facing_to_player`
  and `enter_sfx`; the brain forwards intent+facing at the END of its
  tick (airborne → JUMP) and plays `enter_sfx` inside `_transition` —
  the exact `player.gd` presentation pattern. `NpcWary`'s old
  `_face_player` retired into `facing_to_player`. The brain references only
  `NpcState` and states are direct `NpcState` children, so new NPCs
  reuse the machine untouched: copy the `Brain` subtree of
  `Scenes/mauser.tscn`, wire `npc`/`follower`/`pathfinder`, retune per
  node. A new behaviour is one `NpcState` script; a new archetype adds
  states without editing `NpcBrain`.
- The Mauser (`Scenes/mauser.tscn`, `Scripts/Mauser/mauser.gd`) — the
  first NPC: a configured instance of the NPC framework — docile
  territorial fauna (see DESIGN.md §6). `mauser.gd` is the thin species
  hook (`class_name Mauser extends Npc`, species behaviour belongs
  there); the `Brain` tree carries all tuning (see the Mauser tuning
  reference below) and a `test_level.tscn` instance is placed for play
  feedback. Its follower runs `click_to_move` off and its body carries
  `can_climb = false` (the species trait): it jumps gaps but never climbs
  ladders, so chains are an escape. Its body also carries weighted
  momentum (`acceleration = 180.0`, `friction = 120.0` scene overrides —
  the motor always ramped; the creature was inheriting snappy 1200/1500
  defaults) and an `IdleLife` component (breathing bob, occasional
  glances); `Wander` micro-stalls ride on `BotPathFollower.hold_for`.
- `Player.kill()` — public one-touch death entry for external causes
  (creature contact, traps); fall deaths keep using the internal tiers.
- Pathfinding retarget semantics (probe-fixed 2026-09-30): `BotPathFollower.move_to` **commits to in-flight jumps** — while the bot is airborne a new target is queued (newest wins; refused routes change nothing) and replanned on landing, and mid-flight input release is suppressed (the in-flight steer continues), so rapid retargeting never truncates a jump or dead-sticks a body mid-air. Goal snapping (`PlatformerGrid.snap_to_standable`) is vertically weighted and side-aware — `PathTuning.goal_snap_side_cells` (8) and `goal_snap_vertical_weight` (3.0), with `goal_snap_max_cells` bounding the descent — and the navigator refuses unsupported goals (no ground/one-way below and not a ladder rung): a target floating over a gap snaps to a landing lip at height or the route is refused, never the chasm floor. Regression harness (throwaway, copied back into the project root to run): `/tmp/opencode/bison-probe-retarget/_probe_retarget.gd` — stairs/gap/mid-air retarget assertions, ~10 s headless. Takeoff honesty (2026-10-01, momentum increment): `_matched_impulse` sizes from the measured launch velocity clamped by `BotPathFollower.launch_speed_floor` (0.5 of `move_speed`, standing-start falls back to full speed) and `PathTuning.takeoff_speed_factor` (0.85) derates the drift envelope for momentum-weighted bodies; landed-arc advance accepts same-direction overshoots on supported ground (weak friction + strict LAND return used to walk momentum bodies back off lips); `BotPathFollower.hold_for(duration)` pauses steering without dropping the route (never while `_launched`/mid-air; grounded `move_to`/`stop` cancel it). Advance-rule nuance (ladder fix, 2026-10-01): `_onward_dx` stops at a same-column `CLIMB` — a chain shares its grab column, so scanning past it pointed back down the approach and accepted the grab-WALK early, wedging the body off-centre against 1-cell shaft walls; and a climb-catch whose next waypoint is a CLIMB (previous not) advances into the climb rather than deadlocking a held jump. Probe suite (reconstructed after a server wipe) archived at `/tmp/opencode/bison-probe-{retarget,momentum,caps,wary,present,ladder}/` (descent scenarios live under momentum) — 7 harnesses, 157 assertions.
- Scene-level tuning overrides on the Player node (user-tuned in the
  Inspector; the scene is the source of truth, currently
  `move_speed = 50.0`, `acceleration = 250.0`, `friction = 130.0`,
  `jump_velocity = -150.0`). Script defaults differ
  and only apply where a scene does not override them.
- **Inspector-exposed parameters are volatile — do not chase them.** The
  user tunes scene-exported `@export` values constantly in the editor
  and they routinely differ from session to session (capability flags,
  radii, thresholds, speeds, tints, audio slot assignments, …).
  Differences in such values are routine tuning/testing state, NOT
  findings: do not flag them as regressions, do not revert them, and do
  not "restore documented values" unless the user asks. Script defaults
  in the tuning tables are code and stable; scene-level values are the
  user's live workspace.
- Pathfinding (increment-based delivery): `Scripts/Pathfinding/` foundations
  landed (typed waypoints, jump model, TileMapLayer→grid extraction) and
  headlessly probed, plus a `GridDebugDraw` overlay and a `Pathfinder` route
  preview (both draw in the editor and in-game) for visual verification.
  Solver landed and probe-verified; a 2026-09-30 architecture pass split it
  into pure modules behind one seam: `platformer_navigator.gd`
  (`PlatformerNavigator`, the jump-lattice A* engine, stateless between
  calls — per-query state lives in its `Search` value),
  `waypoint_classifier.gd` (`WaypointClassifier`: state chain → typed
  waypoints; replayable from synthetic chains in tests),
  `platformer_grid.gd` (the single world model: states, ladder bits,
  `has_standable_top`, `snap_to_standable`, `is_strip_blocked`), and the
  `path_tuning.gd`/`agent_kinematics.gd` value objects. The
  `platformer_pathfinder.gd` node is now a thin scene adapter exposing
  `route(from, to, agent)` and `is_drift_blocked` (plus `tuning` resource,
  preview and overlay); the old `find_path`/`get_cell_size`/`rebuild_grid`
  surface is gone — callers pass an `AgentKinematics` snapshot
  (`PlatformerBot.kinematics()`). Bot
  (`platformer_bot.gd`) + follower (`bot_path_follower.gd`) landed: own
  movement (including a ladder mode mirroring the player's climbs),
  typed-waypoint execution, click-to-move (LMB), stuck-watchdog repath. Feedback round 1 fixed: real jumps over gaps (parity applied to
  all air moves), air drift guard (stripe check for columns beside arcs),
  exact jump height (full cut at the path's apex), jump launch position
  check (x+y), and fall-throttle semantics (`fall_threshold` counts fall
  cells, not jump values). Feedback round 2 fixed the drift guard's
  corridor (it wrongly included the support-floor row under takeoff and
  landing cells, blocking every gap crossing and ledge drop). Feedback
  round 3 scoped the drift guard to mid-air steering only (at the ledge
  edge the face below the takeoff column blocked the step-off). Feedback
  round 4 made jump reachability physical: the solver bounds airborne drift
  by the parabola envelope derived from the agent's jump_velocity, gravity
  and move_speed (`PlatformerJumpProfile`), so tuning jump velocity
  honestly changes which arcs exist). Feedback round 5 fixed landing
  clearance: releasing the jump now clamps upward speed to
  `jump_release_speed` instead of zeroing it, so the bot rises ~1 tile past
  the path's apex and clears landing lips (the tutorial's release-cap
  mechanism). Feedback round 6 fixed one-way platforms: the jump apex now
  includes the landing cell (one-way tops sit above the last airborne cell,
  so jumps released a tile short), and stepping down through a one-way's
  surface is classified as DROP_THROUGH (needs the press-down action).
  Feedback round 7 made gap jumps right-sized: the follower computes a
  matched ballistic impulse per jump (v0 = dy/T + g·T/2 with T = dx/v_x,
  +10% margin) and the bot fires it as a one-shot impulse, so gaps get
  hops proportional to their width. Targets not on the descent side of any
  single-impulse arc (high nearby ledges) keep the classic full jump.
  The Pathfinder's map comes through the `navigation` group: the active
  TileMapLayer joins it (see `test_level.tscn`'s `Map/Foreground`) and the
  Pathfinder auto-resolves it on its first `_process` tick when `tilemap`
  was not assigned explicitly — strict validation warns when the group
  holds anything other than exactly one TileMapLayer, and reassignments
  via the `tilemap` setter invalidate the baked grid and refresh the
  preview. `Levels/test_level.tscn` itself needs no Bot wiring; dropping
  `bot.tscn` into any level works if that level tags exactly one
  TileMapLayer with the group.
  Ladder slice: the grid bakes a per-cell ladder flag through
  `LadderMap` (orthogonal to the collision states, since a rung tile may
  also carry a one-way surface) and the solver prices CLIMB waypoints:
  vertical chain edges at `move_speed / climb_speed` (`climb_speed` rides
  on `AgentKinematics` (the profile is derived inside the navigator),
  `PathTuning.climb_grab_cost` prices grab, top-out and
  step-off transitions), grabs in place or as mid-air catches, descend
  grabs through a one-way landing onto the rung below it, and top-outs
  that mirror `ladder.gd`'s stop rule (stand on the rung's own top face,
  or rise through a one-way landing above the chain and stand on it).
  Off the chain: step-offs onto crossings beside a rung or the chain-base
  floor, and drop/jump edges that reuse the airborne lattice.
  `GridDebugDraw` tints ladder cells (`show_ladder`/`ladder_color`). The
  follower executes CLIMB waypoints end to end: held-intent grabs (in
  place, descend grabs and real mid-air catches on the first rung
  touched), climbs toward each rung, and leaves at the route's explicit
  exit cell (top-out holds up, base drop holds down, foot-height
  crossings shimmy out, higher crossings rise until the feet reach the
  exit surface). Exit decisions come from the route's waypoint cells
  only (the bot's live centre cell straddles cell boundaries at the
  chain top and flips branches per frame), and mid-chain falls are
  only routed where a side is open to shimmy off. Climb exits carry a walk waypoint at the stand/step-off cell
  so run compression cannot swallow it, catches replace the landing
  marker with the catch cell's CLIMB, and jump-offs keep the matched
  impulse sizing. Feedback round 8 fixed drop-through classification:
  the airborne run now names its action by the first step off the launch
  state (step up = JUMP takeoff, step down out of a grounded run =
  DROP_THROUGH through the one-way cell below the launch, anything else
  = FALL) instead of by jump value — a fall starts at the lattice peak,
  which overlaps the takeoff range once a profile jumps 2+ cells, so
  drops through one-way platforms were misread as jumps and the bot
  hopped on the platform instead of phasing through. Ladder drop-offs
  classify as FALL through the same rule.
  Awaiting re-verification.
- Known gaps (intentionally out of scope so far): no camera limits, no
  death UI/permadeath flow (DESIGN.md §9 unwired), no fall-specific art
  (AIR still maps to the jump frames). Mauser: tile-placeholder animation frames (`idle`/`move`/`jump` only —
  no wary art yet); its creature sounds are hand-auditioned general
  Kenney effects pending real creature audio (see the Sfx table below). Per-agent pathfinding capability flags
  landed (`can_jump`/`can_climb`/`can_drop_through` on `PlatformerBot`,
  carried into the search through `AgentKinematics`): each prunes the
  matching edge family from the navigator's search, so the Mauser's
  "never climbs ladders" rule is now `can_climb = false` on its body
  instead of a route filter on `BotPathFollower`.

## Coding directives (MUST follow)

1. **Tweakable values are `@export`ed.** When creating a script, any variable
   that is worth tweaking (speeds, jump height, timers, damage, drop rates,
   …) MUST be exposed as an `@export` variable so it can be tuned in the
   Inspector without code edits. Group with `@export_category` /
   `@export_subgroup`, constrain with `@export_range`, and keep units in
   mind (px, px/s, px/s², s).

2. **Node references are `@export`ed, never `$Node`.** When connecting
   systems to each other — including a script referencing its own child
   nodes — expose an `@export var ref: SomeNodeType` and wire the actual
   node in the scene (Inspector, or `node_paths=`/`NodePath(...)` when
   hand-editing; see appendix). Do NOT use `@onready var x = $"..."` or
   `get_node()`; that syntax is brittle and annoying to debug. An
   unassigned exported reference is visible in the Inspector; a broken
   `$` path is not.

   ```gdscript
   # Do
   @export var sprite: Sprite2D

   # Don't
   @onready var sprite: Sprite2D = $Sprite2D
   ```

3. Typed GDScript: annotate variable types, parameter types and return
   types. Indent with tabs (Godot default).

4. Prefer exported tuning over magic numbers inside logic; keep scripts
   scene-agnostic (no hardcoded world positions or assumptions about
   scene structure beyond the exported references).

## Delivery process (MUST follow)

- Build features in subsystem increments — never implement everything in
  one shot.
- After each subsystem is functional and headlessly verified, STOP and hand
  it to the user for feedback before building the next one.
- Rationale: unverified groundwork makes everything built on top of it
  potentially broken; direction corrections are cheap early and expensive
  late.

## Testing policy (MUST follow)

Game development is highly feedback-sensitive; the agent cannot judge
feedback, only the user can. Therefore:

- Verify work ONLY with headless runs that prove there are no
  syntax/parse/load errors. Nothing else.
- Allowed: `godot --headless --path . --check-only --script res://<script>.gd`
  and a one-frame `godot --headless --path . --quit`.
- Allowed: basic probe tests in a vacuum — a throwaway project or script
  (e.g. under `/tmp`) that exercises one mechanism in isolation and prints
  a result, used for behaviour that cannot be reasoned about safely
  (serialization round-trips, API semantics).
- Forbidden: playtesting, judging feel/balance/rendering, "running the game
  to see if it works". Deliverables end with a short manual checklist for
  the user to run in the editor.

## Running and verifying

- Run the game: `godot --path .`, or open the project in the editor.
- Syntax check: `godot --headless --path . --check-only --script res://Scripts/Player/player.gd`
- Load check: `godot --headless --path . --quit`
- Note: headless/editor runs may normalize scene files (stamp `uid=` onto
  ext_resources, generate `*.gd.uid` companions). Expected and harmless.
- Note: `--check-only --script` cannot resolve the `Loot` autoload
  identifier (check-mode scoping), so checking `player.gd`, `dead.gd` or
  `mauser.gd` reports `Identifier not found: Loot` out of `dead.gd` and
  cascades. Pre-existing; the `--quit` load check covers those scripts.
- Note: game runs do not rescan scripts — after adding a `class_name`,
  rebuild `.godot/global_script_class_cache.cfg` once with
  `godot --headless --path . --editor --quit`, or dependents fail with
  `Could not find type ...`.

## Appendix: hand-editing Godot files

Verified facts about Godot 4.7.x as used in this project (probed 2026-09-25).

- **Scenes** (`format=4`): nodes carry `unique_id=` attributes. Preserve
  them when editing existing nodes; do not invent them for new nodes (the
  editor assigns them).
- **Script attachment**: add
  `[ext_resource type="Script" path="res://Scripts/x.gd" id="3_plr"]` and
  `script = ExtResource("3_plr")` on the node. The editor adds
  `uid="uid://…"` and writes the `.gd.uid` companion on the next save;
  path-only references load fine meanwhile.
- **Node reference properties** (`@export var sprite: Sprite2D` etc.): a
  scene stores them as `NodePath`, but resolves them to real node
  references ONLY when the property is declared in the node header:

  ```ini
  [node name="Player" type="CharacterBody2D" ... node_paths=PackedStringArray("sprite")]
  sprite = NodePath("Sprite2D")
  ```

  Without the `node_paths=PackedStringArray(...)` entry the loader silently
  drops the value and the property stays `null`. Paths are relative to the
  node owning the property (`"Sprite2D"` = direct child; a sibling is
  `"../Name"`, the parent is `".."`).
- **Input map** (`project.godot`): events serialize as
  `Object(InputEventKey,"resource_local_to_scene":false,…,"keycode":0,"physical_keycode":<code>,…)`.
  Useful physical keycodes: `A` 65, `D` 68, `W` 87, `Space` 32,
  `←` 4194319, `↑` 4194320, `→` 4194321. Use `physical_keycode`
  (layout-independent) and leave `keycode` 0.
- **Native name collisions**: Godot 4.7's `PhysicsBody2D` already defines
  `get_gravity() -> Vector2`; redefining `get_gravity()` on a body is a
  parse error. Use distinct names (e.g. `get_gravity_strength()`).
- **Startup timing**: exported node refs may still be null inside `_ready`
  of non-root nodes, and a `call_deferred` scheduled from `_ready` did not
  fire in our probes. For startup work that needs refs, use a one-shot
  `_process` hook (proven to work) or property setters.

## Player tuning reference

Script defaults (`Scripts/Player/player.gd`; `coyote_time`,
`jump_buffer_time` and `run_min_speed` live on `PlayerGrounded` in
`Scripts/Player/grounded.gd`, `stun_time` on `PlayerStunned` in
`Scripts/Player/stunned.gd`, `stop_hold_time` on
`Scripts/Player/player_animator.gd`, `voice_count`, `footstep_interval`
and `volume_db` on `Scripts/Player/player_sfx.gd`); scene overrides on
the Player node take precedence.

| Property | Default | Meaning |
|---|---|---|
| `move_speed` | 130.0 px/s | top run speed (~8 tiles/s) |
| `acceleration` | 1200.0 px/s² | how fast `move_speed` is reached |
| `friction` | 1500.0 px/s² | deceleration without input |
| `jump_velocity` | -300.0 px/s | jump impulse (apex ≈ v²/(2·g); tile height depends on current gravity) |
| `coyote_time` | 0.1 s | jump allowed this long after leaving a ledge |
| `jump_buffer_time` | 0.1 s | jump pressed this long before landing fires on touchdown |
| `jump_cut_multiplier` | 0.5 | upward velocity kept when jump is released early (short hop) |
| `max_fall_speed` | 600.0 px/s | terminal velocity clamp |
| `stun_fall_distance` | 64.0 px | drop below the flight's apex at/above which a landing stuns (~4 tiles) |
| `lethal_fall_distance` | 160.0 px | drop below the flight's apex at/above which a landing is lethal (~10 tiles) |
| `run_min_speed` (`PlayerGrounded`) | 10.0 px/s | releasing move input at/above this speed shows the stop animation |
| `stun_time` (`PlayerStunned`) | 0.75 s | control lockout after a hard landing (momentum slides under friction) |
| `drop_through_time` | 0.25 s | seconds the one-way bit stays masked after a press-down (~0.18 s clears the 8 px platform top) |
| `climb_speed` | 60.0 px/s | vertical speed on ladders (~3.75 tiles/s) |
| `stop_hold_time` (`PlayerAnimator`) | 0.2 s | how long the stop one-shot holds before idle resumes |
| `footstep_interval` (`PlayerSfx`) | 0.3 s | seconds between footsteps while running |
| `voice_count` (`PlayerSfx`) | 4 | pooled voices; oldest is reused beyond this many overlapping sounds |
| `volume_db` (`PlayerSfx`) | 0.0 dB | volume applied to every SFX voice |

## Mauser tuning reference

The Mauser is a configured instance of the NPC framework: tuning is
spread over the node whose behaviour reads it (state thresholds live
with the state that acts on them). Motor values (`jump_velocity`, …)
stay on the body as with the Bot, as do the `Capabilities` flags
(the Mauser sets `can_climb = false`). The personal-space bubble is the
`SenseArea` circle radius in the scene (≈48 px): "invaded" means the
player's body overlaps it. Sensing = in the bubble AND line of sight
clear (solid tiles occlude, one-way platforms don't).

`Brain` (`Scripts/NPC/npc_brain.gd`) — cross-state temperament:

| Property | Default | Meaning |
|---|---|---|
| `fill_time` | 2.0 s | 0→1 pressure while the player is sensed |
| `decay_time` | 1.5 s | 1→0 pressure while not sensed (roam/wary) |
| `tint_lerp_speed` | 8.0 | blend speed toward the current state's tint |

`Roam` (`Scripts/NPC/npc_roam.gd`) — docile wander:

| Property | Default | Meaning |
|---|---|---|
| `wary_at` | 0.35 | pressure at which it stops to watch (→ Wary) |
| `aggro_at` | 1.0 | pressure at which it turns (→ Pursue) |
| `calm_tint` | white | `modulate` target in this state |

`Wander` (`Scripts/NPC/npc_wander.gd`, under `Roam`) — ambient movement:

| Property | Default | Meaning |
|---|---|---|
| `speed` | 25.0 px/s | wander pace (applied to `move_speed`) |
| `radius` | 128.0 px | how far the next wander point is picked |
| `height_ratio` | 0.5 | y spread of wander picks (× `radius`) |
| `pause_min` / `pause_max` | 1.0 / 3.0 s | idle between wanders |
| `pick_attempts` | 4 | fresh picks per goal before giving up |
| `reach_distance` | 6.0 px | "arrived" tolerance for a wander goal |
| `walk_timeout` | 8.0 s | abandon a wander goal after this |
| `stall_chance` | 0.08 | per goal, chance of a mid-walk micro-stall |
| `stall_time` | 0.6 s | duration of that micro-stall (via `hold_for`) |

`Mauser` body (`Scenes/mauser.tscn`) — momentum weights (scene
overrides; the motor defaults are 1200/1500, the tuned player uses
250/130):

| Property | Default | Meaning |
|---|---|---|
| `acceleration` | 180.0 px/s² | time-to-speed (≈0.3 s to the 58 px/s charge) |
| `friction` | 120.0 px/s² | stop-slide (≈0.5 s to rest) |

`IdleLife` (`Scripts/NPC/npc_idle_life.gd`) — breathing bob and glances:

| Property | Default | Meaning |
|---|---|---|
| `bob_period` | 2.4 s | breathing cycle |
| `bob_amplitude` | 0.03 | scale.y breath (scale.x compensates) |
| `glance_interval_min` / `_max` | 3.0 / 8.0 s | idle look-around cadence |
| `glance_tilt` | 6.0° | peak tilt of a glance |
| `glance_duration` | 0.35 s | glance in-and-back time |

`Wary` (`Scripts/NPC/npc_wary.gd`) — give ground & watch:

| Property | Default | Meaning |
|---|---|---|
| `calm_at` | 0.35 | falls back to Roam below this pressure |
| `aggro_at` | 1.0 | pressure at which it turns (→ Pursue) |
| `wary_tint` | yellow | `modulate` target in this state |
| `retreat_distance` | 72.0 px | preferred clearance to back off to (≤ 0 = stand & watch) |
| `retreat_speed` | 35.0 px/s | shuffle pace while giving ground |
| `retreat_max_travel` | 96.0 px | total backing per wary episode (then it stands its ground) |
| `retreat_replan_interval` | 0.2 s | retreat goal refresh while the player moves |

Retreat ends early when the player leaves the bubble (unseen = pressure
decays = defused). Keep following and it backs to full clearance — and
then the meter finishes the story.

`Pursue` (`Scripts/NPC/npc_pursue.gd`) — the chase:

| Property | Default | Meaning |
|---|---|---|
| `calm_at` | 0.2 | stands down below this pressure (meter resets to 0) |
| `pursuit_speed` | 58.0 px/s | chase pace (above the player's tuned 50) |
| `reroute_interval` | 0.25 s | how often the chase re-routes |
| `rage_time` | 4.0 s (Mauser scene override: 60.0 s) | chase budget while the player is sensed — the override is user-tuned (scene is source of truth) |
| `lost_contact_rage_time` | 2.0 s (Mauser scene override: 60.0 s) | chase budget once contact breaks |
| `aggressive_tint` | red | `modulate` target in this state |

`Animator` (`Scripts/NPC/npc_animator.gd`) — intent→animation names
(missing animations fall back to `idle`, so future art drops in by
pointing a slot at it from the Inspector — zero code):

| Property | Default | Meaning |
|---|---|---|
| `anim_idle` / `anim_walk` / `anim_charge` | idle / move / move | first three slots |
| `anim_wary` / `anim_retreat` / `anim_jump` | wary / move / jump | `wary` has no art yet → shows idle |

`Sfx` (`Scripts/NPC/npc_sfx.gd`) — spatial creature sounds
(paths relative to `Audio/SFX/`):

| Property | Value | Meaning |
|---|---|---|
| `voice_count` | 4 | pooled round-robin voices (self + spatial children) |
| `footstep_interval` | 0.3 s | STEP cadence while moving and grounded |
| `idle_call_interval_min` / `_max` | 10.0 / 25.0 s | IDLE_CALL cadence — calm only (silence under threat) |
| `sound_idle_call` | `General Sounds/Interactions/sfx_sounds_interaction24.ogg` | the calm call |
| `sound_wary_warning` | `General Sounds/Weird Sounds/sfx_sound_nagger1.ogg` | fires on the give-ground beat |
| `sound_aggro_cry` | `General Sounds/Weird Sounds/sfx_sound_mechanicalnoise4.ogg` | fires on the flip to aggressive |
| `sound_land` | `Movement/Jumping and Landing/sfx_movement_jump13_landing.ogg` | shared with the player's LAND |
| `sound_footsteps` | `Movement/Footsteps/sfx_movement_footstepsloop4_fast` + `_slow` | the STEP slot |
| native spatial knobs | defaults | `volume_db`, `bus`, `max_distance`, `attenuation`, `panning_strength` — set on the Sfx node; copied to its child voices at startup |

All three vocals are hand-auditioned general Kenney effects (the pack
ships no creature voices — swap for real creature audio later);
`Death Screams/Alien/*` stays excluded — it is the player's death
scream.

State presentation fields (`NpcState`): `intent` (set each frame),
`facing_to_player` (`Wary`), `enter_sfx` (`Wary` → WARY_WARN,
`Pursue` → AGGRO_CRY).
