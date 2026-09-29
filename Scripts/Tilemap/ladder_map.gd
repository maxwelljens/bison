class_name LadderMap
extends RefCounted
## Ladder queries over a tilemap's ladder custom-data flag.
##
## Ladders are ordinary tiles carrying two things: a top-half one-way
## polygon (so every rung is walkable from above and passable from below)
## and a [code]ladder[/code] bool custom data marking the cell climbable.
## This is the single source of ladder truth for the player, the grid
## bake and the bots; every query degrades to "no ladders" when the
## tilemap or its custom data layer is missing.

## Name of the bool custom data layer that marks ladder tiles.
const CUSTOM_DATA_NAME := "ladder"


## Whether the cell holds a ladder tile.
static func is_ladder_cell(tilemap: TileMapLayer, cell: Vector2i) -> bool:
	if tilemap == null or tilemap.tile_set == null:
		return false
	if not _has_ladder_layer(tilemap.tile_set):
		return false
	var tile_data := tilemap.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data(CUSTOM_DATA_NAME) == true


## Whether the world position lies in a ladder tile.
static func is_ladder_world(tilemap: TileMapLayer, world: Vector2) -> bool:
	if tilemap == null:
		return false
	return is_ladder_cell(tilemap, tilemap.local_to_map(tilemap.to_local(world)))


## Topmost cell of the contiguous ladder run containing [param cell].
## Returns [param cell] unchanged when it is not a ladder.
static func run_top_cell(tilemap: TileMapLayer, cell: Vector2i) -> Vector2i:
	var top := cell
	while is_ladder_cell(tilemap, top + Vector2i.UP):
		top += Vector2i.UP
	return top


## Bottommost cell of the contiguous ladder run containing [param cell].
## Returns [param cell] unchanged when it is not a ladder.
static func run_bottom_cell(tilemap: TileMapLayer, cell: Vector2i) -> Vector2i:
	var bottom := cell
	while is_ladder_cell(tilemap, bottom + Vector2i.DOWN):
		bottom += Vector2i.DOWN
	return bottom


## World-space y of a cell's top edge (transform-aware).
static func cell_top_y(tilemap: TileMapLayer, cell: Vector2i) -> float:
	var half := tilemap.tile_set.tile_size.y * 0.5
	return tilemap.to_global(tilemap.map_to_local(cell) - Vector2(0, half)).y


## World-space y of a cell's bottom edge (transform-aware).
static func cell_bottom_y(tilemap: TileMapLayer, cell: Vector2i) -> float:
	var half := tilemap.tile_set.tile_size.y * 0.5
	return tilemap.to_global(tilemap.map_to_local(cell) + Vector2(0, half)).y


## Whether the cell holds a tile whose top face can stand a body: any
## collision polygon (solid box or one-way strip) qualifies.
static func has_standable_top(tilemap: TileMapLayer, cell: Vector2i) -> bool:
	if tilemap == null or tilemap.tile_set == null:
		return false
	var tile_data := tilemap.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	for layer in range(tilemap.tile_set.get_physics_layers_count()):
		if tile_data.get_collision_polygons_count(layer) > 0:
			return true
	return false


## Whether the tileset declares the ladder custom data layer at all;
## missing layers must not error when foreign tilesets are queried.
static func _has_ladder_layer(tile_set: TileSet) -> bool:
	for index in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(index) == CUSTOM_DATA_NAME:
			return true
	return false
