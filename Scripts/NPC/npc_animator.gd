@icon("res://addons/at-icons/node/clapperboard.svg")
class_name NpcAnimator
extends Node
## Maps semantic animation intents from the current NPC state onto
## SpriteFrames animations, and owns sprite facing.
##
## States never touch the sprite directly: they report
## IDLE/WALK/CHARGE/WARY/RETREAT/JUMP and this node resolves animation
## names and flipping. Swapping art (or renaming animations) only touches
## the exported name mappings below. Exactly like the
## [PlayerAnimator], this is a pure call-through — it has no
## [method Node._process] of its own, and it never writes scale or
## rotation (the [NpcIdleLife] component owns those).

## What the current state wants the sprite to show.
enum Intent {
	## Standing still, or moving without a locomotion animation to show.
	IDLE,
	## Moving under the creature's own power (wander pace).
	WALK,
	## Moving at the pursuit pace — the hunt.
	CHARGE,
	## Alert stop-and-watch.
	WARY,
	## Giving ground while wary.
	RETREAT,
	## Any airborne phase; rising and falling share the jump frames for now.
	JUMP,
}

@export_category("References")
## The creature's AnimatedSprite2D.
@export var sprite: AnimatedSprite2D

@export_category("Animations")
## SpriteFrames animation played for [enum Intent.IDLE].
@export var anim_idle: StringName = &"idle"
## SpriteFrames animation played for [enum Intent.WALK].
@export var anim_walk: StringName = &"move"
## SpriteFrames animation played for [enum Intent.CHARGE].
@export var anim_charge: StringName = &"move"
## SpriteFrames animation played for [enum Intent.WARY]. The Mauser's
## SpriteFrames currently ships only idle/move/jump, so this intentionally
## falls back to idle until the wary art lands — the zero-code swap design.
@export var anim_wary: StringName = &"wary"
## SpriteFrames animation played for [enum Intent.RETREAT].
@export var anim_retreat: StringName = &"move"
## SpriteFrames animation played for [enum Intent.JUMP].
@export var anim_jump: StringName = &"jump"

# Resolved animation currently shown (the scene autoplays "idle" until the
# first set_intent call, which matches this initial value).
var _shown: StringName = &"idle"


## Sets the intent this frame; deduped (SpriteFrames play only on change)
## and missing animations degrade to idle instead of erroring.
func set_intent(intent: Intent) -> void:
	_show(intent)


## Owns facing: direction < 0 faces left, > 0 right, 0 keeps the current
## facing.
func set_facing(direction: float) -> void:
	if sprite != null and direction != 0.0:
		sprite.flip_h = direction < 0.0


func _show(intent: Intent) -> void:
	if sprite == null:
		return
	var name := _name_for(intent)
	# Unassigned or missing animations degrade to idle (e.g. wary frames
	# before the art lands) instead of erroring every frame.
	if sprite.sprite_frames != null and not sprite.sprite_frames.has_animation(name):
		name = anim_idle
	if _shown == name:
		return
	_shown = name
	sprite.play(name)


func _name_for(intent: Intent) -> StringName:
	match intent:
		Intent.WALK:
			return anim_walk
		Intent.CHARGE:
			return anim_charge
		Intent.WARY:
			return anim_wary
		Intent.RETREAT:
			return anim_retreat
		Intent.JUMP:
			return anim_jump
	return anim_idle
