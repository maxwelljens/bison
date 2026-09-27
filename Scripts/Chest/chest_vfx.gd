@icon("res://addons/at-icons/node/magic_wand.svg")
class_name ChestVfx
extends CPUParticles2D
## One-shot open burst for the chest: a small particle poof plus a
## brightness/scale flash on the chest sprite.
##
## Created paused and not emitting; [method pulse] fires the burst and
## animates the flash through a [Tween] on the animation player's
## timeline. The flash never runs when no sprite reference was wired,
## so dropping the chest into a level without visuals degrades
## silently.

## Sprite that receives the open flash; leave unassigned to skip it.
@export var sprite: Sprite2D
## How far above the closed lid the burst emits, in px.
@export var burst_height: float = -4.0
## Brightness multiplier applied at the flash's peak.
@export_range(1.0, 3.0) var flash_brighten: float = 1.6
## Peak scale multiplier at the flash's peak, relative to the sprite's
## base scale.
@export_range(1.0, 2.0) var flash_scale: float = 1.15
## Seconds for the flash's rise and fall, each.
@export_range(0.05, 1.0) var flash_half_duration: float = 0.1

# Sprite's resting transform values, captured on the first pulse.
var _base_modulate: Color
var _base_scale: Vector2 = Vector2.ONE
# Guards capturing the base values more than once.
var _captured: bool = false
# Active flash tween, killed and restarted on re-pulse.
var _flash: Tween


func _ready() -> void:
	one_shot = true
	amount = 8
	lifetime = 0.4
	explosiveness = 1.0
	emitting = false
	position = Vector2(0.0, burst_height)
	direction = Vector2.UP
	spread = 60.0
	gravity = Vector2(0.0, 120.0)
	initial_velocity_min = 20.0
	initial_velocity_max = 40.0
	scale_amount_min = 1.0
	scale_amount_max = 2.0
	color = Color(1.0, 0.9, 0.5)


## Fires the whole open burst: particles plus the sprite light show.
func pulse() -> void:
	# Restart: a prior burst still finishing does not merge with the
	# fresh one.
	restart()
	if sprite != null:
		_flash_sprite()


## Brief brighten + scale swell on the sprite, then back to rest.
func _flash_sprite() -> void:
	if not _captured:
		_base_modulate = sprite.modulate
		_base_scale = sprite.scale
		_captured = true
	if _flash != null and _flash.is_valid():
		_flash.kill()
	# Reassign every flash parameter instead of tweening from the
	# live values; a re-pulse mid-flash starts clean.
	sprite.modulate = _base_modulate
	sprite.scale = _base_scale
	_flash = create_tween()
	_flash.tween_property(sprite, "modulate", Color(1, 1, 1) * flash_brighten, flash_half_duration)
	_flash.parallel().tween_property(
		sprite, "scale", _base_scale * flash_scale, flash_half_duration)
	_flash.tween_property(sprite, "modulate", _base_modulate, flash_half_duration)
	_flash.parallel().tween_property(sprite, "scale", _base_scale, flash_half_duration)
