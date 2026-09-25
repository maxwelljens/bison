@tool
class_name PlatformerPathfinder
extends Node2D

class MinHeap:
	var _keys: Array[Vector3i] = []
	var _priorities: Array[float] = []

	func size() -> int:
		return _keys.size()

	func push(key: Vector3i, priority: float) -> void:
		_keys.append(key)
		_priorities.append(priority)
		var index := _keys.size() - 1
		while index > 0:
			var parent := (index - 1) >> 1
			if _priorities[parent] <= _priorities[index]:
				break
			_swap(index, parent)
			index = parent

	func pop() -> Vector3i:
		var top := _keys[0]
		var last := _keys.size() - 1
		_keys[0] = _keys[last]
		_priorities[0] = _priorities[last]
		_keys.resize(last)
		_priorities.resize(last)
		if last > 0:
			_sift_down(0)
		return top

	func _sift_down(index: int) -> void:
		var size := _keys.size()
		while true:
			var smallest := index
			var left := index * 2 + 1
			var right := left + 1
			if left < size and _priorities[left] < _priorities[smallest]:
				smallest = left
			if right < size and _priorities[right] < _priorities[smallest]:
				smallest = right
			if smallest == index:
				return
			_swap(index, smallest)
			index = smallest

	func _swap(a: int, b: int) -> void:
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
		var priority := _priorities[a]
		_priorities[a] = _priorities[b]
		_priorities[b] = priority


const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const INVALID_CELL := Vector2i(-1, -1)

@export var tilemap: TileMapLayer

@export_category("Search")
@export var air_penalty: float = 0.25
@export var heuristic_weight: float = 1.0
@export var goal_snap_max_cells: int = 8
@export var max_expansions: int = 20000
@export var use_dominance_pruning: bool = true

@export_group("Preview")
@export var preview_enabled: bool = true
@export var preview_from: Vector2 = Vector2(-152.0, 8.0):
	set(value):
		preview_from = value
		_run_preview_if_ready()
@export var preview_to: Vector2 = Vector2(168.0, 8.0):
	set(value):
		preview_to = value
		_run_preview_if_ready()
@export var preview_jump_velocity: float = -300.0:
	set(value):
		preview_jump_velocity = value
		_run_preview_if_ready()
@export var preview_move_speed: float = 130.0:
	set(value):
		preview_move_speed = value
		_run_preview_if_ready()

@export_category("Debug")
@export var debug_draw: bool = true
@export var debug_draw_explored: bool = true

var _grid: PlatformerGrid
var _last_path: PathData
var _explored: Dictionary = {}
var _max_jump_cells: int = 2
var _preview_pending: bool = true
var _jump: PlatformerJumpProfile
var _launch: Dictionary = {}
var _project_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var _g: Dictionary = {}
var _parents: Dictionary = {}
var _closed: Dictionary = {}
var _cell_nodes: Dictionary = {}


func _ready() -> void:
	z_index = 95
	call_deferred("_run_preview_if_ready")


func _process(_delta: float) -> void:
	if _preview_pending:
		_preview_pending = false
		_run_preview_if_ready()


func get_cell_size() -> int:
	if tilemap != null and tilemap.tile_set != null:
		return tilemap.tile_set.tile_size.x
	return 16


func rebuild_grid() -> void:
	_grid = null
	if tilemap != null:
		_grid = PlatformerGrid.from_tilemap(tilemap)


func is_drift_blocked(from_world: Vector2, to_world: Vector2) -> bool:
	if _grid == null:
		rebuild_grid()
	if _grid == null:
		return false
	var top := _grid.world_to_cell(Vector2(from_world.x, minf(from_world.y, to_world.y) - 3.0)).y
	var bottom := _grid.world_to_cell(Vector2(from_world.x, maxf(from_world.y, to_world.y) + 7.0)).y
	var from_column := _grid.world_to_cell(from_world).x
	var to_column := _grid.world_to_cell(to_world).x
	for x in range(mini(from_column, to_column), maxi(from_column, to_column) + 1):
		for y in range(mini(top, bottom), maxi(top, bottom) + 1):
			if _grid.is_solid(Vector2i(x, y)):
				return true
	return false


