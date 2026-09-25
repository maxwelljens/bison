extends CharacterBody2D
## Player character: platformer movement driven by the input map.
##
## Run with acceleration/friction, jump with coyote time and input buffering,
## variable jump height via a release cut, terminal-velocity clamp, and sprite
## flip on input direction. All tuning is exported; scene overrides on the
## node take precedence over the defaults below.

## Sprite flipped via `flip_h` to face the input direction.
@export var sprite: Sprite2D

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
## Seconds after leaving a ledge during which jumping is still allowed.
@export_range(0.0, 0.5) var coyote_time: float = 0.1
## Seconds a jump press before landing is remembered and fired on touchdown.
@export_range(0.0, 0.5) var jump_buffer_time: float = 0.1
## Upward velocity kept when jump is released early (short hop), 0-1.
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5
## Terminal fall speed in px/s.
@export var max_fall_speed: float = 600.0

# Gravity read at startup; never hardcoded so tuning stays in project settings.
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		velocity.y = minf(velocity.y + _gravity * delta, max_fall_speed)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	# Jump fires only when both grace windows are live: buffered press AND
	# (still on the ledge or just left it).
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# Variable jump height: early release while rising scales velocity down
	# instead of stopping, so a tap gives a short hop.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()
