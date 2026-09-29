@icon("res://addons/at-icons/node2d/chess_king.svg")
class_name Player
extends CharacterBody2D
## Player character: platformer movement driven by a small state machine.
##
## Input is gathered once per physics frame, then the current state
## ([PlayerGrounded], [PlayerAirborne], [PlayerStunned], [PlayerDead] or
## [PlayerLadder]) runs the frame's physics and ends with
## move_and_slide(). The player evaluates transitions on that fresh
## floor state and forwards facing plus animation intent to the
## [PlayerAnimator]. Fall damage resolves on the Airborne touchdown
## edge as landing tiers (safe / stun / lethal) from the drop below the
## flight's apex — no health pool, DESIGN.md §5. Grace windows: the
## jump buffer ticks here (an input memory spanning both states),
## coyote time lives in [PlayerGrounded], and each state applies the
## jump cut. Pressing down while standing starts a drop-through: the
## one-way tileset physics layer is masked out for a short window so
## the player sinks through one-way platforms while solid ground keeps
## colliding. On a ladder tile ([LadderMap]) the same bit is masked for
## the whole [PlayerLadder] state so rungs never block descent. All
## tuning is exported; scene overrides on the node take precedence over
## the defaults below.

## Collision-layer bit the fg tileset's one-way platforms live on
## (physics layer 1, project setting "One-way").
const ONE_WAY_BIT: int = 2

@export_category("Movement")
## Top run speed in px/s (~8 tiles/s at 16 px tiles).
@export var move_speed: float = 130.0
## Ground acceleration in px/s² toward the target speed.
@export var acceleration: float = 1200.0
## Deceleration in px/s² when no input is held.
@export var friction: float = 1500.0

@export_category("Jump")
## Jump impulse in px/s (negative = up); apex height is v²/(2·g).
@export var jump_velocity: float = -300.0
## Upward velocity kept when jump is released early (short hop), 0-1.
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5
## Terminal fall speed in px/s.
@export var max_fall_speed: float = 600.0

@export_category("Fall Damage")
## Drop below the flight's apex in px at or above which a landing stuns
## (~4 tiles; a full jump reads ~23 px here, so normal landings never
## reach it).
@export_range(0.0, 2000.0, 1.0, "suffix:px") var stun_fall_distance: float = 64.0
## Drop below the flight's apex in px at or above which a landing is
## lethal (~10 tiles).
@export_range(0.0, 2000.0, 1.0, "suffix:px") var lethal_fall_distance: float = 160.0

@export_category("Drop-Through")
## Seconds the one-way platform bit stays off after a press-down; the
## 11 px-tall body needs ~0.18 s to clear an 8 px-thick platform top at
## project gravity.
@export_range(0.05, 1.0, 0.05, "suffix:s") var drop_through_time: float = 0.25

@export_category("Ladder")
## Tilemap whose [code]ladder[/code] custom-data flag marks ladder rungs;
## ladder queries degrade to "no ladders" when unassigned.
@export var tilemap: TileMapLayer
## Vertical climb speed in px/s.
@export_range(10.0, 300.0, 1.0, "suffix:px/s") var climb_speed: float = 60.0

@export_category("State Machine")
## Grounded state node: owns coyote time, jump launching, ground intents.
@export var state_grounded: PlayerGrounded
## Airborne state node: owns fall physics and the AIR intent.
@export var state_airborne: PlayerAirborne
## Stunned state node: hard-landing lockout with a momentum slide.
@export var state_stunned: PlayerStunned
## Dead state node: terminal freeze after a lethal landing.
@export var state_dead: PlayerDead
## Ladder state node: climb, hang and jump-off on ladder tiles.
@export var state_ladder: PlayerLadder
## Maps state intents to SpriteFrames animations and owns facing.
@export var animator: PlayerAnimator
## Plays sound effects for jump, land, footstep and stop events.
@export var sfx: PlayerSfx

