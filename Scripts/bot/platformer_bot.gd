class_name PlatformerBot
extends CharacterBody2D

@export_category("Movement")
@export var move_speed: float = 130.0
@export var acceleration: float = 1200.0
@export var friction: float = 1500.0

@export_category("Jump")
@export var jump_velocity: float = -300.0
@export var jump_release_speed: float = 120.0
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.1
@export var max_fall_speed: float = 600.0

@export var sprite: Sprite2D

var input_left: bool = false
var input_right: bool = false
var input_jump: bool = false
var input_down: bool = false
var pending_jump_impulse: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_jump_down: bool = false
var _drop_timer: float = 0.0
var _full_collision_mask: int = 0


func _ready() -> void:
	_full_collision_mask = collision_mask


func get_gravity_strength() -> float:
	return _gravity


func drop_through(duration: float = 0.12) -> void:
	_drop_timer = duration


func _physics_process(delta: float) -> void:
	if _drop_timer > 0.0:
		_drop_timer -= delta
		collision_mask = 0
	else:
		collision_mask = _full_collision_mask

	var jump_pressed := input_jump and not _was_jump_down
	var jump_released := _was_jump_down and not input_jump
	_was_jump_down = input_jump

	var on_floor := is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		velocity.y = minf(velocity.y + _gravity * delta, max_fall_speed)

	if jump_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = -pending_jump_impulse if pending_jump_impulse > 0.0 else jump_velocity
		pending_jump_impulse = 0.0
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if jump_released and velocity.y < -jump_release_speed:
		velocity.y = -jump_release_speed

	var direction := 0.0
	if input_left:
		direction -= 1.0
	if input_right:
		direction += 1.0
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()
