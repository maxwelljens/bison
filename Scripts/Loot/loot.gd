extends Node
## Loot session and haul state shared by chests and the HUD.
##
## Chests report their interaction here and the HUD listens here, so
## entities and UI never reference each other (no node lookups). The
## carried haul lives on this singleton so it survives scene changes;
## the warren settlement phase will bank it there later. No
## [code]class_name[/code]: the autoload global [code]Loot[/code] is the
## access point (a class of the same name would hide the singleton).

## Fired when a chest screen becomes active (player interacted in range).
signal session_opened(chest: Chest)
## Fired when the active session ends (player left the trigger).
signal session_closed
## Fired whenever the carried item list changes.
signal haul_changed

## Items currently carried by the player, in pick-up order.
var haul: Array[Item] = []
## The chest whose screen is currently shown, if any.
var session: Chest = null


## Starts (or re-presents) the screen for [param chest]; no-op when it
## already owns the session.
func open_session(chest: Chest) -> void:
	if session == chest:
		return
	session = chest
	session_opened.emit(chest)


## Ends the session. Passing the closing chest guards against a stale
## close from a chest that no longer owns the screen; null forces close.
func close_session(chest: Chest = null) -> void:
	if session == null:
		return
	if chest != null and session != chest:
		return
	session = null
	session_closed.emit()


## Moves one revealed item from the session chest to the haul.
func transfer_to_player(item: Item) -> void:
	if session == null:
		return
	if not session.take_item(item):
		return
	haul.append(item)
	haul_changed.emit()


## Moves one carried item back into the session chest.
func transfer_to_chest(item: Item) -> void:
	if session == null:
		return
	var index := haul.find(item)
	if index == -1:
		return
	haul.remove_at(index)
	session.return_item(item)
	haul_changed.emit()


## Moves every revealed item of [param chest] to the haul.
func transfer_all_to_player(chest: Chest) -> void:
	if chest == null or chest != session:
		return
	var moved := false
	for item: Item in chest.revealed_items():
		if chest.take_item(item):
			haul.append(item)
			moved = true
	if moved:
		haul_changed.emit()


## Moves the whole haul back into the session chest.
func transfer_all_to_chest(chest: Chest) -> void:
	if chest == null or chest != session or haul.is_empty():
		return
	for item: Item in haul:
		chest.return_item(item)
	haul.clear()
	haul_changed.emit()


## Total carried weight, in item weight units.
func haul_weight() -> float:
	var total := 0.0
	for item: Item in haul:
		total += item.weight
	return total
