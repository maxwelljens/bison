@icon("res://addons/at-icons/control/tag.svg")
class_name InventoryTooltip
extends NinePatchRect
## Hover card describing the item under the cursor.
##
## Replaces the engine tooltip: the owning inventory panel calls
## [method show_item] when a revealed slot is hovered and
## [method hide_tip] when the hover ends or the grid rebuilds. The card
## follows the cursor with [member follow_offset] and clamps itself
## into the viewport so it never leaves the screen. Its whole subtree
## ignores the mouse so it can never eat the hover or the clicks it is
## drawn on top of.

## Line drawn as the item's name.
@export var title: Label
## Rich body drawn under the title.
@export var body: RichTextLabel

## Cursor offset the card's top-left sits at, in px.
@export var follow_offset: Vector2 = Vector2(16.0, 16.0)

# Item currently drawn by the card, so the polling panels can call
# [method show_item] every frame without rebuilding the body text.
var _shown: Item = null


func _ready() -> void:
	hide_tip()


func _process(_delta: float) -> void:
	if not visible:
		return
	_follow_mouse()


## Shows the card for [param item]: the translated name, the optional
## description line and a weight line. Null hides the card.
func show_item(item: Item) -> void:
	if item == null:
		hide_tip()
		return
	if item == _shown and visible:
		return
	_shown = item
	if title != null:
		title.text = tr(item.name_key)
	if body != null:
		var lines: Array[String] = []
		if not item.description_key.is_empty():
			lines.append(tr(item.description_key))
		lines.append("%s: %.1f" % [tr("LABEL_WEIGHT"), item.weight])
		body.text = "\n".join(lines)
	visible = true
	# Position immediately so the first visible frame is already at
	# the cursor, not at the scene-authored offset.
	_follow_mouse()


## Hides the card; panels call this on unhover, rebuild and close.
func hide_tip() -> void:
	visible = false
	_shown = null


## Places the card at the cursor plus [member follow_offset], clamped
## so its drawn rectangle stays inside the visible rect. The cursor
## is read in canvas space and the clamp runs in window pixels (through
## [method CanvasItem.get_screen_transform]), so a CanvasLayer parent
## and the canvas_items stretch cannot skew the result.
func _follow_mouse() -> void:
	# Canvas/Layer space -> window pixels.
	var to_screen := get_screen_transform() * get_global_transform().affine_inverse()
	var origin: Vector2 = to_screen * (get_global_mouse_position() + follow_offset)
	var extent: Vector2 = size * to_screen.get_scale().abs()
	var visible_rect := get_viewport().get_visible_rect()
	var clamped := Vector2(
		clampf(origin.x, visible_rect.position.x,
			maxf(visible_rect.end.x - extent.x, visible_rect.position.x)),
		clampf(origin.y, visible_rect.position.y,
			maxf(visible_rect.end.y - extent.y, visible_rect.position.y))
	)
	global_position = to_screen.affine_inverse() * clamped
