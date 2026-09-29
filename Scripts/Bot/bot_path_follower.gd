class_name BotPathFollower
extends Node
## Waypoint executor: turns a computed path into bot inputs.
##
## Follows [PathData] waypoints by steering a [PlatformerBot] through them:
## runs along the ground, fires matched ballistic impulses at jumps, steers
## mid-air (gated by the pathfinder's drift envelope), pulses drop-through
## at one-way platforms, and climbs ladders (grab, climb, top out or step
## off). Click-to-move and a stuck watchdog that repaths.

## The body being driven.
@export var bot: PlatformerBot
## Path source and drift-envelope authority.
@export var pathfinder: PlatformerPathfinder

@export_category("Control")
## Left mouse click orders a move to the clicked point.
@export var click_to_move: bool = true
## Horizontal waypoint tolerance in px.
@export var reach_tolerance: float = 3.0
## Extra vertical tolerance in px when matching a jump apex.
@export var apex_tolerance: float = 4.0
## Physics frames without movement before the path is rebuilt.
@export var stuck_timeout_frames: int = 45

var _path: PathData
var _index: int = 0
var _launched: bool = false
var _saw_air: bool = false
var _dropping: bool = false
var _matched_jump: bool = false
# Shimmy side committed while letting go of the ladder (-1 left, +1 right).
var _nudge_side: int = 0
var _stuck_frames: int = 0
var _last_position: Vector2 = Vector2.ZERO
var _goal_world: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not click_to_move or pathfinder == null or bot == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		move_to(pathfinder.get_global_mouse_position())


## Requests a move to [param world]: builds a jump profile from the bot's live
## physics, searches a path, and resets all follower state.
func move_to(world: Vector2) -> void:
	_goal_world = world
	if bot == null or pathfinder == null:
		return
	var jump := PlatformerJumpProfile.new(
		bot.jump_velocity, bot.get_gravity_strength(), bot.move_speed,
		float(pathfinder.get_cell_size()), bot.climb_speed)
	_path = pathfinder.find_path(bot.global_position, world, jump)
	_index = 0
	_launched = false
	_saw_air = false
	_dropping = false
	_matched_jump = false
	_nudge_side = 0
	_stuck_frames = 0
	_last_position = bot.global_position


func _physics_process(_delta: float) -> void:
	if bot == null or pathfinder == null:
		return
	if _path == null or not _path.found or _index >= _path.waypoints.size():
		_release_inputs()
		return
	_watch_stuck()
	var waypoint := _path.waypoints[_index]
	if bot.is_climbing() and waypoint.kind != PathWaypoint.Kind.CLIMB:
		if not _leave_ladder_for(waypoint):
			return
	match waypoint.kind:
		PathWaypoint.Kind.WALK:
			_run_toward(waypoint.world)
			if _reached_x(waypoint.world):
				_advance()
		PathWaypoint.Kind.JUMP:
			if not _launched:
				_run_toward(waypoint.world)
				if _reached(waypoint.world) and bot.is_on_floor():
					_launched = true
					_saw_air = false
					var impulse := _matched_impulse(waypoint.world, _next_target(waypoint))
					_matched_jump = impulse > 0.0
					bot.pending_jump_impulse = impulse
					bot.input_jump = true
			else:
				_steer_airborne(_next_target(waypoint))
				if not bot.is_on_floor():
					_saw_air = true
				if _saw_air:
					# Hold the jump until past the apex (velocity turns
					# downward). Matched jumps detect that purely by velocity;
					# unmatched ones also stop rising at the path's apex
					# position, since their impulse was not arc-matched.
					var past_apex := bot.velocity.y >= 0.0
					if not _matched_jump:
						past_apex = past_apex or bot.global_position.y <= waypoint.apex_world.y + apex_tolerance
					bot.input_jump = not past_apex
				bot.input_up = _next_is_climb()
				if _next_is_climb() and bot.is_climbing():
					_advance()
				elif _saw_air and bot.is_on_floor():
					_advance()
		PathWaypoint.Kind.LAND:
			_steer_airborne(waypoint.world)
			if bot.is_on_floor() and _reached_x(waypoint.world):
				_advance()
		PathWaypoint.Kind.FALL:
			_air_transition(waypoint)
		PathWaypoint.Kind.DROP_THROUGH:
			if not _dropping:
				_dropping = true
				bot.drop_through()
			_air_transition(waypoint)
		PathWaypoint.Kind.CLIMB:
			_climb_toward(waypoint)