func find_path(start_world: Vector2, goal_world: Vector2, jump: PlatformerJumpProfile) -> PathData:
	var result := PathData.new()
	_jump = jump
	_max_jump_cells = jump.height_cells()
	if tilemap == null:
		push_warning("PlatformerPathfinder: no tilemap assigned")
		_last_path = result
		return result
	if _grid == null:
		rebuild_grid()

	_explored.clear()
	_g.clear()
	_parents.clear()
	_closed.clear()
	_cell_nodes.clear()
	_launch.clear()
	var open := MinHeap.new()

	result.start_cell = _grid.world_to_cell(start_world)
	result.goal_cell = _snap_goal(_grid.world_to_cell(goal_world))
	if not _grid.is_passable(result.start_cell) or not _grid.is_passable(result.goal_cell):
		_last_path = result
		queue_redraw()
		return result

	var start_jv := 0
	if not _grid.has_ground_below(result.start_cell):
		start_jv = _peak()
	var start_key := Vector3i(result.start_cell.x, result.start_cell.y, start_jv)
	_g[start_key] = 0.0
	_register_cell_node(result.start_cell, start_jv)
	open.push(start_key, _heuristic(result.start_cell, result.goal_cell))

	var goal_key := start_key
	var found := false
	var expansions := 0
	while open.size() > 0 and expansions < max_expansions:
		var current: Vector3i = open.pop()
		if _closed.has(current):
			continue
		_closed[current] = true
		expansions += 1
		_explored[Vector2i(current.x, current.y)] = true
		if current.x == result.goal_cell.x and current.y == result.goal_cell.y:
			goal_key = current
			found = true
			break
		_expand(current, open, result.goal_cell)

	result.cells_explored = expansions
	if found:
		var states: Array[Vector3i] = []
		var cursor := goal_key
		states.append(cursor)
		while _parents.has(cursor):
			cursor = _parents[cursor]
			states.append(cursor)
		states.reverse()
		result.waypoints = _classify(states)
		result.found = not result.waypoints.is_empty()
	_last_path = result
	queue_redraw()
	return result


func _expand(state: Vector3i, open: MinHeap, goal_cell: Vector2i) -> void:
	var cell := Vector2i(state.x, state.y)
	var jv := state.z
	var base_cost: float = _g[state]
	for direction in DIRECTIONS:
		var next_cell: Vector2i = cell + direction
		if not _grid.is_passable(next_cell):
			continue
		if direction == Vector2i.UP and not _can_rise(jv):
			continue
		if direction != Vector2i.UP and direction != Vector2i.DOWN and not _allows_sideways(jv):
			continue
		var launch: Vector2i = cell
		if jv != 0:
			launch = _launch.get(state, cell)
		var next_jv := 0
		if not _grid.has_ground_below(next_cell):
			next_jv = _next_jump_value(jv, direction)
			if _is_ceiling(next_cell):
				next_jv = maxi(next_jv, _peak() + (1 if _is_walled_in(next_cell) else 0))
			var height := launch.y - next_cell.y
			var falling := next_jv > _peak() or height <= 0
			if absi(next_cell.x - launch.x) > _jump.drift_cells(height, falling):
				continue
		if use_dominance_pruning and _is_dominated(next_cell, next_jv):
			continue
		var key := Vector3i(next_cell.x, next_cell.y, next_jv)
		if _closed.has(key):
			continue
		var tentative := base_cost + 1.0 + air_penalty * float(next_jv)
		if _g.has(key) and tentative >= _g[key]:
			continue
		_g[key] = tentative
		_parents[key] = state
		_launch[key] = launch
		_register_cell_node(next_cell, next_jv)
		open.push(key, tentative + _heuristic(next_cell, goal_cell))


func _next_jump_value(jv: int, direction: Vector2i) -> int:
	var next_even := jv + 2 if jv % 2 == 0 else jv + 1
	if direction == Vector2i.UP:
		if jv == 0:
			return 3
		return next_even
	if direction == Vector2i.DOWN:
		return maxi(next_even, _peak())
	return jv + 1


func _can_rise(jv: int) -> bool:
	return jv == 0 or (jv >= 3 and jv < _peak())


func _allows_sideways(jv: int) -> bool:
	return jv % 2 == 0


func _is_dominated(cell: Vector2i, jv: int) -> bool:
	var nodes: Array = _cell_nodes.get(cell, [])
	if nodes.is_empty():
		return false
	var lowest := 1 << 30
	var side_capable := false
	for value in nodes:
		lowest = mini(lowest, value)
		if _allows_sideways(value):
			side_capable = true
	return lowest <= jv and side_capable


