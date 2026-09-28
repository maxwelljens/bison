@icon("res://addons/at-icons/control/tag.svg")
class_name InventoryTooltip
extends NinePatchRect
## Hover card describing the item under the cursor.
##
## Replaces the engine tooltip: a polling inventory panel calls
## [method show_item] every frame while a revealed slot is hovered and
## [method hide_for] when its hover ends or its grid rebuilds. The
## card remembers which panel showed it, so two panels polling the
## same shared card cannot fight over it: [method hide_for] only acts
## for the owner. The card follows the cursor with
## [member follow_offset] and clamps itself into the viewport so it
## never leaves the screen. Its whole subtree ignores the mouse so it
## can never eat the hover or the clicks it is drawn on top of.

## Line drawn as the item's name.
@export var title: Label
## Rich body drawn under the title.
@export var body: RichTextLabel

## Cursor offset the card's top-left sits at, in px.
@export var follow_offset: Vector2 = Vector2(16.0, 16.0)

# Item currently drawn by the card, so the polling panels can call
# [method show_item] every frame without rebuilding the body text.
var _shown: Item = null
# The panel that last showed the card; [method hide_for] only acts for
# it, so two panels polling the shared card cannot fight over it.
var _panel: Control


func _ready() -> void:
	hide_tip()


func _process(_delta: float) -> void:
	if not visible:
		return
	_follow_mouse()


## Shows the card for [param item], owned by [param panel]: the
## translated name, the optional description line and a weight line.
## Null hides the card. A same-item call while visible is a no-op, so
## the polling panels can call this every frame without rebuilding the
## body text.
func show_item(item: Item, panel: Control) -> void:
	if item == null:
		hide_for(panel)
		return
	if item == _shown and visible:
		return
	_panel = panel
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


## Force-hides the card and forgets its owner. HUD lifecycle code
## calls this directly; polling panels go through [method hide_for].
func hide_tip() -> void:
	visible = false
	_shown = null
	_panel = null


## Hides the card only when [param panel] is the one that showed it;
## a foreign panel's call is a no-op. This is the ownership rule that
## keeps two polling panels from hiding each other's hover.
func hide_for(panel: Control) -> void:
	if panel != _panel:
		return
	hide_tip()


## True when the cursor rests inside [param slot]'s rectangle. The
## rect-in-local-space form is immune to canvas/layer transform quirks
## (unlike get_global_rect + get_global_mouse_position).
static func hovered_slot(slot: Control) -> bool:
	return Rect2(Vector2.ZERO, slot.size).has_point(
			slot.get_local_mouse_position())


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
