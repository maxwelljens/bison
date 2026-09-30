class_name NpcState
extends Node
## Base class for NPC state nodes.
##
## The brain owns transitions: it senses, advances the shared pressure
## meter, calls [method physics_process] on the current state each frame,
## and applies any transition the state requested through
## [method NpcBrain.request] after the state's frame. States therefore
## define a custom [method physics_process] — NOT
## [method Node._physics_process] — so the engine never ticks them on
## their own.

## The owning brain; assigned via [method setup].
var brain: NpcBrain


## Called once from the brain's one-shot startup, before any state logic
## runs.
func setup(b: NpcBrain) -> void:
	brain = b


## Called when this state becomes current. [param previous] is the state
## that just exited ([code]null[/code] on initial entry).
func enter(_previous: NpcState) -> void:
	pass


## Called when this state stops being current.
func exit() -> void:
	pass


## Runs one frame of this state's behaviour (custom name on purpose — the
## engine must never tick states itself).
func physics_process(_delta: float) -> void:
	pass


## Advances the shared pressure meter for one frame. The default is the
## accumulating rule (fill while the player is sensed, decay otherwise);
## states with a different rule — e.g. the pursue state's rage burn-down —
## override this.
func update_pressure(delta: float) -> void:
	if brain.sensed:
		brain.pressure += delta / brain.fill_time
	else:
		brain.pressure -= delta / brain.decay_time
	brain.pressure = clampf(brain.pressure, 0.0, 1.0)
