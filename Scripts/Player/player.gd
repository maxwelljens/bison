@icon("res://addons/at-icons/node2d/chess_king.svg")
class_name Player
extends CharacterBody2D
## Player character: platformer movement driven by a two-state machine.
##
## Input is gathered once per physics frame, then the current state
## ([PlayerGrounded] or [PlayerAirborne]) runs the frame's physics and
## ends with move_and_slide(). The player evaluates transitions on that
## fresh floor state and forwards facing plus animation intent to the
## [PlayerAnimator]. Grace windows: the jump buffer ticks here (an input
## memory spanning both states), coyote time lives in [PlayerGrounded],
## and each state applies the jump cut. All tuning is exported; scene
## overrides on the node take precedence over the defaults below.

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

@export_category("State Machine")
## Grounded state node: owns coyote time, jump launching, ground intents.
@export var state_grounded: PlayerGrounded
## Airborne state node: owns fall physics and the AIR intent.
@export var state_airborne: PlayerAirborne
## Maps state intents to SpriteFrames animations and owns facing.
@export var animator: PlayerAnimator

## Horizontal input axis, -1..1; refreshed every physics frame.
var input_direction: float = 0.0
## Jump release edge for this frame; states apply the jump cut from it.
var jump_just_released: bool = false
## Seconds a buffered jump press remains actionable. Ticked every frame in
## both states so a press just before touchdown survives the fall.
var jump_buffer_timer: float = 0.0

# Gravity read at startup; never hardcoded so tuning stays in project settings.
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _jump_just_pressed: bool = false
var _current: PlayerState


func _ready() -> void:
	state_grounded.setup(self)
	state_airborne.setup(self)
	_current = state_grounded
	_current.enter(null)


## Gravity in px/s², for the states' fall integration.
func get_gravity_strength() -> float:
	return _gravity


func _physics_process(delta: float) -> void:
	# 1. Gather input once; states read these values, never Input.
	input_direction = Input.get_axis("move_left", "move_right")
	_jump_just_pressed = Input.is_action_just_pressed("jump")
	jump_just_released = Input.is_action_just_released("jump")

	# 2. Jump buffer ticks every frame regardless of state; only the press
	# duration lives on the current grounded state.
	if _jump_just_pressed:
		jump_buffer_timer = state_grounded.jump_buffer_time
	else:
		jump_buffer_timer -= delta

	# 3. The current state runs this frame's physics and ends with
	# move_and_slide().
	_current.physics_process(delta)

	# 4. Transitions, evaluated on the floor state move_and_slide just
	# produced. Grounded persists through the coyote window after a
	# walk-off, so jump launching stays inside it.
	if _current == state_airborne and is_on_floor():
		_transition(state_grounded)
	elif _current == state_grounded and not is_on_floor() \
			and not state_grounded.coyote_active():
		_transition(state_airborne)

	# 5. Presentation: facing and animation intent.
	if input_direction != 0.0:
		animator.set_facing(input_direction)
	animator.set_intent(_current.intent)


func _transition(next: PlayerState) -> void:
	var previous := _current
	previous.exit()
	_current = next
	_current.enter(previous)
