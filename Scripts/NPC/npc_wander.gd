@icon("res://addons/at-icons/node/lever.svg")
class_name NpcWander
extends Node
## Reusable wander component: the pacing behind a docile roam state.
##
## Composed as a child of a state node; its references are passed into
## [method start] and [method tick], never exported here. One cycle:
## idle for a randomised pause, pick a reachable point inside a box around
## the body and walk it via the [BotPathFollower]; the goal ends at
## [member reach_distance] or [member walk_timeout] (whichever first) and
## the pause resumes. Every export mirrors the old Mauser roam tuning.

@export_category("Wander")
## Wander pace in px/s, applied to [member PlatformerBot.move_speed] on start.
@export_range(0.0, 500.0, 0.5, "suffix:px/s") var speed: float = 25.0
## How far in px the next wander point may be picked from the body.
@export_range(16.0, 1024.0, 1.0, "suffix:px") var radius: float = 128.0
## Vertical spread of wander picks as a fraction of [member radius].
@export_range(0.0, 2.0, 0.01) var height_ratio: float = 0.5
## Lower bound in s of the randomised idle pause between wander goals.
@export_range(0.0, 60.0, 0.1, "suffix:s") var pause_min: float = 1.0
## Upper bound in s of the randomised idle pause between wander goals.
@export_range(0.0, 60.0, 0.1, "suffix:s") var pause_max: float = 3.0
## Fresh wander picks tried until the follower reports a route.
@export_range(1, 16, 1) var pick_attempts: int = 4
## Distance in px at which a wander goal counts as reached.
@export_range(0.5, 64.0, 0.5, "suffix:px") var reach_distance: float = 6.0
## Seconds after which a wander goal is abandoned, then the pause resumes.
@export_range(0.5, 120.0, 0.5, "suffix:s") var walk_timeout: float = 8.0

# Wander state: idle countdown, current goal and its walk timeout.
var _pause_timer: float = 0.0
var _goal: Vector2 = Vector2.ZERO
var _has_goal: bool = false
var _walk_timer: float = 0.0


## (Re)starts a wander cycle: clears any goal, puts [param npc] on
## [member speed] and begins a fresh randomised idle pause.
func start(npc: Npc) -> void:
	_has_goal = false
	_goal = Vector2.ZERO
	_walk_timer = 0.0
	_pause_timer = randf_range(pause_min, pause_max)
	if npc != null:
		npc.move_speed = speed


## Runs one frame of the wander cycle: idle for the pause, then pick a
## wander target and walk it until reached or timed out.
func tick(delta: float, npc: Npc, follower: BotPathFollower) -> void:
	if npc == null or follower == null:
		return
	if _pause_timer > 0.0:
		# Keep inputs cleared while idle in case a stale path is still live.
		follower.stop()
		_pause_timer -= delta
		return
	if not _has_goal and not _pick_goal(npc, follower):
		_pause_timer = randf_range(pause_min, pause_max)
		return
	if npc.global_position.distance_to(_goal) <= reach_distance:
		_finish_goal(follower)
		return
	_walk_timer -= delta
	if _walk_timer <= 0.0:
		_finish_goal(follower)


## Picks a wander point inside the roam box and asks the follower for a
## route, retrying with fresh picks up to [member pick_attempts] times
## (the follower snaps goals to standable ground; the body's capability
## flags constrain which routes the search can return).
func _pick_goal(npc: Npc, follower: BotPathFollower) -> bool:
	for _attempt in pick_attempts:
		var target: Vector2 = npc.global_position + Vector2(
				randf_range(-radius, radius),
				randf_range(-radius * height_ratio,
						radius * height_ratio))
		if follower.move_to(target):
			_goal = target
			_has_goal = true
			_walk_timer = walk_timeout
			return true
	return false


## Closes the current wander goal and starts the next idle pause.
func _finish_goal(follower: BotPathFollower) -> void:
	_has_goal = false
	_goal = Vector2.ZERO
	follower.stop()
	_pause_timer = randf_range(pause_min, pause_max)