func _register_cell_node(cell: Vector2i, jv: int) -> void:
	if not _cell_nodes.has(cell):
		_cell_nodes[cell] = []
	var nodes: Array = _cell_nodes[cell]
	if not nodes.has(jv):
		nodes.append(jv)


func _peak() -> int:
	return 2 * _max_jump_cells


func _is_ceiling(cell: Vector2i) -> bool:
	return _grid.is_solid(cell + Vector2i.UP)


func _is_walled_in(cell: Vector2i) -> bool:
	return not _grid.is_passable(cell + Vector2i.LEFT) and not _grid.is_passable(cell + Vector2i.RIGHT)


func _heuristic(cell: Vector2i, goal: Vector2i) -> float:
	return float(absi(cell.x - goal.x) + absi(cell.y - goal.y)) * heuristic_weight


func _snap_goal(cell: Vector2i) -> Vector2i:
	var candidate := cell
	for _step in range(goal_snap_max_cells + 1):
		if _grid.is_passable(candidate) and _grid.has_ground_below(candidate):
			return candidate
		candidate += Vector2i.DOWN
	return cell


func _classify(states: Array[Vector3i]) -> Array[PathWaypoint]:
	var waypoints: Array[PathWaypoint] = []
	var index := 0
	while index < states.size():
		if states[index].z == 0:
			index = _classify_ground_run(states, index, waypoints)
		else:
			index = _classify_air_run(states, index, waypoints)
	var goal_cell := Vector2i(states[states.size() - 1].x, states[states.size() - 1].y)
	if waypoints.is_empty() or waypoints[waypoints.size() - 1].cell != goal_cell:
		waypoints.append(_make_waypoint(PathWaypoint.Kind.WALK, goal_cell))
	return waypoints


func _classify_ground_run(states: Array[Vector3i], start: int, out: Array[PathWaypoint]) -> int:
	var index := start
	var last_direction := Vector2i.ZERO
	while index < states.size() and states[index].z == 0:
		var cell := Vector2i(states[index].x, states[index].y)
		if index + 1 < states.size() and states[index + 1].z == 0:
			var next := Vector2i(states[index + 1].x, states[index + 1].y)
			var step := next - cell
			if step.y < 0:
				out.append(_make_waypoint(PathWaypoint.Kind.JUMP, cell, next))
				out.append(_make_waypoint(PathWaypoint.Kind.LAND, next))
				last_direction = Vector2i.ZERO
			elif step.y > 0 and _grid.is_oneway(next):
				out.append(_make_waypoint(PathWaypoint.Kind.DROP_THROUGH, cell))
				last_direction = Vector2i.ZERO
			else:
				var direction := Vector2i(signi(step.x), signi(step.y))
				if last_direction != Vector2i.ZERO and direction != last_direction:
					out.append(_make_waypoint(PathWaypoint.Kind.WALK, cell))
				last_direction = direction
		index += 1
	var run_end := Vector2i(states[index - 1].x, states[index - 1].y)
	if out.is_empty() or out[out.size() - 1].cell != run_end:
		out.append(_make_waypoint(PathWaypoint.Kind.WALK, run_end))
	return index


func _classify_air_run(states: Array[Vector3i], start: int, out: Array[PathWaypoint]) -> int:
	var first := Vector2i(states[start].x, states[start].y)
	var launch := first
	if start > 0:
		launch = Vector2i(states[start - 1].x, states[start - 1].y)
	var first_jv := states[start].z
	var apex := first
	var through_oneway := _grid.is_oneway(first)
	var index := start
	while index < states.size() and states[index].z != 0:
		var cell := Vector2i(states[index].x, states[index].y)
		if cell.y < apex.y:
			apex = cell
		if _grid.is_oneway(cell):
			through_oneway = true
		index += 1
	var land := Vector2i(states[index - 1].x, states[index - 1].y)
	if index < states.size() and states[index].z == 0:
		land = Vector2i(states[index].x, states[index].y)
	if land.y < apex.y:
		apex = land
	if first_jv >= 3:
		out.append(_make_waypoint(PathWaypoint.Kind.JUMP, launch, apex))
	elif _grid.is_oneway(first) and first == launch + Vector2i.DOWN:
		var drop := _make_waypoint(PathWaypoint.Kind.DROP_THROUGH, launch)
		drop.through_oneway = true
		out.append(drop)
	else:
		var fall := _make_waypoint(PathWaypoint.Kind.FALL, launch)
		fall.through_oneway = through_oneway
		out.append(fall)
	out.append(_make_waypoint(PathWaypoint.Kind.LAND, land))
	return index


