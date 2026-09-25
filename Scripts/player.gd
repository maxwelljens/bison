extends CharacterBody2D

@export var sprite: Sprite2D

@export_category("Movement")
@export var move_speed: float = 130.0        # px/s (~8 tiles/s at 16 px tiles)
@export var acceleration: float = 1200.0     # px/s^2
@export var friction: float = 1500.0         # px/s^2 when no input

@export_category("Jump")
@export var jump_velocity: float = -300.0    # apex ~46 px ≈ 3 tiles at g=980
@export_range(0.0, 0.5) var coyote_time: float = 0.1
@export_range(0.0, 0.5) var jump_buffer_time: float = 0.1
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5
@export var max_fall_speed: float = 600.0

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

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()