## Horizontal input axis, -1..1; refreshed every physics frame.
var input_direction: float = 0.0
## Jump release edge for this frame; states apply the jump cut from it.
var jump_just_released: bool = false
## Held up/down axis (-1..1, positive = up) for ladder climbing; also
## drives the ladder grab and drop-through in step 4.
var vertical_input: float = 0.0
## The rung the player is holding; set on a grab, read by [PlayerLadder]
## for the chain extents and the column snap.
var ladder_rung: Vector2i = Vector2i.ZERO
## Set by a state when a jump launches this frame; the player consumes
## it (playing the jump sound) and clears it every frame.
var jumped_this_frame: bool = false
## Seconds a buffered jump press remains actionable. Ticked every frame in
## both states so a press just before touchdown survives the fall.
var jump_buffer_timer: float = 0.0

# Gravity read at startup; never hardcoded so tuning stays in project settings.
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _jump_just_pressed: bool = false
var _current: PlayerState
# Highest point (lowest y) reached since leaving the floor; the landing
# tiers measure the drop from here.
var _apex_y: float = 0.0

var _full_collision_mask: int = 0
var _drop_timer: float = 0.0


func _ready() -> void:
	_full_collision_mask = collision_mask
	state_grounded.setup(self)
	state_airborne.setup(self)
	state_stunned.setup(self)
	state_dead.setup(self)
	state_ladder.setup(self)
	_apex_y = global_position.y
	_current = state_grounded
	_current.enter(null)


## Gravity in px/s², for the states' fall integration.
func get_gravity_strength() -> float:
	return _gravity


## False while stunned or dead: the player zeroes its input every frame,
## and interact consumers (the chest) gate their actions on this.
func controls_enabled() -> bool:
	return _current != state_stunned and _current != state_dead


## Starts a drop-through: for [member drop_through_time] seconds the
## one-way platform bit is removed from the collision mask so the player
## sinks through one-way platforms. Solid tiles sit on another layer and
## keep colliding, so over regular floor this is a harmless no-op.
func start_drop_through() -> void:
	_drop_timer = drop_through_time
	collision_mask = _full_collision_mask & ~ONE_WAY_BIT


## Global rectangle of the body's collision shape; ladder queries read
## the body's centre and feet from it.
func collision_rect_global() -> Rect2:
	var rect := Rect2()
	var empty := true
	for owner_id in get_shape_owners():
		var xform: Transform2D = shape_owner_get_transform(owner_id)
		for index in range(shape_owner_get_shape_count(owner_id)):
			var shape := shape_owner_get_shape(owner_id, index)
			if shape == null:
				continue
			var shape_rect: Rect2 = xform * shape.get_rect()
			if empty:
				rect = shape_rect
				empty = false
			else:
				rect = rect.merge(shape_rect)
	return global_transform * rect


## The tilemap cell holding the surface under the body's feet.
func ladder_cell_under_feet() -> Vector2i:
	var rect := collision_rect_global()
	return tilemap.local_to_map(tilemap.to_local(
			Vector2(rect.get_center().x, rect.end.y)))


## Grabs a ladder and enters the Ladder state. A rung counts as
## grabbable when it holds the player's centre — a simple check, no
## reach margin. The up intent grabs from anywhere — a mid-fall catch
## cancels the drop — and the down intent does the same (catch and
## descend). Returns true when it grabbed.
func try_enter_ladder(up: bool) -> bool:
	if tilemap == null or _current == state_ladder or not controls_enabled():
		return false
	var rungs := _rung_candidates(not up)
	if rungs.is_empty():
		return false
	ladder_rung = rungs[0]
	for cell in rungs:
		if cell.y > ladder_rung.y:
			ladder_rung = cell
	if not up:
		# A descend grab needs room to descend: at the chain's bottom
		# edge there is nothing left to go down, and re-grabbing there
		# would flap the state every frame while the key is held.
		var bottom_y := LadderMap.cell_bottom_y(tilemap,
				LadderMap.run_bottom_cell(tilemap, ladder_rung))
		if bottom_y <= collision_rect_global().end.y + 1.0:
			return false
	_transition(state_ladder)
	return true


# Ladder cells for a grab attempt: the cell holding the player's
# centre, plus the cell below the feet for descending off an unflagged
# landing above a chain.
func _rung_candidates(down_intent: bool) -> Array[Vector2i]:
	var rungs: Array[Vector2i] = []
	var centre := tilemap.local_to_map(tilemap.to_local(
			collision_rect_global().get_center()))
	if LadderMap.is_ladder_cell(tilemap, centre):
		rungs.append(centre)
	if down_intent:
		var below := ladder_cell_under_feet() + Vector2i.DOWN
		if LadderMap.is_ladder_cell(tilemap, below) and not rungs.has(below):
			rungs.append(below)
	return rungs


