class_name WaypointClassifier
extends RefCounted
## Turns a search state chain into typed [PathWaypoint]s.
##
## The chain format is the seam contract with the navigator's search: one
## [Vector3i] per step, (cell.x, cell.y, jump value), where 0 is grounded,
## positive values are the airborne phase and [constant CLIMB_JV] is ladder
## travel. Grounded runs (jv == 0), airborne runs and climb runs are
## classified separately, and the route always ends at the goal cell.
## Pure over (chain, grid): replayable from hand-written chains in tests.

## Jump value marking ladder climb states in the chain.
const CLIMB_JV := -1
## "No cell" sentinel for optional cell values.
const INVALID_CELL := Vector2i(-1, -1)


## Classifies a full state chain into waypoints; the route always ends at the
## chain's final cell.
static func classify(states: Array[Vector3i], grid: PlatformerGrid) -> Array[PathWaypoint]:
	var waypoints: Array[PathWaypoint] = []
	var index := 0
	while index < states.size():
		if states[index].z == 0:
			var from_climb := index > 0 and states[index - 1].z == CLIMB_JV
			index = _classify_ground_run(states, index, waypoints, grid, from_climb)
		elif states[index].z == CLIMB_JV:
			index = _classify_climb_run(states, index, waypoints, grid)
		else:
			index = _classify_air_run(states, index, waypoints, grid)
	var goal_cell := Vector2i(states[states.size() - 1].x, states[states.size() - 1].y)
	if waypoints.is_empty() or waypoints[waypoints.size() - 1].cell != goal_cell:
		waypoints.append(_make_waypoint(PathWaypoint.Kind.WALK, goal_cell, grid))
	return waypoints


## Ground run: WALK at the start (the ladder exit cell when leaving a
## climb) and at direction changes, JUMP+LAND pairs for upward steps,
## DROP_THROUGH for steps onto one-way tops; closes with WALK at the run end.
## Returns the state index after the run.
static func _classify_ground_run(
		states: Array[Vector3i],
		start: int,
		out: Array[PathWaypoint],
		grid: PlatformerGrid,
		from_climb: bool = false,
) -> int:
	var index := start
	var last_direction := Vector2i.ZERO
	# Walk-run compression would otherwise swallow the exit cell, and the
	# follower needs it to pick the right way off the ladder.
	if from_climb:
		out.append(_make_waypoint(PathWaypoint.Kind.WALK, Vector2i(states[start].x, states[start].y), grid))
	while index < states.size() and states[index].z == 0:
		var cell := Vector2i(states[index].x, states[index].y)
		if index + 1 < states.size() and states[index + 1].z == 0:
			var next := Vector2i(states[index + 1].x, states[index + 1].y)
			var step := next - cell
			if step.y < 0:
				out.append(_make_waypoint(PathWaypoint.Kind.JUMP, cell, grid, next))
				out.append(_make_waypoint(PathWaypoint.Kind.LAND, next, grid))
				last_direction = Vector2i.ZERO
			elif step.y > 0 and grid.is_oneway(next):
				out.append(_make_waypoint(PathWaypoint.Kind.DROP_THROUGH, cell, grid))
				last_direction = Vector2i.ZERO
			else:
				var direction := Vector2i(signi(step.x), signi(step.y))
				if last_direction != Vector2i.ZERO and direction != last_direction:
					out.append(_make_waypoint(PathWaypoint.Kind.WALK, cell, grid))
				last_direction = direction
		index += 1
	var run_end := Vector2i(states[index - 1].x, states[index - 1].y)
	if out.is_empty() or out[out.size() - 1].cell != run_end:
		out.append(_make_waypoint(PathWaypoint.Kind.WALK, run_end, grid))
	return index


