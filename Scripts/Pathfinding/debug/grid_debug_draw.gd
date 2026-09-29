## Editor/gameplay overlay visualizing the pathfinding grid.
##
## Bakes a [PlatformerGrid] from the source tilemap and draws per-cell states:
## cell grid lines, solid fills, one-way surfaces (fill plus a top edge line),
## ladder rungs, and standable-cell dots. Updates continuously in the editor so
## tile edits show up immediately; static at runtime.
@tool
class_name GridDebugDraw
extends Node2D

## TileMapLayer to visualize; re-bakes the grid on assignment.
@export var grid_source: TileMapLayer:
	set(value):
		grid_source = value
		_refresh()

@export_group("Toggles")
## Draw the cell grid lines.
@export var show_cell_grid: bool = true
## Fill solid cells.
@export var show_solid: bool = true
## Fill one-way cells (with a top edge line).
@export var show_oneway: bool = true
## Fill ladder rung cells.
@export var show_ladder: bool = true
## Dot every passable cell that has ground below it.
@export var show_standable: bool = true

@export_group("Colors")
## Fill color for solid cells.
@export var solid_color: Color = Color(0.95, 0.3, 0.3, 0.3)
## Fill and edge color for one-way cells.
@export var oneway_color: Color = Color(1.0, 0.62, 0.1, 0.5)
## Fill color for ladder rung cells.
@export var ladder_color: Color = Color(0.2, 0.9, 0.85, 0.45)
## Dot color for standable cells.
@export var standable_color: Color = Color(0.3, 0.95, 0.4, 0.9)
## Line color for the cell grid.
@export var cell_grid_color: Color = Color(1.0, 1.0, 1.0, 0.07)

var _grid: PlatformerGrid


func _ready() -> void:
	# 90 keeps this overlay under PlatformerPathfinder's 95.
	z_index = 90
	call_deferred("_refresh")
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_refresh()


## Re-bakes the whole grid snapshot and queues a redraw. Runs every editor
## frame (see [method _process]) so live tile edits appear immediately; that
## is fine for a debug overlay but not something to copy into gameplay code.
func _refresh() -> void:
	if grid_source == null or grid_source.tile_set == null:
		return
	_grid = PlatformerGrid.from_tilemap(grid_source)
	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return
	var size := Vector2(_grid.cell_size)
	for y in range(_grid.rect.position.y, _grid.rect.end.y):
		for x in range(_grid.rect.position.x, _grid.rect.end.x):
			var cell := Vector2i(x, y)
			var top_left := to_local(_grid.cell_to_world(cell)) - size * 0.5
			var rect := Rect2(top_left, size)
			if show_cell_grid:
				draw_rect(rect, cell_grid_color, false, 1.0)
			var state := _grid.get_state(cell)
			if state == PlatformerGrid.CellState.SOLID and show_solid:
				draw_rect(rect, solid_color, true)
			elif state == PlatformerGrid.CellState.ONEWAY and show_oneway:
				draw_rect(rect, oneway_color, true)
				draw_line(top_left, top_left + Vector2(size.x, 0.0), oneway_color, 2.0)
			if show_ladder and _grid.is_ladder(cell):
				draw_rect(rect, ladder_color, true)
			if show_standable and _grid.is_passable(cell) and _grid.has_ground_below(cell):
				# Dot sits slightly below the cell center for readability.
				draw_circle(top_left + size * 0.5 + Vector2(0.0, size.y * 0.3), 2.5, standable_color)
