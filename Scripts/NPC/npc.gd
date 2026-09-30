class_name Npc
extends PlatformerBot
## Generic NPC body shared by every creature steered by an NPC brain.
##
## [PlatformerBot] supplies the locomotion (the brain's states set
## [member PlatformerBot.move_speed] to switch between wander and pursuit
## pacing); this script adds only the body's concerns: a contact zone that
## acts on the [Player] on touch while [member aggressive] is set, plus the
## one-shot startup wiring for it. Behaviour machinery lives alongside in
## `Scripts/NPC/` — the dependency stays one-way (the brain and its states
## read and write this body, this script never references the brain or any
## state class). Every reference degrades silently when unassigned, per
## project convention.

## True while the brain's pursue state is active: the body is hunting.
var aggressive: bool = false

@export_category("References")
## Kill contact zone: overlaps the player (physics layer 4, mask 8) and,
## while [member aggressive], turns any body contact into an instant kill
## (one-touch mortality).
@export var contact_area: Area2D

# One-shot startup flag: wiring runs on the first _process tick, because
# exported node refs may still be null inside _ready (AGENTS.md appendix).
var _wired: bool = false


func _process(_delta: float) -> void:
	if _wired:
		return
	_wired = true
	set_process(false)
	if contact_area != null:
		contact_area.body_entered.connect(_on_contact_body_entered)


## Contact rule: a player touch acts only while the body is hunting;
## docile contact is harmless. The act itself is the species hook below.
func _on_contact_body_entered(body: Node2D) -> void:
	if body is Player and aggressive:
		on_contact_player(body as Player)


## Applies the contact rule to every player inside the contact zone right
## now — called when the body starts hunting, so a player already
## standing inside dies at the flip instead of needing to re-enter.
func check_contact_kill() -> void:
	if contact_area == null:
		return
	for body in contact_area.get_overlapping_bodies():
		if body is Player:
			on_contact_player(body as Player)


## Species hook: what touching [param player] does while [member aggressive].
## The default is instant death (one-touch mortality); override for
## non-lethal species (bluff charges, shoves).
func on_contact_player(player: Player) -> void:
	if aggressive:
		player.kill()
