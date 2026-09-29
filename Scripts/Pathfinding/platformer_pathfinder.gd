@tool
class_name PlatformerPathfinder
extends Node2D
## Jump-value A* pathfinder for platformer terrain.
##
## The search runs over (x, y, jumpValue) states: the z coordinate encodes the
## airborne phase, and the parity of the jump value alternates horizontal and
## vertical moves so grid steps approximate a parabolic arc (approach from the
## Envato Tuts+ platformer pathfinding tutorial series, ported to GDScript).
## Produces typed [PathWaypoint]s via [method find_path]; jump reach is bounded
## by a [PlatformerJumpProfile] derived from live physics, so tuning jump
## velocity honestly changes which routes exist.

## Hand-rolled binary min-heap with parallel key/priority arrays; the A* open set.
class MinHeap:
	var _keys: Array[Vector3i] = []
	var _priorities: Array[float] = []

	## Number of queued entries.
	func size() -> int:
		return _keys.size()

	## Pushes a key with its f-cost priority.
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

	## Removes and returns the lowest-priority key.
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


## 4-neighborhood movement directions.
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## Sideways step-off targets from a ladder rung: crossing cells at rung level
## and one cell up, where a crossing's surface meets the rung's top edge.
const CLIMB_STEP_OFFS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.LEFT + Vector2i.UP,
	Vector2i.RIGHT + Vector2i.UP,
]
## "No cell" sentinel for optional cell values.
const INVALID_CELL := Vector2i(-1, -1)
## Jump value marking ladder climb states in the search lattice.
const CLIMB_JV := -1

## TileMapLayer the search grid is baked from.
@export var tilemap: TileMapLayer:
	set(value):
		tilemap = value
		_grid = null
		_run_preview_if_ready()

## TileMapLayer group used to auto-resolve the baked map when no explicit
## [member tilemap] was assigned.
const MAP_GROUP := "navigation"

@export_category("Search")
## Extra edge cost per jump-value unit; punishes staying high and airborne.
@export var air_penalty: float = 0.25
## Weighted-A* factor on the heuristic; > 1 trades optimality for speed.
@export var heuristic_weight: float = 1.0
## Max downward cells the goal may snap to standable ground.
@export var goal_snap_max_cells: int = 8
## Search budget in expanded states before giving up.
@export var max_expansions: int = 20000
## Skip states that a strictly more capable state at the same cell dominates.
@export var use_dominance_pruning: bool = true
## Cost of grabbing, topping out of or stepping off a ladder, in walk cells.
@export var climb_grab_cost: float = 0.5

@export_group("Preview")
## Runs and draws an automatic route between the preview endpoints.
@export var preview_enabled: bool
## Editor preview: route start point in world px.
@export var preview_from: Vector2 = Vector2(-152.0, 8.0):
	set(value):
		preview_from = value
		_run_preview_if_ready()
## Editor preview: route goal point in world px (snapped to standable ground).
@export var preview_to: Vector2 = Vector2(168.0, 8.0):
	set(value):
		preview_to = value
		_run_preview_if_ready()
## Editor preview: jump impulse in px/s used for the preview route.
@export var preview_jump_velocity: float = -300.0:
	set(value):
		preview_jump_velocity = value
		_run_preview_if_ready()
## Editor preview: run speed in px/s used for the preview route.
@export var preview_move_speed: float = 130.0:
	set(value):
		preview_move_speed = value
		_run_preview_if_ready()

@export_category("Debug")
## Draw explored cells and the last route.
@export var debug_draw: bool
## Also draw a dot per explored cell (can be noisy on big searches).
@export var debug_draw_explored: bool

# Baked occupancy grid snapshot; rebuilt lazily by rebuild_grid().
var _grid: PlatformerGrid
# Most recent search result; kept for the debug overlay.
var _last_path: PathData
# Cells touched by the last search, for the explored-cells overlay.
var _explored: Dictionary = {}
# Jump height in cells from the current profile; drives _peak().
var _max_jump_cells: int = 2
# One-shot flag: the preview run is deferred to the first _process tick
# because exported node refs can be null inside _ready of non-root nodes.
var _preview_pending: bool = true
# Jump profile of the current search.
var _jump: PlatformerJumpProfile
# Per-state launch cell: airborne states remember where their arc began,
# which the drift envelope is measured from.
var _launch: Dictionary = {}
# Gravity read at startup; jump math never hardcodes it.
var _project_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# A* bookkeeping keyed by Vector3i(x, y, jump value): g-cost, parent link,
# closed set, and per-cell seen jump values (dominance pruning).
var _g: Dictionary = {}
var _parents: Dictionary = {}
var _closed: Dictionary = {}
var _cell_nodes: Dictionary = {}


