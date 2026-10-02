extends Area2D
## The run's spawn point and the way back into the warren.
##
## The scavenge spawns the player inside this zone, so a first entry must
## not count: the zone arms only once it has been left (or was never
## entered), and a walk-in while armed and the player is alive reports
## occupancy to the [code]GameFlow[/code] autoload — the HUD shows the
## return confirmation and its Confirm button ends the run (the [Loot]
## pattern: the entity reports, the autoload owns state, the UI
## listens). A dead player cannot report an entry: death is terminal and
## must route to the title, not the colony. The placeholder marker child
## makes the exit visible until real art exists.

## Whether walk-in is live: set once the spawn overlap has been cleared.
var _armed: bool = false
## Physics frames seen; the area's overlap list is empty before its first
## flush, so the empty-check below must not arm on frame one.
var _frames: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames > 1 and get_overlapping_bodies().is_empty():
		_arm()


func _on_body_exited(body: Node2D) -> void:
	_arm()
	if body is Player:
		GameFlow.set_in_exit_zone(false)


func _on_body_entered(body: Node2D) -> void:
	if not _armed or not GameFlow.player_alive:
		return
	if body is Player:
		GameFlow.set_in_exit_zone(true)


func _arm() -> void:
	_armed = true
	set_physics_process(false)
