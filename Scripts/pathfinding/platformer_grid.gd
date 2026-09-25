class_name PlatformerGrid
extends RefCounted

enum CellState { EMPTY, SOLID, ONEWAY }

const PHYSICS_LAYER := 0

var source: TileMapLayer
var rect: Rect2i = Rect2i()
var cell_size: Vector2i = Vector2i(16, 16)

var _states: PackedByteArray = PackedByteArray()


static func from_tilemap(tilemap: TileMapLayer) -> PlatformerGrid:
	var grid := PlatformerGrid.new()
	grid.source = tilemap
	if tilemap.tile_set != null:
		grid.cell_size = tilemap.tile_set.tile_size
	grid.rect = tilemap.get_used_rect()
	grid._states.resize(grid.rect.size.x * grid.rect.size.y)
	for y in range(grid.rect.position.y, grid.rect.end.y):
		for x in range(grid.rect.position.x, grid.rect.end.x):
			var cell := Vector2i(x, y)
			grid._states[grid._index(cell)] = grid._read_tile_state(cell)
	return grid


func in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= rect.position.x
		and cell.y >= rect.position.y
		and cell.x < rect.end.x
		and cell.y < rect.end.y
	)


func get_state(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return CellState.SOLID
	return _states[_index(cell)]


func is_solid(cell: Vector2i) -> bool:
	return get_state(cell) == CellState.SOLID


func is_oneway(cell: Vector2i) -> bool:
	return get_state(cell) == CellState.ONEWAY


func is_passable(cell: Vector2i) -> bool:
	return get_state(cell) != CellState.SOLID


func has_ground_below(cell: Vector2i) -> bool:
	var below := cell + Vector2i.DOWN
	return is_solid(below) or is_oneway(below)


func world_to_cell(world: Vector2) -> Vector2i:
	return source.local_to_map(source.to_local(world))


func cell_to_world(cell: Vector2i) -> Vector2:
	return source.to_global(source.map_to_local(cell))


func _index(cell: Vector2i) -> int:
	return (cell.y - rect.position.y) * rect.size.x + (cell.x - rect.position.x)


func _read_tile_state(cell: Vector2i) -> int:
	var tile_data := source.get_cell_tile_data(cell)
	if tile_data == null:
		return CellState.EMPTY
	var polygon_count := tile_data.get_collision_polygons_count(PHYSICS_LAYER)
	if polygon_count == 0:
		return CellState.EMPTY
	for polygon_index in range(polygon_count):
		if not tile_data.is_collision_polygon_one_way(PHYSICS_LAYER, polygon_index):
			return CellState.SOLID
	return CellState.ONEWAY
