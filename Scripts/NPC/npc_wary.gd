@icon("res://addons/at-icons/node/lever.svg")
class_name NpcWary
extends NpcState
## Stop-and-watch state: halts the wander, holds position and faces the
## player while the pressure sits in the wary band.

@export_category("Transitions")
## State entered when the pressure falls below [member calm_at].
@export var roam_state: NpcState
## State entered at [member aggro_at] pressure (the chase).
@export var aggressive_state: NpcState
## Falls back to roam below this pressure.
@export_range(0.0, 1.0, 0.01) var calm_at: float = 0.35
## Pressure at which it turns aggressive.
@export_range(0.0, 1.0, 0.01) var aggro_at: float = 1.0

@export_category("Feedback")
## Tint lerped onto the body while wary.
@export var wary_tint: Color = Color(1.0, 0.9, 0.55)


## Halts any live route and aims the tint at the alert colour.
func enter(_previous: NpcState) -> void:
	if brain.follower != null:
		brain.follower.stop()
	brain.tint_target = wary_tint


## Holds position (inputs cleared every frame) and faces the player, then
## checks this frame's pressure for a transition out. Pressure keeps
## accumulating through the base rule (no override here).
func physics_process(_delta: float) -> void:
	if brain.follower != null:
		brain.follower.stop()
	if brain.npc != null and brain.npc.sprite != null \
			and is_instance_valid(brain.player):
		var dx: float = brain.player.global_position.x \
				- brain.npc.global_position.x
		if dx != 0.0:
			# Same facing convention as PlatformerBot: flip_h when heading left.
			brain.npc.sprite.flip_h = dx < 0.0
	if brain.pressure >= aggro_at:
		brain.request(aggressive_state)
	elif brain.pressure < calm_at:
		brain.request(roam_state)
