extends TextureRect
## Day-phase face for the HUD clock.
##
## Swaps its texture when [code]GameClock[/code] changes phase. All three
## art slots ship unassigned; a null slot keeps the previous face instead
## of blanking (the project's missing-art convention: no errors, no
## blanking). The [code]Phase[/code] enum lives on the class_name-less
## [code]GameClock[/code] autoload, so the handler is typed [code]int[/code].

## Face while the day is wide open.
@export var texture_day: Texture2D
## Face during the pre-dusk warning window.
@export var texture_warning: Texture2D
## Face once the clock reaches dusk.
@export var texture_dusk: Texture2D


func _ready() -> void:
	GameClock.phase_changed.connect(_on_phase_changed)
	_apply(GameClock.phase)


func _on_phase_changed(phase: int) -> void:
	_apply(phase)


func _apply(phase: int) -> void:
	var slot: Texture2D = null
	if phase == GameClock.Phase.DUSK:
		slot = texture_dusk
	elif phase == GameClock.Phase.WARNING:
		slot = texture_warning
	else:
		slot = texture_day
	if slot != null:
		texture = slot
