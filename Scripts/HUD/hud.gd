@icon("res://addons/at-icons/control/window.svg")
class_name Hud
extends Control
## Loot screen root: shows the chest panel during a session and keeps
## the player haul strip updated.
##
## All state arrives from the [Loot] autoload; this root only routes it
## to the two panels. Wiring happens in a one-shot [method _process]
## because exported node references may still be null inside
## [method Node._ready] of instanced scenes.

## Chest-side loot panel, hidden outside a session.
@export var chest_inventory: ChestInventory
## Player-side haul strip, always visible.
@export var player_inventory: PlayerInventory
## Shared hover card for both panels.
@export var tooltip: InventoryTooltip

# One-shot init gate for the first _process tick.
var _initialized: bool = false


func _process(_delta: float) -> void:
	if _initialized:
		return
	_initialized = true
	set_process(false)
	_init_hud()


func _on_session_opened(chest: Chest) -> void:
	if chest_inventory == null:
		return
	chest_inventory.bind(chest)
	chest_inventory.visible = true


func _on_session_closed() -> void:
	if tooltip != null:
		tooltip.hide_tip()
	if chest_inventory == null:
		return
	chest_inventory.visible = false
	chest_inventory.bind(null)


func _on_haul_changed() -> void:
	if player_inventory != null:
		player_inventory.refresh()


func _init_hud() -> void:
	Loot.session_opened.connect(_on_session_opened)
	Loot.session_closed.connect(_on_session_closed)
	Loot.haul_changed.connect(_on_haul_changed)
	if chest_inventory != null:
		chest_inventory.visible = false
	if player_inventory != null:
		player_inventory.refresh()
	if tooltip != null:
		tooltip.hide_tip()