func _ready() -> void:
	# 95 keeps path overlays above GridDebugDraw's 90.
	z_index = 95
	call_deferred("_run_preview_if_ready")


func _process(_delta: float) -> void:
	if _preview_pending:
		_preview_pending = false
		_resolve_tilemap()
		_run_preview_if_ready()


## Picks the tilemap to bake the grid from when none was assigned explicitly.
## The trusted one-shot _process path calls this after readiness; strict
## validation weeds out misconfigured levels by warning on any group count
## other than exactly one TileMapLayer.
func _resolve_tilemap() -> void:
	if tilemap != null:
		return
	var candidates: Array[Node] = get_tree().get_nodes_in_group(MAP_GROUP)
	var maps: Array[TileMapLayer] = []
	for candidate in candidates:
		if candidate is TileMapLayer:
			maps.append(candidate)
	match maps.size():
		0:
			push_warning("PlatformerPathfinder: no TileMapLayer in the '%s' group" % MAP_GROUP)
		1:
			tilemap = maps[0]
		_:
			push_warning(
				"PlatformerPathfinder: %d TileMapLayers in the '%s' group, using the first (tree order)"
					% [maps.size(), MAP_GROUP])
			tilemap = maps[0]


## Tile width in px; falls back to 16 when no tileset is assigned.
func get_cell_size() -> int:
	if tilemap != null and tilemap.tile_set != null:
		return tilemap.tile_set.tile_size.x
	return 16


## Re-bakes the occupancy grid from the tilemap.
func rebuild_grid() -> void:
	_grid = null
	if tilemap != null:
		_grid = PlatformerGrid.from_tilemap(tilemap)


## True when a solid cell blocks the column strip between two airborne points;
## used to veto mid-air steering that would clip terrain. The strip is padded
## 3 px above and 7 px below to cover the body height around the path line.
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


## Runs the A* search and classifies the resulting state chain into typed
## waypoints. [param jump] bounds which arcs physically exist. The result is
## kept as the last path for the debug overlay.
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

	# A start without ground below begins mid-arc, at peak jump value.
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
		# Goal test ignores the jump value: any phase may end the route.
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
	if jv == CLIMB_JV:
		_expand_climb(state, open, goal_cell)
		return
	for direction in DIRECTIONS:
		var next_cell: Vector2i = cell + direction
		if not _grid.is_passable(next_cell):
			continue
		if direction == Vector2i.UP and not _can_rise(jv):
			continue
		if direction != Vector2i.UP and direction != Vector2i.DOWN and not _allows_sideways(jv):
			continue
		# Airborne states carry their launch cell for the drift envelope below.
		var launch: Vector2i = cell
		if jv != 0:
			launch = _launch.get(state, cell)
		var next_jv := 0
		if not _grid.has_ground_below(next_cell):
			next_jv = _next_jump_value(jv, direction)
			if _is_ceiling(next_cell):
				# Ceiling bump forces the descent phase. The +1 makes the value
				# odd (sideways disabled) when walled in on both sides.
				next_jv = maxi(next_jv, _peak() + (1 if _is_walled_in(next_cell) else 0))
			var height := launch.y - next_cell.y
			var falling := next_jv > _peak() or height <= 0
			# Drift envelope: reject cells outside the physical arc from launch.
			if absi(next_cell.x - launch.x) > _jump.drift_cells(height, falling):
				continue
		# Base step cost plus an airborne penalty scaled by jump value.
		var step_cost := 1.0 + air_penalty * float(next_jv)
		_relax(open, state, next_cell, next_jv, step_cost, launch, goal_cell)
	_try_ladder_grabs(state, cell, jv, open, goal_cell)


## Relaxes one lattice edge from [param from_state] to [param to_cell] at
## [param to_jv], costing [param step_cost]; [param launch] records the
## airborne arc's origin for the drift envelope.
func _relax(
		open: MinHeap,
		from_state: Vector3i,
		to_cell: Vector2i,
		to_jv: int,
		step_cost: float,
		launch: Vector2i,
		goal_cell: Vector2i,
) -> void:
	if use_dominance_pruning and to_jv >= 0 and _is_dominated(to_cell, to_jv):
		return
	var key := Vector3i(to_cell.x, to_cell.y, to_jv)
	if _closed.has(key):
		return
	var tentative: float = _g[from_state] + step_cost
	if _g.has(key) and tentative >= _g[key]:
		return
	_g[key] = tentative
	_parents[key] = from_state
	_launch[key] = launch
	_register_cell_node(to_cell, to_jv)
	open.push(key, tentative + _heuristic(to_cell, goal_cell))


