class_name BotPathFollower
extends Node

@export var bot: PlatformerBot
@export var pathfinder: PlatformerPathfinder

@export_category("Control")
@export var click_to_move: bool = true
@export var reach_tolerance: float = 3.0
@export var apex_tolerance: float = 4.0
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


func _air_transition(waypoint: PathWaypoint) -> void:
	bot.input_jump = false
	_steer_airborne(_next_target(waypoint))
	if not bot.is_on_floor():
		_saw_air = true
	if _saw_air and bot.is_on_floor():
		_advance()


func _run_toward(target: Vector2) -> void:
	bot.input_jump = false
	bot.input_down = false
	var dx := target.x - bot.global_position.x
	bot.input_left = dx < -reach_tolerance
	bot.input_right = dx > reach_tolerance


func _steer_airborne(target: Vector2) -> void:
	if not _can_drift_toward(target):
		bot.input_left = false
		bot.input_right = false
		return
	var dx := target.x - bot.global_position.x
	bot.input_left = dx < -reach_tolerance
	bot.input_right = dx > reach_tolerance


func _can_drift_toward(target: Vector2) -> bool:
	if pathfinder == null or bot.is_on_floor():
		return true
	return not pathfinder.is_drift_blocked(bot.global_position, target)


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


func _reached(target: Vector2) -> bool:
	return (
		absf(bot.global_position.x - target.x) <= reach_tolerance
		and absf(bot.global_position.y - target.y) <= reach_tolerance * 2.0
	)


func _next_target(waypoint: PathWaypoint) -> Vector2:
	if _index + 1 < _path.waypoints.size():
		return _path.waypoints[_index + 1].world
	return waypoint.world


func _reached_x(target: Vector2) -> bool:
	return absf(bot.global_position.x - target.x) <= reach_tolerance


func _advance() -> void:
	_index += 1
	_launched = false
	_saw_air = false
	_dropping = false
	_matched_jump = false
	_stuck_frames = 0


func _watch_stuck() -> void:
	if bot.global_position.distance_squared_to(_last_position) < 0.01:
		_stuck_frames += 1
	else:
		_stuck_frames = 0
		_last_position = bot.global_position
	if _stuck_frames > stuck_timeout_frames:
		move_to(_goal_world)


func _release_inputs() -> void:
	bot.input_left = false
	bot.input_right = false
	bot.input_jump = false
	bot.input_down = false
