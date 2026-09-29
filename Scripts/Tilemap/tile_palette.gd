@tool
@icon("res://addons/at-icons/node2d/palette.svg")
class_name TilePalette
extends Node2D
## Bakes per-tile colours from TileSet custom data into tile rendering.
##
## The TileSet's custom data layer named [member color_layer] holds one Color
## per tile (authored in the TileSet editor's Custom Data section). Baking
## copies that colour onto the tile's [member TileData.modulate], which the
## engine multiplies into the tile's drawing — no shader, no runtime code.
## Custom data stays the source of truth; modulate is derived, so re-bake
## after editing custom data values. Untagged tiles read the layer default
## Color(0, 0, 0, 1); baking resets those to untinted white. Pure black is
## therefore not authorable as a tint.

## Tilemap whose placed tiles get baked.
@export var target: TileMapLayer
## Name of the TileSet custom data layer carrying the colour attribute.
## Resolved by name so layer reordering in the TileSet editor stays safe.
@export var color_layer: String = "color"

## The default value of an unauthored Color custom data entry; treated as
## "untagged" and reset to white on bake.
const UNTAGGED_COLOR := Color(0, 0, 0, 1)

## Toggle in the Inspector to bake. The flag resets itself to false so
## baking only happens on an explicit assignment, never on scene load: the
## tileset is a shared resource and must not be churned automatically.
@export var bake: bool = false:
	set(value):
		if value and target != null and target.tile_set != null:
			_bake()
		bake = false


## Copies [member color_layer]'s colour onto every placed tile's
## [member TileData.modulate]. Each [TileMapLayer] cell read resolves to the
## atlas tile's [TileData] (including any alternative in use), so repeated
## cells of one tile converge idempotently on the same write. Tiles whose
## custom data is untagged have any stale tint cleared instead.
func _bake() -> void:
	var tile_set := target.tile_set
	if tile_set.get_custom_data_layer_by_name(color_layer) == -1:
		push_warning("TilePalette: tileset has no custom data layer '%s'" % color_layer)
		return
	var tinted := 0
	var cleared := 0
	for cell in target.get_used_cells():
		var data := target.get_cell_tile_data(cell)
		if data == null:
			continue
		var color: Variant = data.get_custom_data(color_layer)
		if color is Color and color != UNTAGGED_COLOR:
			data.modulate = color
			tinted += 1
		else:
			data.modulate = Color.WHITE
			cleared += 1
	print("TilePalette: tinted %d tiles, cleared %d (layer '%s')" % [tinted, cleared, color_layer])
