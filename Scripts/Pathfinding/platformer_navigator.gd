class_name PlatformerNavigator
extends RefCounted
## Jump-value A* route engine over a baked [PlatformerGrid] snapshot.
##
## The search runs over (x, y, jumpValue) states: the z coordinate encodes the
## airborne phase, and the parity of the jump value alternates horizontal and
## vertical moves so grid steps approximate a parabolic arc (approach from the
## Envato Tuts+ platformer pathfinding tutorial series, ported to GDScript).
## Produces typed [PathWaypoint]s via [method route]; jump reach is bounded by
## a [PlatformerJumpProfile] derived from the requesting agent's kinematics,
## so tuning jump velocity honestly changes which routes exist.
##
## Pure and stateless between calls: every search runs in a fresh [Search]
## value, so queries are reentrant and never contaminate each other. No
## scene tree, no drawing, no warnings — scene concerns live in the
## [PlatformerPathfinder] adapter.

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


## Per-search bookkeeping, keyed by Vector3i(x, y, jump value): g-costs,
## parent links, the closed set, per-cell seen jump values (dominance
## pruning) and per-state launch cells (drift-envelope origins). One fresh
## instance per [method route] keeps the engine reentrant.
class Search:
	## Jump profile of this search.
	var jump: PlatformerJumpProfile
	## Jump height in cells from [member jump]; drives the lattice peak.
	var max_jump_cells: int = 2
	var g: Dictionary = {}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	var cell_nodes: Dictionary = {}
	var launch: Dictionary = {}
	## Cells touched by this search, for the explored-cells overlay.
	var explored: Dictionary = {}


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

## Baked world model; bind before querying. Queries with no grid return an
## empty result.
var grid: PlatformerGrid
## Search knobs, read at query time (never during a call, never mutated).
var tuning: PathTuning = PathTuning.new()


## Classifies a route between two world points for [param agent]'s physics.
## Returns a fresh [PathData] every call; the result also carries the search's
## explored cells for debug overlays.
func route(from_world: Vector2, to_world: Vector2, agent: AgentKinematics) -> PathData:
	if grid == null or agent == null:
		return PathData.new()
	var state := Search.new()
	state.jump = PlatformerJumpProfile.new(
		agent.jump_velocity,
		agent.gravity,
		agent.move_speed,
		float(grid.cell_size.x),
		agent.climb_speed,
	)
	state.max_jump_cells = state.jump.height_cells()
	return _run(state, from_world, to_world)


## True when a solid cell blocks the padded column strip between two airborne
## world points; used to veto mid-air steering that would clip terrain. The
## strip is padded [member PathTuning.drift_pad_top] px above and
## [member PathTuning.drift_pad_bottom] px below to cover the body height
## around the path line.
func is_drift_blocked(from_world: Vector2, to_world: Vector2) -> bool:
	if grid == null:
		return false
	return grid.is_strip_blocked(
		from_world, to_world, tuning.drift_pad_top, tuning.drift_pad_bottom)


## World point a goal snaps to: the nearest standable cell within
## [member PathTuning.goal_snap_max_cells] steps below [param world], else
## [param world] unchanged.
func snap_goal_world(world: Vector2) -> Vector2:
	if grid == null:
		return world
	return grid.cell_to_world(
		grid.snap_to_standable(grid.world_to_cell(world), tuning.goal_snap_max_cells))


## Runs the A* search and classifies the resulting state chain into typed
## waypoints. [param state] carries this query's bookkeeping.
func _run(state: Search, start_world: Vector2, goal_world: Vector2) -> PathData:
	var result := PathData.new()
	var open := MinHeap.new()
	result.start_cell = grid.world_to_cell(start_world)
	result.goal_cell = grid.snap_to_standable(
		grid.world_to_cell(goal_world), tuning.goal_snap_max_cells)
	if not grid.is_passable(result.start_cell) or not grid.is_passable(result.goal_cell):
		return result

	# A start without ground below begins mid-arc, at peak jump value.
	var start_jv := 0
	if not grid.has_ground_below(result.start_cell):
		start_jv = _peak(state)
	var start_key := Vector3i(result.start_cell.x, result.start_cell.y, start_jv)
	state.g[start_key] = 0.0
	_register_cell_node(state, result.start_cell, start_jv)
	open.push(start_key, _heuristic(result.start_cell, result.goal_cell))

	var goal_key := start_key
	var found := false
	var expansions := 0
	while open.size() > 0 and expansions < tuning.max_expansions:
		var current: Vector3i = open.pop()
		if state.closed.has(current):
			continue
		state.closed[current] = true
		expansions += 1
		state.explored[Vector2i(current.x, current.y)] = true
		# Goal test ignores the jump value: any phase may end the route.
		if current.x == result.goal_cell.x and current.y == result.goal_cell.y:
			goal_key = current
			found = true
			break
		_expand(state, open, current, result.goal_cell)

	result.cells_explored = expansions
	if found:
		var states: Array[Vector3i] = []
		var cursor := goal_key
		states.append(cursor)
		while state.parents.has(cursor):
			cursor = state.parents[cursor]
			states.append(cursor)
		states.reverse()
		result.waypoints = WaypointClassifier.classify(states, grid)
		result.found = not result.waypoints.is_empty()
	for cell in state.explored:
		result.explored.append(cell)
	return result