## Ladder grab edges into the climb phase: in place when the cell is a rung
## (a grounded grab or a mid-air catch), or down through a one-way landing
## onto the rung two cells below (the descend grab).
func _try_ladder_grabs(
		state: Vector3i,
		cell: Vector2i,
		jv: int,
		open: MinHeap,
		goal_cell: Vector2i,
) -> void:
	if _grid.is_ladder(cell):
		_relax(open, state, cell, CLIMB_JV, climb_grab_cost, cell, goal_cell)
		return
	if jv != 0:
		return
	var rung := cell + Vector2i.DOWN + Vector2i.DOWN
	if _grid.is_oneway(cell + Vector2i.DOWN) and _grid.is_ladder(rung):
		_relax(open, state, rung, CLIMB_JV, climb_grab_cost, cell, goal_cell)


## Climb-phase expansion: vertical chain travel plus every way off the
## ladder — top out onto the first standable surface at or above the chain
## top (one-way landings are risen through), step off onto a crossing beside
## the rung, drop off, or jump off at full power.
func _expand_climb(state: Vector3i, open: MinHeap, goal_cell: Vector2i) -> void:
	var cell := Vector2i(state.x, state.y)
	var up := cell + Vector2i.UP
	var down := cell + Vector2i.DOWN
	var step_cost := _climb_step_cost()
	if _grid.is_ladder(up):
		_relax(open, state, up, CLIMB_JV, step_cost, cell, goal_cell)
	if _grid.is_ladder(down):
		_relax(open, state, down, CLIMB_JV, step_cost, cell, goal_cell)
	if not _grid.is_ladder(up):
		var stand := INVALID_CELL
		var standable := false
		if LadderMap.has_standable_top(_grid.source, cell):
			stand = up
			standable = _grid.is_passable(stand)
		elif LadderMap.has_standable_top(_grid.source, up) and _grid.is_oneway(up):
			stand = up + Vector2i.UP
			standable = _grid.is_passable(stand)
		if standable:
			_relax(open, state, stand, 0, climb_grab_cost, cell, goal_cell)
	# Dropping off mid-chain needs shimmy room; the chain's bottom edge and
	# chain breaks drop without one.
	if _grid.is_passable(down) and (
			not _grid.is_ladder(down)
			or _grid.is_passable(cell + Vector2i.LEFT)
			or _grid.is_passable(cell + Vector2i.RIGHT)):
		var fall_jv := _next_jump_value(0, Vector2i.DOWN)
		_relax(open, state, down, fall_jv, 1.0 + air_penalty * float(fall_jv), cell, goal_cell)
	if _grid.is_passable(up):
		var jump_jv := _next_jump_value(0, Vector2i.UP)
		_relax(open, state, up, jump_jv, 1.0 + air_penalty * float(jump_jv), cell, goal_cell)
	for offset in CLIMB_STEP_OFFS:
		var crossing: Vector2i = cell + offset
		if _grid.is_passable(crossing) and _grid.has_ground_below(crossing):
			_relax(open, state, crossing, 0, climb_grab_cost, cell, goal_cell)
	if _grid.has_ground_below(cell):
		_relax(open, state, cell, 0, climb_grab_cost, cell, goal_cell)


## Cost of one ladder cell in walk-cell units: a cell takes cell_size /
## climb_speed seconds to climb against cell_size / move_speed to walk.
func _climb_step_cost() -> float:
	if _jump.climb_speed <= 0.0:
		return 1.0
	return _jump.move_speed / _jump.climb_speed


## Jump-value transition for a move in [param direction].
##
## Parity rule: horizontal steps cost +1 and are allowed only on even values,
## so horizontal and vertical moves alternate and grid steps approximate a
## parabola. Rising uses the next even value (takeoff goes 2 -> 3); falling is
## clamped at least to the peak (descent phase).
func _next_jump_value(jv: int, direction: Vector2i) -> int:
	var next_even := jv + 2 if jv % 2 == 0 else jv + 1
	if direction == Vector2i.UP:
		if jv == 0:
			return 3
		return next_even
	if direction == Vector2i.DOWN:
		return maxi(next_even, _peak())
	return jv + 1


