class_name BotPathFollower
extends Node
## Waypoint executor: turns a computed path into bot inputs.
##
## Follows [PathData] waypoints by steering a [PlatformerBot] through them:
## runs along the ground, fires matched ballistic impulses at jumps, steers
## mid-air (gated by the pathfinder's drift envelope), and pulses drop-through
## at one-way platforms. Click-to-move and a stuck watchdog that repaths.

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
		bot.jump_velocity, bot.get_gravity_strength(), bot.move_speed, float(pathfinder.get_cell_size()))
	_path = pathfinder.find_path(bot.global_position, world, jump)
	_index = 0
	_launched = false
	_saw_air = false
	_dropping = false
	_matched_jump = false
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
				if _saw_air and bot.is_on_floor():
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
				bot.input_down = true
			_air_transition(waypoint)
		PathWaypoint.Kind.CLIMB:
			# Climbing execution arrives with the bot ladder slice; drop the
			# path for now instead of grinding the stuck watchdog on it.
			_path = null


## Unpowered air move: release jump, steer toward the next waypoint, and
## advance once the floor is regained after having been airborne.
func _air_transition(waypoint: PathWaypoint) -> void:
	bot.input_jump = false
	_steer_airborne(_next_target(waypoint))
	if not bot.is_on_floor():
		_saw_air = true
	if _saw_air and bot.is_on_floor():
		_advance()


## Grounded steering: horizontal input toward the target, deadzone at
## [member reach_tolerance].
func _run_toward(target: Vector2) -> void:
	bot.input_jump = false
	bot.input_down = false
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
	bot.input_down = false