## Climb run: CLIMB at the run's first cell (the grab), at direction
## reversals and at the run end (the exit cell). Returns the state index
## after the run.
static func _classify_climb_run(states: Array[Vector3i], start: int, out: Array[PathWaypoint], grid: PlatformerGrid) -> int:
	var first := Vector2i(states[start].x, states[start].y)
	out.append(_make_waypoint(PathWaypoint.Kind.CLIMB, first, grid))
	var index := start
	var last_direction := 0
	while index < states.size() and states[index].z == CLIMB_JV:
		var cell := Vector2i(states[index].x, states[index].y)
		if index + 1 < states.size() and states[index + 1].z == CLIMB_JV:
			var next := Vector2i(states[index + 1].x, states[index + 1].y)
			var direction := signi(next.y - cell.y)
			if last_direction != 0 and direction != last_direction:
				out.append(_make_waypoint(PathWaypoint.Kind.CLIMB, cell, grid))
			last_direction = direction
		index += 1
	var climb_end := Vector2i(states[index - 1].x, states[index - 1].y)
	if out[out.size() - 1].cell != climb_end:
		out.append(_make_waypoint(PathWaypoint.Kind.CLIMB, climb_end, grid))
	return index


## Airborne run: the apex is the highest cell (including the landing cell).
## The first step off the launch state names the action: stepping up is a
## powered takeoff (JUMP at the launch cell), while stepping down out of a
## grounded run drops through the one-way platform below the launch cell
## (DROP_THROUGH, whose first cell is that platform's tile). A run at the
## very start of the state chain began mid-air instead, so it is never a
## takeoff; anything else (a ledge step-off, a ladder drop off) is FALL.
## Jump values cannot tell takeoffs apart from drops: a fall starts at the
## lattice peak, which overlaps the takeoff range for taller jump profiles.
## Always closes with LAND unless a climb run (a catch) follows. Returns the
## state index after the run.
static func _classify_air_run(
		states: Array[Vector3i],
		start: int,
		out: Array[PathWaypoint],
		grid: PlatformerGrid,
) -> int:
	var first := Vector2i(states[start].x, states[start].y)
	var launch := first
	if start > 0:
		launch = Vector2i(states[start - 1].x, states[start - 1].y)
	var apex := first
	var through_oneway := grid.is_oneway(first)
	var index := start
	while index < states.size() and states[index].z > 0:
		var cell := Vector2i(states[index].x, states[index].y)
		if cell.y < apex.y:
			apex = cell
		if grid.is_oneway(cell):
			through_oneway = true
		index += 1
	var land := Vector2i(states[index - 1].x, states[index - 1].y)
	if index < states.size() and states[index].z == 0:
		land = Vector2i(states[index].x, states[index].y)
	if land.y < apex.y:
		apex = land
	if start > 0 and first == launch + Vector2i.UP:
		out.append(_make_waypoint(PathWaypoint.Kind.JUMP, launch, grid, apex))
	elif start > 0 and states[start - 1].z == 0 and first == launch + Vector2i.DOWN \
			and grid.is_oneway(first):
		var drop := _make_waypoint(PathWaypoint.Kind.DROP_THROUGH, launch, grid)
		drop.through_oneway = true
		out.append(drop)
	else:
		# A one-cell air run at the very start, caught at its own cell, is
		# the mid-air start artifact (the agent is already on the chain);
		# the CLIMB waypoint that follows is the real instruction.
		var caught_here := (
			start == 0
			and index == start + 1
			and index < states.size()
			and states[index].z == CLIMB_JV
		)
		if not caught_here:
			var fall := _make_waypoint(PathWaypoint.Kind.FALL, launch, grid)
			fall.through_oneway = through_oneway
			out.append(fall)
	# A climb run right after the air run is a mid-air catch; the CLIMB
	# waypoint at the catch cell replaces the landing marker.
	if index >= states.size() or states[index].z != CLIMB_JV:
		out.append(_make_waypoint(PathWaypoint.Kind.LAND, land, grid))
	return index


## Builds a waypoint with world coordinates; [param apex] is optional and
## only set for jumps.
static func _make_waypoint(
		kind: PathWaypoint.Kind,
		cell: Vector2i,
		grid: PlatformerGrid,
		apex: Vector2i = INVALID_CELL,
) -> PathWaypoint:
	var waypoint := PathWaypoint.new()
	waypoint.kind = kind
	waypoint.cell = cell
	waypoint.world = grid.cell_to_world(cell)
	if apex != INVALID_CELL:
		waypoint.apex_cell = apex
		waypoint.apex_world = grid.cell_to_world(apex)
	return waypoint
