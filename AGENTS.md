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
  (Bot root: `Sprite2D`, collision, `BotPathFollower`, `Pathfinder`) and
  `chest.tscn` (Chest root: `Sprite2D`, `Trigger` Area2D, `Sfx`, `Vfx`).
- `Scripts/` — GDScript sources: `Player/` (`player.gd`, `player_state.gd`,
  `grounded.gd`, `airborne.gd`, `player_animator.gd`,
  `player_sfx.gd`); `Pathfinding/`
  (`platformer_grid.gd`, `jump_profile.gd`, `path_data.gd`,
  `path_waypoint.gd`, `platformer_pathfinder.gd`,
  `debug/grid_debug_draw.gd`); `Bot/`
  (`platformer_bot.gd`, `bot_path_follower.gd`); `Chest/`
  (`chest.gd`, `chest_sfx.gd`, `chest_vfx.gd`).
- `Textures/` — art: `Tilemap/` (tileset textures), `Tiles/Default` and
  `Tiles/Transparent` (individual tiles), `Sample.png`.
- `AGENTS.md` — this file.

## Current state (as of 2026-09-25)

- `Levels/test_level.tscn` — `TestLevel` (Node2D) contains:
  - `TileMapLayer` — tile data plus a `TileSet` with a physics layer on
	collision_layer 1 (the player's default collision mask matches it).
  - `Chest` (instance of `Scenes/chest.tscn`) — interactive loot chest:
	stand in its `Trigger` Area2D and press the `interact` action (E) to
	open. Opening swaps the sprite texture, plays a `ChestSfx` event,
	fires a `ChestVfx` particle/flash burst and emits `Chest.opened`.
	The chest stays open visually and remains interactable — every
	in-range press re-emits `opened` (the loot/inventory increment will
	hook the signal). The trigger counts only `CharacterBody2D` overlaps
	so static tile collision never fakes proximity. Feedback components
	degrade silently when unassigned (no art/sound/refs = no errors).
	`texture_open` ships unassigned (open-chest art pending); texture
	slot defaults keep the sprite's own texture until assigned.
  - `Player` (instance of `Scenes/player.tscn`) with children:
    `StateMachine` (holds the `Grounded`/`Airborne` state nodes),
    `Animator`, `Sfx`, `AnimatedSprite2D` (SpriteFrames:
    idle/jump/run/stop), `CollisionShape2D` (RectangleShape2D 12×11 at
    (0, 2.5)), and `Camera2D` (follows the player for free by being a
    child).
- `Scripts/Player/` — player-driven two-state machine: the player gathers
  input once per frame, the current state (`grounded.gd` / `airborne.gd`)
  runs the frame's physics and ends with `move_and_slide()`, transitions
  are evaluated on that fresh floor state (Grounded exits only when the
  floor is lost AND its coyote window expired, so jump launching stays
  inside it), and states emit animation intents (IDLE/RUN/STOP/AIR) that
  `player_animator.gd` maps onto the SpriteFrames. `player_state.gd` is
  the base class (`setup`/`enter`/`exit`/`physics_process`).
- Sound effects: `player_sfx.gd` (`PlayerSfx`) sits under the player
  like the Animator and never touches audio from the states. The player
  forwards the state intent (`set_intent`), floor state (`set_grounded`)
  and events: Grounded sets `player.jumped_this_frame` at jump launch
  (the player plays JUMP and clears it), and the player plays LAND on
  the Airborne→Grounded transition. Footsteps tick while RUN + grounded
  (fixed `footstep_interval`); STOP plays on its one-frame intent edge.
  Sounds play through a code-created round-robin pool of
  `voice_count` `AudioStreamPlayer`s (overlaps never cut). New events
  scale by adding an Event entry, an `@export` stream and a match arm in
  `_stream_for`. `sound_stop` ships unassigned (no skid asset in the
  Kenney pack); unassigned streams silently skip their event.
- Input map (`project.godot`): `move_left` (A/←), `move_right` (D/→),
  `jump` (Space/W/↑). Keyboard only, no gamepad bindings.
- Scene-level tuning overrides on the Player node (user-tuned in the
  Inspector; the scene is the source of truth, currently
  `move_speed = 50.0`, `jump_velocity = -150.0`). Script defaults differ
  and only apply where a scene does not override them.
- Pathfinding (increment-based delivery): `Scripts/Pathfinding/` foundations
  landed (typed waypoints, jump model, TileMapLayer→grid extraction) and
  headlessly probed, plus a `GridDebugDraw` overlay and a `Pathfinder` route
  preview (both draw in the editor and in-game) for visual verification.
  Solver (`platformer_pathfinder.gd`) landed and probe-verified. Bot
  (`platformer_bot.gd`) + follower (`bot_path_follower.gd`) landed: own
  movement, typed-waypoint execution, click-to-move (LMB), stuck-watchdog
  repath. Feedback round 1 fixed: real jumps over gaps (parity applied to
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
  Awaiting re-verification.
- Known gaps (intentionally out of scope so far): no camera limits, no
  UI/health/death, only the Grounded/Airborne states exist so far (no
  fall-specific art — AIR maps to the jump frames).

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
`Scripts/Player/grounded.gd`, `stop_hold_time` on
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
| `run_min_speed` (`PlayerGrounded`) | 10.0 px/s | releasing move input at/above this speed shows the stop animation |
| `stop_hold_time` (`PlayerAnimator`) | 0.2 s | how long the stop one-shot holds before idle resumes |
| `footstep_interval` (`PlayerSfx`) | 0.3 s | seconds between footsteps while running |
| `voice_count` (`PlayerSfx`) | 4 | pooled voices; oldest is reused beyond this many overlapping sounds |
| `volume_db` (`PlayerSfx`) | 0.0 dB | volume applied to every SFX voice |
