extends Node2D
## Test-level root: owns the run's daytime clock lifecycle.
##
## The [code]GameClock[/code] autoload is global, so the level that owns a
## run starts its day on load and reacts to the dusk boundary. On reload
## the [MusicCue] on this scene re-announces the daytime set before this
## runs - that self-heal is expected.

## Score to play once the day ends. Unassigned = keep the current music:
## [code]Music.play_soundtrack(null)[/code] would fade to silence, so a
## null slot is deliberately a no-op here.
@export var dusk_soundtrack: Soundtrack


func _ready() -> void:
	GameClock.dusk_reached.connect(_on_dusk_reached)
	GameClock.start_day()


func _on_dusk_reached() -> void:
	if dusk_soundtrack == null:
		return
	Music.play_soundtrack(dusk_soundtrack)
