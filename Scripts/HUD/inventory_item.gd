class_name InventoryItemView
extends PanelContainer
## One slot in an inventory grid: icon when revealed, fill bar while
## the item is still buffering in.
##
## Slots only accept clicks once revealed; left-click transfers the
## item, shift-click transfers the whole side (handled by the owner).
## The tooltip keeps the raw Locale key so Godot's automatic
## translation resolves it.

## Fired when a revealed slot is left-clicked.
signal pressed
## Fired when a revealed slot is shift-clicked.
signal shift_pressed

## Fill bar shown while the item buffers in.
@export var progress: ProgressBar
## Item icon shown once revealed.
@export var icon: TextureRect

## The bound item, if any.
var item: Item = null
## Whether the item is revealed (takeable) or still buffering.
var revealed: bool = false


## Binds the slot to an item and a reveal state.
func bind(next_item: Item, is_revealed: bool) -> void:
	item = next_item
	revealed = is_revealed
	tooltip_text = next_item.name_key if is_revealed and next_item != null else ""
	if progress != null:
		progress.visible = not is_revealed
		progress.value = 0.0
	if icon != null:
		icon.visible = is_revealed
		icon.texture = next_item.texture if next_item != null else null


## Sets the buffering fill, 0..1.
func set_fill(value: float) -> void:
	if progress != null:
		progress.value = value


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT \
			or not mouse.pressed:
		return
	if not revealed:
		return
	if mouse.shift_pressed:
		shift_pressed.emit()
	else:
		pressed.emit()
