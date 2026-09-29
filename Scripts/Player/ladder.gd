@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerLadder
extends PlayerState
## Ladder state: climbing a flagged rung chain with hang and jump-off.
##
## Entered by grabbing a rung within reach (see
## [method Player.try_enter_ladder]): up and down climb (both intents
## catch mid-fall), release hangs (no gravity), a buffered jump jumps
## off at full power, and left/right shimmies along the rung tile at
## normal run speed — moving out of the tile steps off into a free
## fall. The chain extents clamp the climb: the bottom edge hands a
## fall to Airborne, and the top stops at the first standable surface
## at or above the top rung — a one-way landing is risen through (the
## one-way bit stays masked) and stood on — or hangs at the chain's top
## edge when there is none. Ladder frames read as grounded to the fall
## apex, so a catch or a step-off never measures the whole chain as one
## fall.

## Where a finished ladder move wants to go.
enum Exit {
	## No exit requested.
	NONE,
	## Stand on the surface reached at the climb top.
	GROUND,
	## Detach, jump-off, shimmy-off or chain bottom: free fall from here.
	AIR,
}

var _exit: Exit = Exit.NONE
# World y of the chain's bottom edge and of the climb stop, computed on
# entry together with whether the stop can be stood on; _column_x is
# the grabbed rung's centre, the shimmy's home axis.
var _run_bottom_y: float = 0.0
var _stop_y: float = 0.0
var _stop_standable: bool = false
var _column_x: float = 0.0


## Exit requested by the last physics frame; consuming resets it to NONE.
func consume_exit() -> Exit:
	var value := _exit
	_exit = Exit.NONE
	return value


func enter(_previous: PlayerState) -> void:
	_exit = Exit.NONE
	intent = PlayerAnimator.Intent.CLIMB
	var rung := player.ladder_rung
	_run_bottom_y = LadderMap.cell_bottom_y(
			player.tilemap, LadderMap.run_bottom_cell(player.tilemap, rung))
	var top := LadderMap.run_top_cell(player.tilemap, rung)
	_stop_y = LadderMap.cell_top_y(player.tilemap, top)
	_stop_standable = false
	if LadderMap.has_standable_top(player.tilemap, top):
		_stop_standable = true
	elif LadderMap.has_standable_top(player.tilemap, top + Vector2i.UP):
		_stop_y = LadderMap.cell_top_y(player.tilemap, top + Vector2i.UP)
		_stop_standable = true
	_column_x = player.tilemap.to_global(
			player.tilemap.map_to_local(rung)).x
	player.velocity = Vector2.ZERO


func physics_process(delta: float) -> void:
	# A buffered jump jumps off at full power; both other exits hand a
	# free fall to Airborne.
	if player.jump_buffer_timer > 0.0:
		player.jump_buffer_timer = 0.0
		player.velocity.y = player.jump_velocity
		player.jumped_this_frame = true
		player.move_and_slide()
		_exit = Exit.AIR
		return

	# Climb/shimmy: up/down drives the climb (0 = hang) and left/right
	# slides along the rung tile at normal run speed. The chain edges
	# clamp the feet: reaching the climb stop stands up when it is a
	# real surface and hangs otherwise; sinking past the chain's bottom
	# edge (within a frame-step of slack) falls.
	var slack := player.climb_speed * delta
	player.velocity.y = -player.vertical_input * player.climb_speed
	_steer(delta)
	player.move_and_slide()

	# Moving out of the rung tile sideways steps off the ladder.
	var half_tile := player.tilemap.tile_set.tile_size.x * 0.5
	if absf(player.global_position.x - _column_x) > half_tile:
		player.velocity.y = 0.0
		_exit = Exit.AIR
		return

	var feet_y := player.collision_rect_global().end.y
	if player.vertical_input > 0.0 and feet_y <= _stop_y + slack:
		player.global_position.y += _stop_y - feet_y
		player.velocity.y = 0.0
		if _stop_standable:
			_exit = Exit.GROUND
	elif player.vertical_input < 0.0 and feet_y >= _run_bottom_y - slack:
		_exit = Exit.AIR
