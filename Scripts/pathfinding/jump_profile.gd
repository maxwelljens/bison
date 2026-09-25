class_name PlatformerJumpProfile
extends RefCounted

const MAX_REASONABLE_CELLS := 64

var jump_velocity: float
var gravity: float
var move_speed: float
var cell_size: float


func _init(p_jump_velocity: float, p_gravity: float, p_move_speed: float, p_cell_size: float) -> void:
	jump_velocity = p_jump_velocity
	gravity = p_gravity
	move_speed = p_move_speed
	cell_size = p_cell_size


func apex_height_px() -> float:
	if gravity <= 0.0:
		return 0.0
	var rise := absf(jump_velocity)
	return (rise * rise) / (2.0 * gravity)


func height_cells() -> int:
	if cell_size <= 0.0:
		return 1
	return clampi(int(apex_height_px() / cell_size), 1, MAX_REASONABLE_CELLS)


func drift_cells(height: int, falling: bool) -> int:
	if gravity <= 0.0 or cell_size <= 0.0:
		return 0
	var h := float(height) * cell_size
	var disc := jump_velocity * jump_velocity - 2.0 * gravity * h
	if disc < 0.0:
		disc = 0.0
	var root := sqrt(disc)
	var t := (absf(jump_velocity) + root) / gravity
	if not falling and height > 0:
		t = (absf(jump_velocity) - root) / gravity
	return int(move_speed * t / cell_size)
