@tool
class_name PlatformerPathfinder
extends Node2D
## Scene adapter for the pure pathfinding engine.
##
## Owns everything scene-shaped — the [member tilemap] export plus its
## 'navigation' group resolution, Inspector tuning ([PathTuning]), the editor
## preview and the debug overlay — and forwards route and drift queries to a
## [PlatformerNavigator] over the baked [PlatformerGrid]. The jump-lattice
## search and waypoint classification live in the pure modules; this node
## only wires them to the scene.

## TileMapLayer group used to auto-resolve the baked map when no explicit
## [member tilemap] was assigned.
const MAP_GROUP := "navigation"

## TileMapLayer the search grid is baked from.
@export var tilemap: TileMapLayer:
	set(value):
		tilemap = value
		_grid = null
		if _navigator != null:
			_navigator.grid = null
		_run_preview_if_ready()

## Search and steering knobs, shared by reference with the navigator.
@export var tuning: PathTuning = PathTuning.new()

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

# Baked occupancy grid snapshot; rebuilt lazily by _bind_navigator().
var _grid: PlatformerGrid
# Pure search engine over the baked grid; created lazily.
var _navigator: PlatformerNavigator
# Most recent route result; kept for the debug overlay.
var _last_path: PathData
# One-shot flag: the preview run is deferred to the first _process tick
# because exported node refs can be null inside _ready of non-root nodes.
var _preview_pending: bool = true
# Gravity read at startup; jump math never hardcodes it.
var _project_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


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


## Routes between two world points for [param agent]'s physics: forwards to
## the pure [PlatformerNavigator] and keeps the result as the overlay state.
func route(from_world: Vector2, to_world: Vector2, agent: AgentKinematics) -> PathData:
	if tilemap == null:
		push_warning("PlatformerPathfinder: no tilemap assigned")
		_last_path = PathData.new()
		return _last_path
	_bind_navigator()
	_last_path = _navigator.route(from_world, to_world, agent)
	queue_redraw()
	return _last_path


## True when a solid cell blocks the mid-air drift corridor between two world
## points (the follower's steering veto); forwards to the navigator.
func is_drift_blocked(from_world: Vector2, to_world: Vector2) -> bool:
	_bind_navigator()
	return _navigator.is_drift_blocked(from_world, to_world)


## Ensures the navigator holds the current baked grid and tuning; the grid is
## baked lazily and dropped when [member tilemap] is reassigned.
func _bind_navigator() -> void:
	if _navigator == null:
		_navigator = PlatformerNavigator.new()
	if _grid == null and tilemap != null:
		_grid = PlatformerGrid.from_tilemap(tilemap)
	_navigator.grid = _grid
	_navigator.tuning = _active_tuning()


## The tuning queries run with; a cleared [member tuning] export self-heals
## to script defaults.
func _active_tuning() -> PathTuning:
	if tuning == null:
		tuning = PathTuning.new()
	return tuning


## Runs the preview route when enabled and the node is wired up.
func _run_preview_if_ready() -> void:
	if not is_node_ready() or not preview_enabled or tilemap == null:
		return
	route(preview_from, preview_to, AgentKinematics.new(
		preview_jump_velocity, _project_gravity, preview_move_speed))


## Debug overlay: explored-cell dots, the waypoint polyline with per-kind
## colored dots, purple apex dots, and the preview markers.
func _draw() -> void:
	if debug_draw and _grid != null:
		if debug_draw_explored and _last_path != null:
			for cell in _last_path.explored:
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
		_bind_navigator()
		var snapped_world := _navigator.snap_goal_world(preview_to)
		if snapped_world.distance_to(preview_to) > 1.0:
			_draw_marker(to_local(snapped_world), Color(1.0, 1.0, 1.0, 0.9), false, 5.0)


## Whether a preview endpoint lands in a passable cell (after goal snapping).
func _preview_point_valid(world: Vector2, snap_to_ground: bool) -> bool:
	if _grid == null:
		return true
	var cell := _grid.world_to_cell(world)
	if snap_to_ground:
		cell = _grid.snap_to_standable(cell, _active_tuning().goal_snap_max_cells)
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