## Rising is allowed grounded, or mid-arc between takeoff and the peak.
func _can_rise(jv: int) -> bool:
	return jv == 0 or (jv >= 3 and jv < _peak())


## Only even jump values may step sideways (see [method _next_jump_value]).
func _allows_sideways(jv: int) -> bool:
	return jv % 2 == 0


## Dominance pruning: skip the state when another state already seen at the
## same cell reached it with at most this jump value and can still step
## sideways (strictly more capable).
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


## Records a jump value seen at a cell for [method _is_dominated]. Climb
## states never dominate, so they are not recorded.
func _register_cell_node(cell: Vector2i, jv: int) -> void:
	if jv < 0:
		return
	if not _cell_nodes.has(cell):
		_cell_nodes[cell] = []
	var nodes: Array = _cell_nodes[cell]
	if not nodes.has(jv):
		nodes.append(jv)


## Peak jump value: 2 per jump-height cell, so the lattice size tracks
## the profile's reach.
func _peak() -> int:
	return 2 * _max_jump_cells


## True when the cell has a solid ceiling directly above.
func _is_ceiling(cell: Vector2i) -> bool:
	return _grid.is_solid(cell + Vector2i.UP)


## True when both horizontal neighbours block movement.
func _is_walled_in(cell: Vector2i) -> bool:
	return not _grid.is_passable(cell + Vector2i.LEFT) and not _grid.is_passable(cell + Vector2i.RIGHT)


## Weighted Manhattan distance to the goal.
func _heuristic(cell: Vector2i, goal: Vector2i) -> float:
	return float(absi(cell.x - goal.x) + absi(cell.y - goal.y)) * heuristic_weight


## Walks down to the nearest standable cell within goal_snap_max_cells;
## returns the input cell when no standable cell is found.
func _snap_goal(cell: Vector2i) -> Vector2i:
	var candidate := cell
	for _step in range(goal_snap_max_cells + 1):
		if _grid.is_passable(candidate) and _grid.has_ground_below(candidate):
			return candidate
		candidate += Vector2i.DOWN
	return cell


## Turns the state chain into waypoints: grounded runs (jv == 0) and airborne
## runs are classified separately, and the route always ends at the goal cell.
func _classify(states: Array[Vector3i]) -> Array[PathWaypoint]:
	var waypoints: Array[PathWaypoint] = []
	var index := 0
	while index < states.size():
		if states[index].z == 0:
			var from_climb := index > 0 and states[index - 1].z == CLIMB_JV
			index = _classify_ground_run(states, index, waypoints, from_climb)
		elif states[index].z == CLIMB_JV:
			index = _classify_climb_run(states, index, waypoints)
		else:
			index = _classify_air_run(states, index, waypoints)
	var goal_cell := Vector2i(states[states.size() - 1].x, states[states.size() - 1].y)
	if waypoints.is_empty() or waypoints[waypoints.size() - 1].cell != goal_cell:
		waypoints.append(_make_waypoint(PathWaypoint.Kind.WALK, goal_cell))
	return waypoints


## Ground run: WALK at the start (the ladder exit cell when leaving a
## climb) and at direction changes, JUMP+LAND pairs for upward steps,
## DROP_THROUGH for steps onto one-way tops; closes with WALK at the run end.
## Returns the state index after the run.
func _classify_ground_run(
		states: Array[Vector3i],
		start: int,
		out: Array[PathWaypoint],
		from_climb: bool = false,
) -> int:
	var index := start
	var last_direction := Vector2i.ZERO
	# Walk-run compression would otherwise swallow the exit cell, and the
	# follower needs it to pick the right way off the ladder.
	if from_climb:
		out.append(_make_waypoint(PathWaypoint.Kind.WALK, Vector2i(states[start].x, states[start].y)))
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


