@icon("res://addons/at-icons/node2d/chess_king.svg")
class_name Player
extends CharacterBody2D
## Player character: platformer movement driven by a small state machine.
##
## Input is gathered once per physics frame, then the current state
## ([PlayerGrounded], [PlayerAirborne], [PlayerStunned] or
## [PlayerDead]) runs the frame's physics and ends with
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
## colliding. All tuning is exported; scene overrides on the node take
## precedence over the defaults below.

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

@export_category("State Machine")
## Grounded state node: owns coyote time, jump launching, ground intents.
@export var state_grounded: PlayerGrounded
## Airborne state node: owns fall physics and the AIR intent.
@export var state_airborne: PlayerAirborne
## Stunned state node: hard-landing lockout with a momentum slide.
@export var state_stunned: PlayerStunned
## Dead state node: terminal freeze after a lethal landing.
@export var state_dead: PlayerDead
## Maps state intents to SpriteFrames animations and owns facing.
@export var animator: PlayerAnimator
## Plays sound effects for jump, land, footstep and stop events.
@export var sfx: PlayerSfx

## Horizontal input axis, -1..1; refreshed every physics frame.
var input_direction: float = 0.0
## Jump release edge for this frame; states apply the jump cut from it.
var jump_just_released: bool = false
## Press-down edge for this frame; [PlayerGrounded] starts a drop-through
## from it while the player stands on a one-way platform.
var down_just_pressed: bool = false
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


func _physics_process(delta: float) -> void:
	# 0. Maintain the drop-through mask; start_drop_through clears the bit
	# for the same frame, this keeps it cleared while the timer runs.
	if _drop_timer > 0.0:
		_drop_timer -= delta
		collision_mask = _full_collision_mask & ~ONE_WAY_BIT
	else:
		collision_mask = _full_collision_mask

	# 1. Gather input once; states read these values, never Input. Input
	# is dead while stunned or dead, so the buffer below only decays there.
	if controls_enabled():
		input_direction = Input.get_axis("move_left", "move_right")
		_jump_just_pressed = Input.is_action_just_pressed("jump")
		jump_just_released = Input.is_action_just_released("jump")
		down_just_pressed = Input.is_action_just_pressed("move_down")
	else:
		input_direction = 0.0
		_jump_just_pressed = false
		jump_just_released = false
		down_just_pressed = false

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
	# never leaves.
	if _current == state_stunned:
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

	# Track the apex of the current floor leave; the landing tier above
	# reads it before this resets it to the landing height.
	if is_on_floor():
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
