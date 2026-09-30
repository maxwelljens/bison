class_name PlatformerGrid
extends RefCounted
## Flat occupancy grid baked from a [TileMapLayer] for pathfinding.
##
## Converts tilemap physics into a plain array of cell states the pathfinder
## can query cheaply, plus a per-cell ladder flag from the tileset's ladder
## custom data. One snapshot per bake; re-bake via [method from_tilemap]
## when the tilemap changes.

## What occupies a cell.
enum CellState {
	## No collision geometry; freely enterable.
	EMPTY,
	## Blocking collision; the agent cannot enter.
	SOLID,
	## One-way platform: enterable from above only.
	ONEWAY,
}

## The tilemap this grid was baked from; also the coordinate-space reference
## for [method world_to_cell] and [method cell_to_world].
var source: TileMapLayer
## Baked area in cells (the tilemap's used rect).
var rect: Rect2i = Rect2i()
## Tile size in px, read from the TileSet.
var cell_size: Vector2i = Vector2i(16, 16)

## Row-major cell states over [member rect].
var _states: PackedByteArray = PackedByteArray()
## Row-major ladder flags over [member rect]; 1 marks a climbable rung cell.
var _ladders: PackedByteArray = PackedByteArray()


## Bakes the tilemap's collision into a new grid snapshot.
static func from_tilemap(tilemap: TileMapLayer) -> PlatformerGrid:
	var grid := PlatformerGrid.new()
	grid.source = tilemap
	if tilemap.tile_set != null:
		grid.cell_size = tilemap.tile_set.tile_size
	grid.rect = tilemap.get_used_rect()
	grid._states.resize(grid.rect.size.x * grid.rect.size.y)
	grid._ladders.resize(grid.rect.size.x * grid.rect.size.y)
	for y in range(grid.rect.position.y, grid.rect.end.y):
		for x in range(grid.rect.position.x, grid.rect.end.x):
			var cell := Vector2i(x, y)
			grid._states[grid._index(cell)] = grid._read_tile_state(cell)
			grid._ladders[grid._index(cell)] = 1 if LadderMap.is_ladder_cell(tilemap, cell) else 0
	return grid


## Whether the cell lies inside the baked rect.
func in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= rect.position.x
		and cell.y >= rect.position.y
		and cell.x < rect.end.x
		and cell.y < rect.end.y
	)


## Cell state; out-of-bounds cells read as [constant CellState.SOLID] so the
## baked area acts as world boundary.
func get_state(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return CellState.SOLID
	return _states[_index(cell)]


## True when the cell blocks movement.
func is_solid(cell: Vector2i) -> bool:
	return get_state(cell) == CellState.SOLID


## True when the cell is a one-way platform surface.
func is_oneway(cell: Vector2i) -> bool:
	return get_state(cell) == CellState.ONEWAY


## True when the cell holds a climbable ladder rung (its tile carries the
## ladder custom-data flag). Ladder-ness is orthogonal to collision: a rung
## may hang in open air or double as a one-way surface, so it is tracked as
## a separate bit instead of a [enum CellState].
func is_ladder(cell: Vector2i) -> bool:
	return in_bounds(cell) and _ladders[_index(cell)] == 1


## True when the cell can be entered (empty or one-way).
func is_passable(cell: Vector2i) -> bool:
	return get_state(cell) != CellState.SOLID


## True when the cell below is solid or one-way; one-way tops count as ground
## because the agent can stand on them.
func has_ground_below(cell: Vector2i) -> bool:
	var below := cell + Vector2i.DOWN
	return is_solid(below) or is_oneway(below)


## True when the cell's tile has any collision polygon (solid box or one-way
## strip), i.e. its top face can stand a body. Out-of-bounds cells are false.
## This is [method LadderMap.has_standable_top]'s predicate at grid level, so
## the search never reads the live tilemap mid-query.
func has_standable_top(cell: Vector2i) -> bool:
	return in_bounds(cell) and get_state(cell) != CellState.EMPTY


## Nearest standable cell to snap a goal onto: the input cell itself when
## it can be stood on, otherwise the best candidate within
## [param max_cells] rows below and [param side_cells] columns either side.
## Candidates are scored |dy| · [param vertical_weight] + |dx| (horizontal
## cell = 1), so a weight above 1 prefers a lip at the request's height
## over a floor far below — a goal floating over a gap resolves sideways to
## a landing or stays put, never dives into the chasm. Returns the input
## cell when no candidate exists; callers refuse such goals.
func snap_to_standable(
		cell: Vector2i,
		max_cells: int,
		side_cells: int = 0,
		vertical_weight: float = 1.0,
) -> Vector2i:
	if is_passable(cell) and has_ground_below(cell):
		return cell
	var best := cell
	var best_score := INF
	for dy in range(max_cells + 1):
		for dx in range(-side_cells, side_cells + 1):
			if dx == 0 and dy == 0:
				continue
			var candidate := cell + Vector2i(dx, dy)
			if not is_passable(candidate) or not has_ground_below(candidate):
				continue
			var score := float(absi(dy)) * vertical_weight + float(absi(dx))
			if score < best_score:
				best_score = score
				best = candidate
	return best


## True when a solid cell blocks the column strip between two world points;
## the strip is padded [param top_pad] px above and [param bottom_pad] px
## below to cover the body height around the path line.
func is_strip_blocked(
		from_world: Vector2,
		to_world: Vector2,
		top_pad: float = 3.0,
		bottom_pad: float = 7.0,
) -> bool:
	var top := world_to_cell(Vector2(from_world.x, minf(from_world.y, to_world.y) - top_pad)).y
	var bottom := world_to_cell(Vector2(from_world.x, maxf(from_world.y, to_world.y) + bottom_pad)).y
	var from_column := world_to_cell(from_world).x
	var to_column := world_to_cell(to_world).x
	for x in range(mini(from_column, to_column), maxi(from_column, to_column) + 1):
		for y in range(mini(top, bottom), maxi(top, bottom) + 1):
			if is_solid(Vector2i(x, y)):
				return true
	return false


## World pixel position to grid cell (via the source tilemap's transform).
func world_to_cell(world: Vector2) -> Vector2i:
	return source.local_to_map(source.to_local(world))


## Grid cell center to world pixel position.
func cell_to_world(cell: Vector2i) -> Vector2:
	return source.to_global(source.map_to_local(cell))


## Row-major flattening of a cell within [member rect].
func _index(cell: Vector2i) -> int:
	return (cell.y - rect.position.y) * rect.size.x + (cell.x - rect.position.x)


## Classifies a tile's collision: no polygons is EMPTY; any polygon that is
## not one-way makes the cell SOLID; only when every polygon is one-way is
## the cell ONEWAY. Polygons may sit on any physics layer — one-way
## platforms live on their own layer (collision layer 2) so bodies can
## drop through by masking it — so every layer is scanned.
func _read_tile_state(cell: Vector2i) -> int:
	var tile_data := source.get_cell_tile_data(cell)
	if tile_data == null:
		return CellState.EMPTY
	var layers := source.tile_set.get_physics_layers_count()
	var any_polygon := false
	for layer_index in range(layers):
		var polygon_count := tile_data.get_collision_polygons_count(layer_index)
		for polygon_index in range(polygon_count):
			any_polygon = true
			if not tile_data.is_collision_polygon_one_way(layer_index, polygon_index):
				return CellState.SOLID
	if not any_polygon:
		return CellState.EMPTY
	return CellState.ONEWAY