func _physics_process(delta: float) -> void:
	# 0. Maintain the drop-through mask; start_drop_through clears the bit
	# for the same frame, this keeps it cleared while the timer runs. The
	# Ladder state holds it cleared for its whole duration so rungs never
	# block descent.
	if _drop_timer > 0.0:
		_drop_timer -= delta
		collision_mask = _full_collision_mask & ~ONE_WAY_BIT
	elif _current == state_ladder:
		collision_mask = _full_collision_mask & ~ONE_WAY_BIT
	else:
		collision_mask = _full_collision_mask

	# 1. Gather input once; states read these values, never Input. Input
	# is dead while stunned or dead, so the buffer below only decays there.
	if controls_enabled():
		input_direction = Input.get_axis("move_left", "move_right")
		_jump_just_pressed = Input.is_action_just_pressed("jump")
		jump_just_released = Input.is_action_just_released("jump")
		vertical_input = Input.get_axis("move_down", "move_up")
	else:
		input_direction = 0.0
		_jump_just_pressed = false
		jump_just_released = false
		vertical_input = 0.0

	# 2. Jump buffer ticks every frame regardless of state; only the press
	# duration lives on the current grounded state.
	if _jump_just_pressed:
		jump_buffer_timer = state_grounded.jump_buffer_time
	else:
		jump_buffer_timer -= delta

	# 3. The current state runs this frame's physics and ends with
	# move_and_slide().
	_current.physics_process(delta)
	if jumped_this_frame:
		sfx.play(PlayerSfx.Event.JUMP)
		jumped_this_frame = false

	# 4. Transitions, evaluated on the floor state move_and_slide just
	# produced. Grounded persists through the coyote window after a
	# walk-off, so jump launching stays inside it. An Airborne touchdown
	# resolves the fall-damage tier from the drop below the flight's apex
	# (tracked at the end of this frame); Dead matches no branch and
	# never leaves. A ladder exits on its reported move: stand on the
	# top rung or hand a free fall to Airborne.
	if _current == state_ladder:
		match state_ladder.consume_exit():
			PlayerLadder.Exit.GROUND:
				_transition(state_grounded)
			PlayerLadder.Exit.AIR:
				_transition(state_airborne)
			PlayerLadder.Exit.NONE:
				pass
	elif _current == state_stunned:
		if not is_on_floor():
			_transition(state_airborne)
		elif state_stunned.expired():
			_transition(state_grounded)
	elif _current == state_airborne and is_on_floor():
		var fall := global_position.y - _apex_y
		if fall >= lethal_fall_distance:
			sfx.play(PlayerSfx.Event.DEATH)
			_transition(state_dead)
		elif fall >= stun_fall_distance:
			sfx.play(PlayerSfx.Event.HARD_LAND)
			_transition(state_stunned)
		else:
			sfx.play(PlayerSfx.Event.LAND)
			_transition(state_grounded)
	elif _current == state_grounded and not is_on_floor() \
			and not state_grounded.coyote_active():
		_transition(state_airborne)

	# Ladder grab and drop-through run off the held up/down intent, so
	# falling or walking in while already holding a direction still
	# catches. Down grabs a rung to catch and descend — standing on
	# anything else drops through one-ways (a no-op over solid floor).
	if vertical_input > 0.0:
		try_enter_ladder(true)
	elif vertical_input < 0.0 and not try_enter_ladder(false) \
			and _current == state_grounded and is_on_floor():
		start_drop_through()

	# Track the apex of the current floor leave; the landing tier above
	# reads it before this resets it to the landing height. Ladder frames
	# count as grounded, so stepping off measures only that drop.
	if is_on_floor() or _current == state_ladder:
		_apex_y = global_position.y
	else:
		_apex_y = minf(_apex_y, global_position.y)

	# 5. Presentation: facing and animation intent.
	if input_direction != 0.0:
		animator.set_facing(input_direction)
	animator.set_intent(_current.intent)
	sfx.set_intent(_current.intent)
	sfx.set_grounded(is_on_floor())


func _transition(next: PlayerState) -> void:
	var previous := _current
	previous.exit()
	_current = next
	_current.enter(previous)
