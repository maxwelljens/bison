@icon("res://addons/at-icons/node/lever.svg")
class_name NpcRoam
extends NpcState
## Docile wander state: runs the [NpcWander] cycle and watches the shared
## pressure meter, leaving when it crosses a threshold (aggressive first,
## as in the original machine).

@export_category("Transitions")
## State entered at [member wary_at] pressure (stop and watch).
@export var wary_state: NpcState
## State entered at [member aggro_at] pressure (the chase).
@export var aggressive_state: NpcState
## Pressure at which it stops to watch.
@export_range(0.0, 1.0, 0.01) var wary_at: float = 0.35
## Pressure at which it turns aggressive.
@export_range(0.0, 1.0, 0.01) var aggro_at: float = 1.0

@export_category("Behaviour")
## Wander component driving the roam (a child of this state).
@export var wander: NpcWander

@export_category("Feedback")
## Tint lerped onto the body while docile.
@export var calm_tint: Color = Color.WHITE


## Takes the wander pace and a fresh pause, clears any route still live
## from the previous state, and aims the tint at calm.
func enter(_previous: NpcState) -> void:
	# Entry intent: the transition frame must not show the predecessor's
	# intent while this state runs its first tick.
	intent = Intent.IDLE
	if wander != null:
		wander.start(brain.npc)
	if brain.follower != null:
		brain.follower.stop()
	brain.tint_target = calm_tint


## Runs one frame of wandering, then checks this frame's pressure for a
## transition out. Pressure keeps accumulating through the base rule (no
## override here).
func physics_process(delta: float) -> void:
	if wander != null and brain.npc != null and brain.follower != null \
			and brain.pathfinder != null:
		wander.tick(delta, brain.npc, brain.follower)
	if brain.npc != null:
		intent = Intent.WALK if absf(brain.npc.velocity.x) > 1.0 else Intent.IDLE
	if brain.pressure >= aggro_at:
		if aggressive_state != null:
			brain.request(aggressive_state)
	elif brain.pressure >= wary_at:
		if wary_state != null:
			brain.request(wary_state)