func _make_waypoint(kind: PathWaypoint.Kind, cell: Vector2i, apex: Vector2i = INVALID_CELL) -> PathWaypoint:
	var waypoint := PathWaypoint.new()
	waypoint.kind = kind
	waypoint.cell = cell
	waypoint.world = _grid.cell_to_world(cell)
	if apex != INVALID_CELL:
		waypoint.apex_cell = apex
		waypoint.apex_world = _grid.cell_to_world(apex)
	return waypoint


func _run_preview_if_ready() -> void:
	if not is_node_ready() or not preview_enabled or tilemap == null:
		return
	var jump := PlatformerJumpProfile.new(preview_jump_velocity, _project_gravity, preview_move_speed, float(get_cell_size()))
	find_path(preview_from, preview_to, jump)


func _draw() -> void:
	if debug_draw and _grid != null:
		if debug_draw_explored:
			for cell in _explored:
				draw_circle(to_local(_grid.cell_to_world(cell)), 2.0, Color(0.35, 0.75, 1.0, 0.35))
		if _last_path != null and _last_path.found:
			var previous := Vector2.ZERO
			var first := true
			for waypoint in _last_path.waypoints:
				var point := to_local(waypoint.world)
				if not first:
					draw_line(previous, point, Color(1.0, 1.0, 1.0, 0.65), 1.5)
				first = false
				previous = point
				draw_circle(point, 3.5, _kind_color(waypoint.kind))
				if waypoint.kind == PathWaypoint.Kind.JUMP and waypoint.apex_world != Vector2.ZERO:
					draw_circle(to_local(waypoint.apex_world), 2.5, Color(0.6, 0.4, 1.0, 0.85))
	_draw_preview_markers()


func _draw_preview_markers() -> void:
	if not preview_enabled:
		return
	var start_invalid := not _preview_point_valid(preview_from, false)
	var goal_invalid := not _preview_point_valid(preview_to, true)
	if _last_path != null and not _last_path.found:
		draw_line(to_local(preview_from), to_local(preview_to), Color(0.9, 0.15, 0.15, 0.45), 2.0)
	_draw_marker(to_local(preview_from), Color(0.3, 1.0, 0.45), start_invalid)
	_draw_marker(to_local(preview_to), Color(1.0, 0.35, 0.4), goal_invalid)
	if _grid != null:
		var snapped_world := _grid.cell_to_world(_snap_goal(_grid.world_to_cell(preview_to)))
		if snapped_world.distance_to(preview_to) > 1.0:
			_draw_marker(to_local(snapped_world), Color(1.0, 1.0, 1.0, 0.9), false, 5.0)


func _preview_point_valid(world: Vector2, snap_to_ground: bool) -> bool:
	if _grid == null:
		return true
	var cell := _grid.world_to_cell(world)
	if snap_to_ground:
		cell = _snap_goal(cell)
	return _grid.is_passable(cell)


func _draw_marker(center: Vector2, color: Color, invalid: bool, half_size: float = 7.0) -> void:
	var rect := Rect2(center - Vector2(half_size, half_size), Vector2(half_size, half_size) * 2.0)
	if invalid:
		draw_rect(rect, Color(color, 0.3), true)
		draw_line(rect.position, rect.position + rect.size, color, 2.5)
		draw_line(rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), color, 2.5)
	draw_rect(rect, color, false, 2.5)


func _kind_color(kind: PathWaypoint.Kind) -> Color:
	match kind:
		PathWaypoint.Kind.JUMP:
			return Color(0.35, 0.65, 1.0, 0.95)
		PathWaypoint.Kind.LAND:
			return Color(1.0, 0.9, 0.3, 0.95)
		PathWaypoint.Kind.FALL:
			return Color(1.0, 0.55, 0.2, 0.95)
		PathWaypoint.Kind.DROP_THROUGH:
			return Color(0.85, 0.4, 1.0, 0.95)
	return Color(0.4, 1.0, 0.5, 0.95)
