extends Node
## Meta-flow state and scene navigation for the title → colony →
## scavenge loop.
##
## Owns what must survive scene changes: the run day, the colony
## stockpile and the "haul just banked" flag the colony report shows.
## Screens call the transition methods; nothing else references scenes.
## No [code]class_name[/code]: the autoload global [code]GameFlow[/code]
## is the access point (a class of the same name would hide it).

## Scenes the flow moves between.
const TITLE_SCENE: String = "res://Levels/title_screen.tscn"
const COLONY_SCENE: String = "res://Levels/colony_screen.tscn"
const RUN_SCENE: String = "res://Levels/test_level.tscn"

## Fired when the player enters (true) or leaves (false) the armed
## warren exit — the HUD listens to show/hide the return confirmation.
signal exit_zone_changed(inside: bool)

## Day the colony screen reports and the upcoming scavenge runs under
## (1 = the first expedition).
var day: int = 1
## Banked totals keyed by [member Item.id]; empty until the first return.
var stockpile: Dictionary[StringName, int] = {}
## Whether the next colony visit should report a fresh banking.
var haul_banked: bool = false
## Whether the player currently stands in the armed warren exit.
var in_exit_zone: bool = false

# Guards a double-confirm from banking twice before the deferred scene
# change lands; reset whenever a run (or fresh run) starts.
var _transitioning: bool = false


## Title "Start": begins a fresh run — day 1, empty stockpile, empty haul.
func new_run() -> void:
	day = 1
	stockpile.clear()
	haul_banked = false
	_transitioning = false
	Loot.close_session()
	Loot.haul.clear()
	Loot.haul_changed.emit()


## Zone occupancy report (the [Loot] pattern: the entity reports here,
## the HUD listens here; deduplicated on the stored value).
func set_in_exit_zone(inside: bool) -> void:
	if in_exit_zone == inside:
		return
	in_exit_zone = inside
	exit_zone_changed.emit(inside)


## Enter the colony hub.
func go_to_colony() -> void:
	_go_to(COLONY_SCENE)


## Back to the title screen (Quit to Title; death routes here too).
func go_to_title() -> void:
	_go_to(TITLE_SCENE)


## Colony "Set Out": loads the scavenge level, whose root starts the day
## clock on load.
func set_out() -> void:
	_transitioning = false
	_go_to(RUN_SCENE)


## Confirm pressed in the exit zone: bank the haul into the stockpile,
## settle the clock, advance the day and report the banking on the
## colony screen. Ignored if a transition is already in flight.
func finish_scavenge() -> void:
	if _transitioning:
		return
	_transitioning = true
	set_in_exit_zone(false)
	Loot.close_session()
	for item: Item in Loot.haul:
		stockpile[item.id] = int(stockpile.get(item.id, 0)) + 1
	Loot.haul.clear()
	Loot.haul_changed.emit()
	GameClock.stop_clock()
	haul_banked = true
	day += 1
	go_to_colony()


## Death: freeze the run and route to the title. The stockpile and day
## are wiped by the next [method new_run], so this only stops and routes.
func end_run() -> void:
	GameClock.stop_clock()
	Loot.close_session()
	set_in_exit_zone(false)
	go_to_title()


## Deferred scene change: callers include physics callbacks (the exit
## zone's body_entered), where immediate changes are forbidden — the
## current scene's collision objects would be removed mid-step.
func _go_to(scene_path: String) -> void:
	get_tree().call_deferred(&"change_scene_to_file", scene_path)
