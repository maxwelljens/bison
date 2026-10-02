@icon("res://addons/at-icons/control/window.svg")
class_name Hud
extends Control
## Loot screen root: shows the chest panel during a session and keeps
## the player haul strip updated. Also hosts the return-to-warren
## confirmation shown while the player stands in the armed exit zone.
##
## All state arrives from the [Loot] and [code]GameFlow[/code]
## autoloads; this root only routes it to the panels. Wiring happens in
## a one-shot [method _process] because exported node references may
## still be null inside [method Node._ready] of instanced scenes.

## Chest-side loot panel, hidden outside a session.
@export var chest_inventory: ChestInventory
## Player-side haul strip, always visible.
@export var player_inventory: PlayerInventory
## Shared hover card for both panels.
@export var tooltip: InventoryTooltip
## HUD clock label fed by the [code]GameClock[/code] autoload.
@export var clock: Label
## Return-to-warren prompt, shown while in the armed exit zone.
@export var return_confirmation: NinePatchRect
## Confirm: ends the run through GameFlow (banks the haul, advances the
## day); no-op while the player is dead.
@export var confirm_button: Button
## Deny: hides the prompt until the zone is left and re-entered.
@export var deny_button: Button

# One-shot init gate for the first _process tick.
var _initialized: bool = false
# Set by Deny: suppresses the prompt until the zone reports an exit.
var _return_denied: bool = false


func _process(_delta: float) -> void:
	if not _initialized:
		_initialized = true
		_init_hud()
	_update_clock()


## Push the current clock text only when it changes (avoids layout churn).
func _update_clock() -> void:
	if clock == null:
		return
	var next_text: String = GameClock.clock_text()
	if clock.text != next_text:
		clock.text = next_text


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
	GameFlow.exit_zone_changed.connect(_on_exit_zone_changed)
	if chest_inventory != null:
		chest_inventory.visible = false
	if player_inventory != null:
		player_inventory.refresh()
	if tooltip != null:
		tooltip.hide_tip()
	if return_confirmation != null:
		return_confirmation.visible = false
	if confirm_button != null:
		confirm_button.pressed.connect(_on_confirm_pressed)
	if deny_button != null:
		deny_button.pressed.connect(_on_deny_pressed)


func _on_exit_zone_changed(inside: bool) -> void:
	if not inside:
		_return_denied = false
	_update_return_confirmation()


func _on_confirm_pressed() -> void:
	GameFlow.finish_scavenge()


func _on_deny_pressed() -> void:
	_return_denied = true
	_update_return_confirmation()


func _update_return_confirmation() -> void:
	if return_confirmation == null:
		return
	return_confirmation.visible = GameFlow.in_exit_zone and not _return_denied
