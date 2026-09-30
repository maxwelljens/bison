@icon("res://addons/at-icons/node/brain.svg")
class_name NpcBrain
extends Node
## Generic finite-state-machine host for NPCs, mirroring the [Player]'s
## FSM contract.
##
## The brain owns transitions: each physics frame it senses, advances the
## shared pressure meter through the current state, runs the current
## state's [method NpcState.physics_process], then applies any transition
## the state requested via [method request] — states never force a
## mid-frame switch (same "transitions are evaluated after the state
## runs" shape as the player). States are plain child nodes (never
## engine-ticked); the one-shot startup wires the sense area, calls
## [method NpcState.setup] on every direct state child and enters
## [member initial_state]. All references degrade silently when
## unassigned. The brain never names a concrete state class — only
## [NpcState] — which is what makes this layer reusable by any NPC.

## Physics collision mask for line of sight: layer 1 ("World") only, so
## solid tiles occlude the view and one-way platforms (layer 2) do not.
const WORLD_MASK := 1

@export_category("References")
## The creature body this brain steers.
@export var npc: Npc
## Waypoint executor driving the body: runs every wander and pursuit route.
@export var follower: BotPathFollower
## Route source behind the follower; movement commands also wait on it.
@export var pathfinder: PlatformerPathfinder
## Personal-space bubble detector (mask 8 = the player). Its collision
## shape radius — scene default 48 px — is the Inspector knob for how
## close counts as "invaded".
@export var sense_area: Area2D
## Optional pressure/state readout, e.g. "0.72 Pursue"; null = silent.
@export var debug_label: Label
## State node entered on startup; null = the brain stays idle (silent).
@export var initial_state: NpcState

@export_category("Pressure")
## Seconds to fill 0→1 while sensed (shared by the accumulating states).
@export_range(0.1, 60.0, 0.1, "suffix:s") var fill_time: float = 2.0
## Seconds to drain 1→0 while not sensed (shared by the accumulating states).
@export_range(0.1, 60.0, 0.1, "suffix:s") var decay_time: float = 1.5

@export_category("Feedback")
## Per-second strength of the tint lerp toward [member tint_target].
@export_range(0.0, 60.0, 0.5) var tint_lerp_speed: float = 8.0

## The player currently inside the personal-space bubble; null = none.
var player: Player
## This frame's line-of-sight result: inside the bubble AND clear view
## (solid tiles occlude, one-way platforms don't).
var sensed: bool = false
## Personal-space pressure fill, 0..1, shaped each frame by the current
## state's [method NpcState.update_pressure] rule.
var pressure: float = 0.0
## Body modulate lerped toward every frame; set by the entering state.
var tint_target: Color = Color.WHITE

# The state running this frame, and the state a state asked to move to.
var _current: NpcState
var _pending: NpcState
# One-shot startup flag (AGENTS.md appendix: refs may be null in _ready).
var _wired: bool = false


func _process(_delta: float) -> void:
	if _wired:
		return
	_wired = true
	set_process(false)
	if sense_area != null:
		sense_area.body_entered.connect(_on_sense_body_entered)
		sense_area.body_exited.connect(_on_sense_body_exited)
	for child in get_children():
		if child is NpcState:
			(child as NpcState).setup(self)
	if initial_state != null:
		_current = initial_state
		_current.enter(null)


func _physics_process(delta: float) -> void:
	if not _wired or _current == null:
		return
	_update_sensing()
	_current.update_pressure(delta)
	_current.physics_process(delta)
	if _pending != null:
		var next := _pending
		_pending = null
		_transition(next)
	_update_tint(delta)
	_update_debug_label()


## A state asks to leave: the brain applies it after the state's frame
## (states never force a mid-frame transition; mirrors the player's
## "transitions are evaluated after the state runs").
func request(next: NpcState) -> void:
	_pending = next


## The state currently running ([code]null[/code] before startup, or when
## [member initial_state] is unassigned).
func current_state() -> NpcState:
	return _current


## Swaps the current state, in the player's order: the old state exits
## first, then the new one is assigned and enters with the old state as
## [param next]'s previous.
func _transition(next: NpcState) -> void:
	var previous := _current
	previous.exit()
	_current = next
	_current.enter(previous)


## A player inside the bubble becomes the sensed target.
func _on_sense_body_entered(body: Node2D) -> void:
	if body is Player:
		player = body as Player


## Leaving the bubble ends sensing (the ray is skipped from now on).
func _on_sense_body_exited(body: Node2D) -> void:
	if body is Player and player == body:
		player = null


## Recomputes the sensed flag: at most one line-of-sight ray per physics
## frame, and only while a player is inside the bubble.
func _update_sensing() -> void:
	sensed = false
	if npc == null or not is_instance_valid(player):
		return
	var query := PhysicsRayQueryParameters2D.create(
			npc.global_position, player.global_position, WORLD_MASK)
	query.exclude = [npc.get_rid()]
	sensed = npc.get_world_2d().direct_space_state \
			.intersect_ray(query).is_empty()


## Lerps the body's modulate toward [member tint_target]; the weight is
## clamped so a long frame cannot overshoot past the target.
func _update_tint(delta: float) -> void:
	if npc == null:
		return
	npc.modulate = npc.modulate.lerp(tint_target,
			minf(tint_lerp_speed * delta, 1.0))


## Writes the pressure/state readout; skipped entirely when unassigned.
func _update_debug_label() -> void:
	if debug_label == null:
		return
	debug_label.text = "%.2f %s" % [pressure,
			_current.name if _current != null else "-"]