func _expand(state: Search, open: MinHeap, current: Vector3i, goal_cell: Vector2i) -> void:
	var cell := Vector2i(current.x, current.y)
	var jv := current.z
	if jv == WaypointClassifier.CLIMB_JV:
		_expand_climb(state, open, current, goal_cell)
		return
	for direction in DIRECTIONS:
		var next_cell: Vector2i = cell + direction
		if not grid.is_passable(next_cell):
			continue
		if direction == Vector2i.UP and not _can_rise(state, jv):
			continue
		if direction != Vector2i.UP and direction != Vector2i.DOWN and not _allows_sideways(jv):
			continue
		# Airborne states carry their launch cell for the drift envelope below.
		var launch: Vector2i = cell
		if jv != 0:
			launch = state.launch.get(current, cell)
		var next_jv := 0
		if not grid.has_ground_below(next_cell):
			next_jv = _next_jump_value(state, jv, direction)
			if _is_ceiling(next_cell):
				# Ceiling bump forces the descent phase. The +1 makes the value
				# odd (sideways disabled) when walled in on both sides.
				next_jv = maxi(next_jv, _peak(state) + (1 if _is_walled_in(next_cell) else 0))
			var height := launch.y - next_cell.y
			var falling := next_jv > _peak(state) or height <= 0
			# Drift envelope: reject cells outside the physical arc from launch.
			if absi(next_cell.x - launch.x) > state.jump.drift_cells(height, falling):
				continue
		# Base step cost plus an airborne penalty scaled by jump value.
		var step_cost := 1.0 + tuning.air_penalty * float(next_jv)
		_relax(state, open, current, next_cell, next_jv, step_cost, launch, goal_cell)
	_try_ladder_grabs(state, open, current, cell, jv, goal_cell)


## Relaxes one lattice edge from [param from_state] to [param to_cell] at
## [param to_jv], costing [param step_cost]; [param launch] records the
## airborne arc's origin for the drift envelope.
func _relax(
		state: Search,
		open: MinHeap,
		from_state: Vector3i,
		to_cell: Vector2i,
		to_jv: int,
		step_cost: float,
		launch: Vector2i,
		goal_cell: Vector2i,
) -> void:
	if tuning.use_dominance_pruning and to_jv >= 0 and _is_dominated(state, to_cell, to_jv):
		return
	var key := Vector3i(to_cell.x, to_cell.y, to_jv)
	if state.closed.has(key):
		return
	var tentative: float = state.g[from_state] + step_cost
	if state.g.has(key) and tentative >= state.g[key]:
		return
	state.g[key] = tentative
	state.parents[key] = from_state
	state.launch[key] = launch
	_register_cell_node(state, to_cell, to_jv)
	open.push(key, tentative + _heuristic(to_cell, goal_cell))


## Ladder grab edges into the climb phase: in place when the cell is a rung
## (a grounded grab or a mid-air catch), or down through a one-way landing
## onto the rung two cells below (the descend grab).
func _try_ladder_grabs(
		state: Search,
		open: MinHeap,
		current: Vector3i,
		cell: Vector2i,
		jv: int,
		goal_cell: Vector2i,
) -> void:
	if grid.is_ladder(cell):
		_relax(state, open, current, cell, WaypointClassifier.CLIMB_JV, tuning.climb_grab_cost, cell, goal_cell)
		return
	if jv != 0:
		return
	var rung := cell + Vector2i.DOWN + Vector2i.DOWN
	if grid.is_oneway(cell + Vector2i.DOWN) and grid.is_ladder(rung):
		_relax(state, open, current, rung, WaypointClassifier.CLIMB_JV, tuning.climb_grab_cost, cell, goal_cell)