## Ladder travel: grabs the chain on the first contact (held up, or held
## down for a descend grab from a landing above), then climbs toward the
## waypoint's height and advances once within reach.
func _climb_toward(waypoint: PathWaypoint) -> void:
	bot.input_jump = false
	if not bot.is_climbing():
		bot.input_up = not _is_descend_grab(waypoint)
		bot.input_down = not bot.input_up
		_steer_airborne(waypoint.world)
		return
	var dy := waypoint.world.y - bot.global_position.y
	bot.input_up = dy < -reach_tolerance
	bot.input_down = dy > reach_tolerance
	bot.input_left = false
	bot.input_right = false
	if absf(dy) <= reach_tolerance:
		_advance()


## Drives the exit the next waypoint needs while the bot is still on the
## ladder: top out (hold up), shimmy off toward a crossing (steer x), drop
## off the chain base (hold down), jump off (fire the launch), or detach
## into a fall (steer toward the landing). Returns true once the bot has
## left the ladder and the waypoint's own arm can run.
func _leave_ladder_for(waypoint: PathWaypoint) -> bool:
	bot.input_jump = false
	bot.input_up = false
	bot.input_down = false
	bot.input_left = false
	bot.input_right = false
	var rung := _exit_rung()
	match waypoint.kind:
		PathWaypoint.Kind.JUMP:
			var impulse := _matched_impulse(waypoint.world, _next_target(waypoint))
			_matched_jump = impulse > 0.0
			bot.pending_jump_impulse = impulse
			bot.input_jump = true
			_launched = true
			_saw_air = false
		PathWaypoint.Kind.WALK:
			if waypoint.cell.x != rung.x:
				_step_off_sideways(waypoint, rung)
			elif waypoint.cell.y < rung.y:
				bot.input_up = true
			else:
				bot.input_down = true
		_:
			if not LadderMap.is_ladder_cell(bot.tilemap, rung + Vector2i.DOWN):
				bot.input_down = true
			else:
				# Letting go needs a shimmy past the rung tile, so commit to one
				# side and hold it; steering toward a target in the column band
				# would oscillate inside the reach deadzone and never detach.
				if _nudge_side == 0:
					var landing := _next_target(waypoint)
					if absf(landing.x - bot.global_position.x) > reach_tolerance:
						_nudge_side = -1 if landing.x < bot.global_position.x else 1
					elif bot.test_move(bot.global_transform, Vector2(-2.0, 0.0)):
						_nudge_side = 1
					else:
						_nudge_side = -1
				bot.input_left = _nudge_side < 0
				bot.input_right = _nudge_side > 0
	return not bot.is_climbing()


## The rung an exit leaves from: the previous CLIMB waypoint's cell. Path
## data is immutable, unlike the bot's live centre cell, which straddles
## cell boundaries at the chain top and flips the exit branch per frame.
func _exit_rung() -> Vector2i:
	if _index > 0 and _path.waypoints[_index - 1].kind == PathWaypoint.Kind.CLIMB:
		return _path.waypoints[_index - 1].cell
	return bot.ladder_rung


## Sideways step-off toward [param waypoint] from [param rung]: a crossing
## above the rung is reached by rising to its exit surface first, then
## shimmying out; foot-height crossings shimmy out immediately.
func _step_off_sideways(waypoint: PathWaypoint, rung: Vector2i) -> void:
	if waypoint.cell.y < rung.y:
		var plane := LadderMap.cell_bottom_y(bot.tilemap, waypoint.cell)
		if bot.collision_rect_global().end.y > plane + 1.0:
			bot.input_up = true
			return
	_steer_x(waypoint.world)


## True when the waypoint after the current one starts a climb (a catch).
func _next_is_climb() -> bool:
	return _index + 1 < _path.waypoints.size() \
			and _path.waypoints[_index + 1].kind == PathWaypoint.Kind.CLIMB


## True when this climb is entered by descending from a landing two cells
## above the first rung (the descend grab holds down instead of up).
func _is_descend_grab(waypoint: PathWaypoint) -> bool:
	if _index == 0:
		return false
	return _path.waypoints[_index - 1].cell == waypoint.cell + 2 * Vector2i.UP


