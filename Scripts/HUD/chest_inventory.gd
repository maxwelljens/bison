@icon("res://addons/at-icons/control/chest.svg")
class_name ChestInventory
extends NinePatchRect
## Chest-side loot panel: renders the session chest's contents.
##
## Slots are spawned from [member item_scene] into [member grid] and
## rebuilt on every chest content change; the fill of the active
## buffering item is pushed live from
## [signal Chest.reveal_progress_changed].

## Grid holding the item slots.
@export var grid: GridContainer
## Slot scene spawned per chest item.
@export var item_scene: PackedScene

# The chest currently displayed.
var _chest: Chest = null
var _slots: Array[InventoryItemView] = []
# Slot whose reveal bar is filling, if any.
var _head_slot: InventoryItemView = null


## Shows the chest's contents; null clears the panel.
func bind(chest: Chest) -> void:
	if _chest != null:
		if _chest.contents_changed.is_connected(_rebuild):
			_chest.contents_changed.disconnect(_rebuild)
		if _chest.reveal_progress_changed.is_connected(_on_reveal_progress):
			_chest.reveal_progress_changed.disconnect(_on_reveal_progress)
	_chest = chest
	if _chest != null:
		_chest.contents_changed.connect(_rebuild)
		_chest.reveal_progress_changed.connect(_on_reveal_progress)
	_rebuild()


func _rebuild() -> void:
	_slots.clear()
	_head_slot = null
	if grid == null:
		return
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	if _chest == null or item_scene == null:
		return
	for item: Item in _chest.revealed_items():
		_add_slot(item, true)
	for item: Item in _chest.pending_items():
		var slot := _add_slot(item, false)
		if _head_slot == null:
			_head_slot = slot
	if _head_slot != null:
		_head_slot.set_fill(_chest.slot_progress())


func _add_slot(item: Item, revealed: bool) -> InventoryItemView:
	var slot := item_scene.instantiate() as InventoryItemView
	if slot == null:
		return null
	grid.add_child(slot)
	slot.bind(item, revealed)
	slot.pressed.connect(_on_slot_pressed.bind(item))
	slot.shift_pressed.connect(_on_shift_pressed)
	_slots.append(slot)
	return slot


func _on_slot_pressed(item: Item) -> void:
	Loot.transfer_to_player(item)


func _on_shift_pressed() -> void:
	if _chest != null:
		Loot.transfer_all_to_player(_chest)


func _on_reveal_progress(value: float) -> void:
	if _head_slot != null:
		_head_slot.set_fill(value)
