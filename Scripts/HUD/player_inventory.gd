@icon("res://addons/at-icons/control/backpack.svg")
class_name PlayerInventory
extends NinePatchRect
## Player-side haul strip: carried items and total weight readout.
##
## Renders the [Loot] autoload's haul and stays visible while playing;
## clicks transfer items back to the session chest.

## Grid holding the carried item slots.
@export var grid: GridContainer
## Label showing the total carried weight.
@export var weight_label: Label
## Slot scene spawned per carried item.
@export var item_scene: PackedScene


## Rebuilds the slots and the weight readout from the haul.
func refresh() -> void:
	_rebuild()
	if weight_label != null:
		weight_label.text = "%.1f" % Loot.haul_weight()


func _rebuild() -> void:
	if grid == null:
		return
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	if item_scene == null:
		return
	for item: Item in Loot.haul:
		var slot := item_scene.instantiate() as InventoryItemView
		if slot == null:
			continue
		grid.add_child(slot)
		slot.bind(item, true)
		slot.pressed.connect(_on_slot_pressed.bind(item))
		slot.shift_pressed.connect(_on_shift_pressed)


func _on_slot_pressed(item: Item) -> void:
	Loot.transfer_to_chest(item)


func _on_shift_pressed() -> void:
	Loot.transfer_all_to_chest(Loot.session)