## Unpowered air move: release jump, steer toward the next waypoint, and
## advance once the floor is regained after having been airborne.
func _air_transition(waypoint: PathWaypoint) -> void:
	bot.input_jump = false
	bot.input_up = _next_is_climb()
	bot.input_down = false
	_steer_airborne(_next_target(waypoint))
	if not bot.is_on_floor():
		_saw_air = true
	if _next_is_climb() and bot.is_climbing():
		_advance()
	elif _saw_air and bot.is_on_floor():
		_advance()


## Grounded steering: horizontal input toward the target, deadzone at
## [member reach_tolerance].
func _run_toward(target: Vector2) -> void:
	bot.input_jump = false
	bot.input_up = false
	bot.input_down = false
	_steer_x(target)


## Horizontal steering only; leaves the vertical and grab inputs alone.
func _steer_x(target: Vector2) -> void:
	var dx := target.x - bot.global_position.x
	bot.input_left = dx < -reach_tolerance
	bot.input_right = dx > reach_tolerance


## Mid-air steering; vetoed entirely when the drift envelope says the move
## would clip terrain.
func _steer_airborne(target: Vector2) -> void:
	if not _can_drift_toward(target):
		bot.input_left = false
		bot.input_right = false
		return
	var dx := target.x - bot.global_position.x
	bot.input_left = dx < -reach_tolerance
	bot.input_right = dx > reach_tolerance


## Drift check against the pathfinder's column scan; grounded steering is
## always allowed.
func _can_drift_toward(target: Vector2) -> bool:
	if pathfinder == null or bot.is_on_floor():
		return true
	return not pathfinder.is_drift_blocked(bot.global_position, target)


## Launch impulse in px/s (0 = use the bot's default full jump) sized to the
## arc this jump actually needs.
##
## Math: with constant air speed, flight time is T = dx/v_x, so the impulse
## matching the parabola dy = v0·t − ½g·t² over that time is
## v0 = dy_up/T + g·T/2, with a +10% margin, clamped to the bot's capability.
## A target higher than ½g·T² (above the arc reachable in that flight time)
## falls back to the classic full jump. Near-vertical jumps use the
## energy-equivalent minimum sqrt(2·g·dy_up), also with 10% margin.
func _matched_impulse(launch: Vector2, target: Vector2) -> float:
	var gravity := bot.get_gravity_strength()
	var v_x := maxf(bot.move_speed, 1.0)
	var dx := absf(target.x - launch.x)
	var dy_up := launch.y - target.y
	if dx <= reach_tolerance:
		if dy_up <= 0.0:
			return 0.0
		return minf(sqrt(2.0 * gravity * dy_up) * 1.1, absf(bot.jump_velocity))
	var flight := dx / v_x
	if dy_up > 0.5 * gravity * flight * flight:
		return 0.0
	var impulse := (dy_up / flight + 0.5 * gravity * flight) * 1.1
	return clampf(impulse, 0.0, absf(bot.jump_velocity))


## Positional reach test; vertical tolerance is twice the horizontal one to
## tolerate landing lip overshoot.
func _reached(target: Vector2) -> bool:
	return (
		absf(bot.global_position.x - target.x) <= reach_tolerance
		and absf(bot.global_position.y - target.y) <= reach_tolerance * 2.0
	)


## World position of the waypoint after the current one (the jump's landing).
func _next_target(waypoint: PathWaypoint) -> Vector2:
	if _index + 1 < _path.waypoints.size():
		return _path.waypoints[_index + 1].world
	return waypoint.world


func _reached_x(target: Vector2) -> bool:
	return absf(bot.global_position.x - target.x) <= reach_tolerance


## Moves to the next waypoint and clears all per-waypoint state.
func _advance() -> void:
	_index += 1
	_launched = false
	_saw_air = false
	_dropping = false
	_matched_jump = false
	_nudge_side = 0
	_stuck_frames = 0


## Repaths to the goal when the bot has moved less than 0.1 px per physics
## frame for [member stuck_timeout_frames] frames.
func _watch_stuck() -> void:
	if bot.global_position.distance_squared_to(_last_position) < 0.01:
		_stuck_frames += 1
	else:
		_stuck_frames = 0
		_last_position = bot.global_position
	if _stuck_frames > stuck_timeout_frames:
		move_to(_goal_world)


## Clears all bot inputs (idle, or when there is no path to follow).
func _release_inputs() -> void:
	bot.input_left = false
	bot.input_right = false
	bot.input_jump = false
	bot.input_up = false
	bot.input_down = false
