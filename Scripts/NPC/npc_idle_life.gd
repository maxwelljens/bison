@icon("res://addons/at-icons/node/telescope.svg")
class_name NpcIdleLife
extends Node
## Ambient idle-life animation: a breathing bob and periodic glances.
##
## Composed as a child of an [Npc] body (engine-ticked, like every node
## script here). Purely cosmetic and sprite-only — it writes only the
## sprite's scale and rotation, NEVER [member AnimatedSprite2D.flip_h]:
## facing arbitration stays with the motor and [NpcWary] until the
## animator increment lands. The bob runs always; glances only fire while
## the body is stationary. Every reference degrades silently when
## unassigned, per project convention.

@export_category("References")
## The body whose sprite is animated; typically [code]NodePath("..")[/code]
## (the parent Npc).
@export var npc: Npc

@export_category("Breathing")
## Seconds per breathing-bob cycle.
@export_range(0.1, 30.0, 0.1, "suffix:s") var bob_period: float = 2.4
## Peak scale distortion of the breath, as a unitless fraction of the
## captured base scale (y stretches, x compensates for volume).
@export_range(0.0, 0.5, 0.005) var bob_amplitude: float = 0.03

@export_category("Glances")
## Lower bound in s between idle look-arounds.
@export_range(0.0, 60.0, 0.1, "suffix:s") var glance_interval_min: float = 3.0
## Upper bound in s between idle look-arounds.
@export_range(0.0, 60.0, 0.1, "suffix:s") var glance_interval_max: float = 8.0
## Peak head tilt of a glance, in degrees, left or right at random.
@export_range(0.0, 45.0, 0.5, "suffix:°") var glance_tilt: float = 6.0
## Seconds the tilt takes to reach its peak; the return takes as long.
@export_range(0.05, 5.0, 0.05, "suffix:s") var glance_duration: float = 0.35

# One-shot init: the sprite's captured base scale, on the first frame the
# references resolve (exported refs may be null before _ready, per the
# AGENTS.md appendix).
var _wired: bool = false
var _base_scale: Vector2 = Vector2.ONE
# Breathing clock and glance state: idle countdown, in-progress flag,
# elapsed tilt time and tilt side (+1 / -1).
var _time: float = 0.0
var _glance_timer: float = 0.0
var _glancing: bool = false
var _glance_time: float = 0.0
var _glance_side: float = 1.0


func _process(delta: float) -> void:
	if npc == null or npc.sprite == null:
		return
	if not _wired:
		_wired = true
		_base_scale = npc.sprite.scale
		_glance_timer = randf_range(glance_interval_min, glance_interval_max)
	_time += delta
	_breathe()
	_glance(delta)


## Volume-preserving breath: y stretches with the sine wave, x compensates
## inversely around the captured base scale. Runs every frame, moving or
## not — a creature breathes while it walks.
func _breathe() -> void:
	var wave := sin(TAU * _time / bob_period) * bob_amplitude
	npc.sprite.scale = Vector2(
			_base_scale.x * (1.0 - wave),
			_base_scale.y * (1.0 + wave))


## Look-around: after a randomised interval, a small tilt to one side and
## back — only while the body is stationary (never while moving). A body
## that starts moving mid-glance snaps the tilt back out immediately.
func _glance(delta: float) -> void:
	var stationary := npc.velocity.length() < 1.0
	if _glancing:
		if not stationary:
			_cancel_glance()
			return
		_glance_time += delta
		var peak := deg_to_rad(glance_tilt) * _glance_side
		if _glance_time < glance_duration:
			npc.sprite.rotation = peak * (_glance_time / glance_duration)
		elif _glance_time < glance_duration * 2.0:
			var back := (_glance_time - glance_duration) / glance_duration
			npc.sprite.rotation = peak * (1.0 - back)
		else:
			npc.sprite.rotation = 0.0
			_glancing = false
			_glance_timer = randf_range(glance_interval_min, glance_interval_max)
		return
	_glance_timer -= delta
	# An expired interval waits for the next stationary moment instead of
	# firing on the move.
	if _glance_timer <= 0.0 and stationary:
		_glancing = true
		_glance_time = 0.0
		_glance_side = -1.0 if randf() < 0.5 else 1.0


## Ends an in-progress glance immediately: rotation home, interval re-rolled.
func _cancel_glance() -> void:
	_glancing = false
	npc.sprite.rotation = 0.0
	_glance_timer = randf_range(glance_interval_min, glance_interval_max)