## Climb-phase expansion: vertical chain travel plus every way off the
## ladder — top out onto the first standable surface at or above the chain
## top (one-way landings are risen through), step off onto a crossing beside
## the rung, drop off, or jump off at full power.
func _expand_climb(state: Search, open: MinHeap, current: Vector3i, goal_cell: Vector2i) -> void:
	var cell := Vector2i(current.x, current.y)
	var up := cell + Vector2i.UP
	var down := cell + Vector2i.DOWN
	var step_cost := _climb_step_cost(state)
	if grid.is_ladder(up):
		_relax(state, open, current, up, WaypointClassifier.CLIMB_JV, step_cost, cell, goal_cell)
	if grid.is_ladder(down):
		_relax(state, open, current, down, WaypointClassifier.CLIMB_JV, step_cost, cell, goal_cell)
	if not grid.is_ladder(up):
		var stand := WaypointClassifier.INVALID_CELL
		var standable := false
		if grid.has_standable_top(cell):
			stand = up
			standable = grid.is_passable(stand)
		elif grid.has_standable_top(up) and grid.is_oneway(up):
			stand = up + Vector2i.UP
			standable = grid.is_passable(stand)
		if standable:
			_relax(state, open, current, stand, 0, tuning.climb_grab_cost, cell, goal_cell)
	# Dropping off mid-chain needs shimmy room; the chain's bottom edge and
	# chain breaks drop without one.
	if grid.is_passable(down) and (
			not grid.is_ladder(down)
			or grid.is_passable(cell + Vector2i.LEFT)
			or grid.is_passable(cell + Vector2i.RIGHT)):
		var fall_jv := _next_jump_value(state, 0, Vector2i.DOWN)
		_relax(state, open, current, down, fall_jv, 1.0 + tuning.air_penalty * float(fall_jv), cell, goal_cell)
	if grid.is_passable(up):
		var jump_jv := _next_jump_value(state, 0, Vector2i.UP)
		_relax(state, open, current, up, jump_jv, 1.0 + tuning.air_penalty * float(jump_jv), cell, goal_cell)
	for offset in CLIMB_STEP_OFFS:
		var crossing: Vector2i = cell + offset
		if grid.is_passable(crossing) and grid.has_ground_below(crossing):
			_relax(state, open, current, crossing, 0, tuning.climb_grab_cost, cell, goal_cell)
	if grid.has_ground_below(cell):
		_relax(state, open, current, cell, 0, tuning.climb_grab_cost, cell, goal_cell)


## Cost of one ladder cell in walk-cell units: a cell takes cell_size /
## climb_speed seconds to climb against cell_size / move_speed to walk.
func _climb_step_cost(state: Search) -> float:
	if state.jump.climb_speed <= 0.0:
		return 1.0
	return state.jump.move_speed / state.jump.climb_speed


## Jump-value transition for a move in [param direction].
##
## Parity rule: horizontal steps cost +1 and are allowed only on even values,
## so horizontal and vertical moves alternate and grid steps approximate a
## parabola. Rising uses the next even value (takeoff goes 2 -> 3); falling is
## clamped at least to the peak (descent phase).
func _next_jump_value(state: Search, jv: int, direction: Vector2i) -> int:
	var next_even := jv + 2 if jv % 2 == 0 else jv + 1
	if direction == Vector2i.UP:
		if jv == 0:
			return 3
		return next_even
	if direction == Vector2i.DOWN:
		return maxi(next_even, _peak(state))
	return jv + 1


## Rising is allowed grounded, or mid-arc between takeoff and the peak.
func _can_rise(state: Search, jv: int) -> bool:
	return jv == 0 or (jv >= 3 and jv < _peak(state))


## Only even jump values may step sideways (see [method _next_jump_value]).
func _allows_sideways(jv: int) -> bool:
	return jv % 2 == 0


## Dominance pruning: skip the state when another state already seen at the
## same cell reached it with at most this jump value and can still step
## sideways (strictly more capable).
func _is_dominated(state: Search, cell: Vector2i, jv: int) -> bool:
	var nodes: Array = state.cell_nodes.get(cell, [])
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
func _register_cell_node(state: Search, cell: Vector2i, jv: int) -> void:
	if jv < 0:
		return
	if not state.cell_nodes.has(cell):
		state.cell_nodes[cell] = []
	var nodes: Array = state.cell_nodes[cell]
	if not nodes.has(jv):
		nodes.append(jv)


## Peak jump value: 2 per jump-height cell, so the lattice size tracks
## the profile's reach.
func _peak(state: Search) -> int:
	return 2 * state.max_jump_cells


## True when the cell has a solid ceiling directly above.
func _is_ceiling(cell: Vector2i) -> bool:
	return grid.is_solid(cell + Vector2i.UP)


## True when both horizontal neighbours block movement.
func _is_walled_in(cell: Vector2i) -> bool:
	return not grid.is_passable(cell + Vector2i.LEFT) and not grid.is_passable(cell + Vector2i.RIGHT)


## Weighted Manhattan distance to the goal.
func _heuristic(cell: Vector2i, goal: Vector2i) -> float:
	return float(absi(cell.x - goal.x) + absi(cell.y - goal.y)) * tuning.heuristic_weight
