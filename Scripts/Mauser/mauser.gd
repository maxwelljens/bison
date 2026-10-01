@icon("res://addons/at-icons/node2d/dragon.svg")
class_name Mauser
extends Npc
## The Mauser: territorial fauna (see docs/DESIGN.md §6). Docile roving
## grazer of the ruins whose personal space, invaded for too long, turns
## it lethal. This class is the species hook — species-wide behaviour
## (calls, traits) belongs here; behaviour machinery belongs in
## Scripts/NPC/ and is shared by every NPC.

## Species default (docs/DESIGN.md §6): the Mauser jumps gaps but never
## climbs ladders, so chains are an escape. Scene/Inspector values apply
## after [method _init] and override it per instance, so per-instance
## experiments (e.g. testing) still work — and a scene re-save can never
## silently lose the trait.
func _init() -> void:
	can_climb = false