## Climb run: CLIMB at the run's first cell (the grab), at direction
## reversals and at the run end (the exit cell). Returns the state index
## after the run.
func _classify_climb_run(states: Array[Vector3i], start: int, out: Array[PathWaypoint]) -> int:
	var first := Vector2i(states[start].x, states[start].y)
	out.append(_make_waypoint(PathWaypoint.Kind.CLIMB, first))
	var index := start
	var last_direction := 0
	while index < states.size() and states[index].z == CLIMB_JV:
		var cell := Vector2i(states[index].x, states[index].y)
		if index + 1 < states.size() and states[index + 1].z == CLIMB_JV:
			var next := Vector2i(states[index + 1].x, states[index + 1].y)
			var direction := signi(next.y - cell.y)
			if last_direction != 0 and direction != last_direction:
				out.append(_make_waypoint(PathWaypoint.Kind.CLIMB, cell))
			last_direction = direction
		index += 1
	var climb_end := Vector2i(states[index - 1].x, states[index - 1].y)
	if out[out.size() - 1].cell != climb_end:
		out.append(_make_waypoint(PathWaypoint.Kind.CLIMB, climb_end))
	return index


## Airborne run: the apex is the highest cell (including the landing cell).
## A first jump value >= 3 marks a powered takeoff (JUMP at the launch cell);
## stepping onto a one-way's first cell from a grounded launch is
## DROP_THROUGH; anything else is FALL.
## Always closes with LAND. Returns the state index after the run.
func _classify_air_run(states: Array[Vector3i], start: int, out: Array[PathWaypoint]) -> int:
	var first := Vector2i(states[start].x, states[start].y)
	var launch := first
	if start > 0:
		launch = Vector2i(states[start - 1].x, states[start - 1].y)
	var first_jv := states[start].z
	var apex := first
	var through_oneway := _grid.is_oneway(first)
	var index := start
	while index < states.size() and states[index].z > 0:
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
	elif start > 0 and states[start - 1].z == 0 and _grid.is_oneway(first) \
			and first == launch + Vector2i.DOWN:
		var drop := _make_waypoint(PathWaypoint.Kind.DROP_THROUGH, launch)
		drop.through_oneway = true
		out.append(drop)
	else:
		var fall := _make_waypoint(PathWaypoint.Kind.FALL, launch)
		fall.through_oneway = through_oneway
		out.append(fall)
	# A climb run right after the air run is a mid-air catch; the CLIMB
	# waypoint at the catch cell replaces the landing marker.
	if index >= states.size() or states[index].z != CLIMB_JV:
		out.append(_make_waypoint(PathWaypoint.Kind.LAND, land))
	return index


## Builds a waypoint with world coordinates; [param apex] is optional and
## only set for jumps.
func _make_waypoint(kind: PathWaypoint.Kind, cell: Vector2i, apex: Vector2i = INVALID_CELL) -> PathWaypoint:
	var waypoint := PathWaypoint.new()
	waypoint.kind = kind
	waypoint.cell = cell
	waypoint.world = _grid.cell_to_world(cell)
	if apex != INVALID_CELL:
		waypoint.apex_cell = apex
		waypoint.apex_world = _grid.cell_to_world(apex)
	return waypoint


## Runs the preview route when enabled and the node is wired up.
func _run_preview_if_ready() -> void:
	if not is_node_ready() or not preview_enabled or tilemap == null:
		return
	var jump := PlatformerJumpProfile.new(preview_jump_velocity, _project_gravity, preview_move_speed, float(get_cell_size()))
	find_path(preview_from, preview_to, jump)


## Debug overlay: explored-cell dots, the waypoint polyline with per-kind
## colored dots, purple apex dots, and the preview markers.
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


## Preview endpoints (green/red), a red line when no route exists, and a
## white marker where the goal would snap to standable ground.
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


## Whether a preview endpoint lands in a passable cell (after goal snapping).
func _preview_point_valid(world: Vector2, snap_to_ground: bool) -> bool:
	if _grid == null:
		return true
	var cell := _grid.world_to_cell(world)
	if snap_to_ground:
		cell = _snap_goal(cell)
	return _grid.is_passable(cell)


## Square preview marker; invalid points get a filled body and an X.
func _draw_marker(center: Vector2, color: Color, invalid: bool, half_size: float = 7.0) -> void:
	var rect := Rect2(center - Vector2(half_size, half_size), Vector2(half_size, half_size) * 2.0)
	if invalid:
		draw_rect(rect, Color(color, 0.3), true)
		draw_line(rect.position, rect.position + rect.size, color, 2.5)
		draw_line(rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), color, 2.5)
	draw_rect(rect, color, false, 2.5)


## Per-kind overlay color for waypoint dots.
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
		PathWaypoint.Kind.CLIMB:
			return Color(0.2, 0.9, 0.85, 0.95)
	return Color(0.4, 1.0, 0.5, 0.95)
