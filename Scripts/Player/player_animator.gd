@icon("res://addons/at-icons/node/clapperboard.svg")
class_name PlayerAnimator
extends Node
## Maps semantic animation intents from the current player state onto
## SpriteFrames animations, and owns sprite facing.
##
## States never touch the sprite directly: they report IDLE/RUN/STOP/AIR
## and the animator resolves animation names, the STOP one-shot hold, and
## flipping. Swapping art (or renaming animations) only touches the
## exported name mappings below.

## What the current state wants the sprite to show.
enum Intent {
	## Standing still (or releasing input below the stop threshold).
	IDLE,
	## Moving under player control.
	RUN,
	## One-frame skid shown for [member stop_hold_time] after releasing
	## move input at speed.
	STOP,
	## Any airborne phase; rising and falling share the jump frames for now.
	AIR,
}

## The player's AnimatedSprite2D.
@export var sprite: AnimatedSprite2D
## SpriteFrames animation played for [enum Intent.IDLE].
@export var anim_idle: StringName = &"idle"
## SpriteFrames animation played for [enum Intent.RUN].
@export var anim_run: StringName = &"run"
## SpriteFrames animation played for [enum Intent.STOP].
@export var anim_stop: StringName = &"stop"
## SpriteFrames animation played for [enum Intent.AIR].
@export var anim_air: StringName = &"jump"
## Seconds the STOP one-shot holds before the pending intent resumes.
@export_range(0.0, 2.0, 0.05) var stop_hold_time: float = 0.2

# Animation currently requested (the scene autoplays "idle" until the
# first set_intent call, which matches this initial value).
var _shown: Intent = Intent.IDLE
var _stop_latched: bool = false
var _stop_hold_remaining: float = 0.0


## Applies the state's intent: STOP starts a one-shot latch that ignores
## IDLE until it expires; RUN and AIR cancel the latch; everything else
## maps straight to its animation.
func set_intent(intent: Intent) -> void:
	if intent == Intent.STOP:
		if not _stop_latched:
			_stop_latched = true
			_stop_hold_remaining = stop_hold_time
			_show(Intent.STOP)
		return
	if intent == Intent.RUN or intent == Intent.AIR:
		_stop_latched = false
		_stop_hold_remaining = 0.0
		_show(intent)
		return
	if not _stop_latched:
		_show(intent)


## Faces the sprite left or right; ignored for a neutral direction so the
## last facing is kept.
func set_facing(direction: float) -> void:
	if sprite != null and direction != 0.0:
		sprite.flip_h = direction < 0.0


func _process(delta: float) -> void:
	if _stop_latched:
		_stop_hold_remaining -= delta
		if _stop_hold_remaining <= 0.0:
			_stop_latched = false


func _show(intent: Intent) -> void:
	if sprite == null or _shown == intent:
		return
	_shown = intent
	sprite.play(_name_for(intent))


func _name_for(intent: Intent) -> StringName:
	match intent:
		Intent.RUN:
			return anim_run
		Intent.STOP:
			return anim_stop
		Intent.AIR:
			return anim_air
	return anim_idle
