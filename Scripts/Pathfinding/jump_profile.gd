class_name PlatformerJumpProfile
extends RefCounted
## Ballistic capabilities of a jumping agent.
##
## Given live kinematics (jump impulse, gravity, run speed, tile size), this
## derives what arcs physically exist: how high the agent can rise and how far
## it can drift horizontally at a given height delta. The pathfinder bounds
## every airborne move by these envelopes, so tuning jump velocity honestly
## changes which paths are reachable.

## Sanity clamp on derived reach, in cells.
const MAX_REASONABLE_CELLS := 64

## Launch impulse in px/s (negative = upward).
var jump_velocity: float
## Gravity in px/s².
var gravity: float
## Horizontal air speed in px/s (assumed constant while airborne).
var move_speed: float
## Tile size in px.
var cell_size: float
## Vertical ladder speed in px/s.
var climb_speed: float


## Stores the agent's kinematics; all derived values are computed on demand.
## [param p_climb_speed] prices ladder travel for the pathfinder.
func _init(
		p_jump_velocity: float,
		p_gravity: float,
		p_move_speed: float,
		p_cell_size: float,
		p_climb_speed: float = 60.0,
) -> void:
	jump_velocity = p_jump_velocity
	gravity = p_gravity
	move_speed = p_move_speed
	cell_size = p_cell_size
	climb_speed = p_climb_speed


## Apex height of the jump arc in px: v² / (2·g).
func apex_height_px() -> float:
	if gravity <= 0.0:
		return 0.0
	var rise := absf(jump_velocity)
	return (rise * rise) / (2.0 * gravity)


## Jump height in whole grid cells, clamped to [1, MAX_REASONABLE_CELLS].
func height_cells() -> int:
	if cell_size <= 0.0:
		return 1
	return clampi(int(apex_height_px() / cell_size), 1, MAX_REASONABLE_CELLS)


## Maximum horizontal drift, in cells, while airborne at a height delta of
## [param height] cells (positive = above the launch point).
##
## Math: at height h the vertical speed follows v_f² = v² − 2·g·h, so
## root = √(v² − 2·g·h) is the speed magnitude there. The time to reach that
## height on the ascending branch is (|v| − root)/g; the time to descend back
## to it is (|v| + root)/g. [param falling] picks the descending branch (full
## flight time), otherwise the ascending one. Multiplied by [member move_speed]
## and divided by [member cell_size], that airtime is the drift in cells.
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
