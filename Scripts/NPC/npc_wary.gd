@icon("res://addons/at-icons/node/lever.svg")
class_name NpcWary
extends NpcState
## Stop-and-watch state: halts the wander, holds position and faces the
## player while the pressure sits in the wary band. When the player invades
## its preferred clearance, a reluctant creature gives ground first — it
## backs directly away up to a per-episode budget, then stands and watches.

func _init() -> void:
	# Wary watches the player while backing away (facing is forwarded by
	# the brain), and warns once as it becomes current.
	facing_to_player = true
	enter_sfx = NpcSfx.Event.WARY_WARN


@export_category("Transitions")
## State entered when the pressure falls below [member calm_at].
@export var roam_state: NpcState
## State entered at [member aggro_at] pressure (the chase).
@export var aggressive_state: NpcState
## Falls back to roam below this pressure.
@export_range(0.0, 1.0, 0.01) var calm_at: float = 0.35
## Pressure at which it turns aggressive.
@export_range(0.0, 1.0, 0.01) var aggro_at: float = 1.0

@export_category("Retreat")
## Preferred centre-to-centre clearance in px: while the player is sensed
## and closer than this, the creature backs directly away. 0 disables
## retreat (stand-and-watch species).
@export_range(0.0, 256.0, 1.0, "suffix:px") var retreat_distance: float = 72.0
## Backing pace in px/s, applied to move_speed on entry (a nervous shuffle
## between the wander and pursuit paces).
@export_range(0.0, 200.0, 0.5, "suffix:px/s") var retreat_speed: float = 35.0
## Backing budget per wary episode in px: retreat goals stay within this
## radius of the position where the state was entered. Spending it makes
## the creature stand its ground.
@export_range(0.0, 512.0, 1.0, "suffix:px") var retreat_max_travel: float = 96.0
## Seconds between retreat goal refreshes while backing away; keeps the
## goal tracking a moving player without churning the follower every frame.
@export_range(0.05, 2.0, 0.05, "suffix:s") var retreat_replan_interval: float = 0.2

@export_category("Feedback")
## Tint lerped onto the body while wary.
@export var wary_tint: Color = Color(1.0, 0.9, 0.55)

# Centre of the current wary episode: the retreat budget is measured from
# here, and it is reset on every entry.
var _episode_origin: Vector2 = Vector2.ZERO
# Seconds until the next retreat goal refresh.
var _replan_timer: float = 0.0


## Halts any live route, records the episode origin, takes the retreat pace
## when retreat is enabled and aims the tint at the alert colour.
func enter(_previous: NpcState) -> void:
	if brain.follower != null:
		brain.follower.stop()
	if brain.npc != null:
		_episode_origin = brain.npc.global_position
	if _retreat_enabled() and brain.npc != null:
		brain.npc.move_speed = retreat_speed
	_replan_timer = 0.0
	brain.tint_target = wary_tint


## Drops any retreat route on every exit path (clean slate for the next
## state, which clears its own pace and tint on entry).
func exit() -> void:
	if brain.follower != null:
		brain.follower.stop()


## Backs away from a sensed, too-close player within the episode budget,
## then holds and watches; reports the RETREAT/WARY intent (the brain
## forwards facing to the player while this state watches) and checks this
## frame's pressure for a transition out. Pressure keeps accumulating
## through the base rule (no override here).
func physics_process(delta: float) -> void:
	_update_retreat(delta)
	if brain.npc != null:
		intent = Intent.RETREAT if absf(brain.npc.velocity.x) > 1.0 else Intent.WARY
	if brain.pressure >= aggro_at:
		brain.request(aggressive_state)
	elif brain.pressure < calm_at:
		brain.request(roam_state)


## True when [member retreat_distance] is positive (retreat enabled).
func _retreat_enabled() -> bool:
	return retreat_distance > 0.0


## The retreat trigger: enabled, wired, the player sensed and closer than
## the preferred clearance, and the episode budget not yet spent.
func _should_retreat() -> bool:
	if not _retreat_enabled() or brain.follower == null or brain.npc == null:
		return false
	if not brain.sensed or not is_instance_valid(brain.player):
		return false
	if _budget_spent():
		return false
	return brain.npc.global_position.distance_to(
			brain.player.global_position) < retreat_distance


## True once the body has used the whole per-episode backing budget.
func _budget_spent() -> bool:
	if brain.npc == null:
		return true
	return _episode_origin.distance_to(brain.npc.global_position) >= retreat_max_travel


## Runs one frame of retreat: while the trigger holds, refresh the goal on
## the [member retreat_replan_interval] cadence (the follower's queue makes
## the churn safe); otherwise hold position and watch.
func _update_retreat(delta: float) -> void:
	if not _should_retreat():
		_hold()
		return
	_replan_timer -= delta
	if _replan_timer > 0.0:
		return
	_replan_timer = retreat_replan_interval
	if not _commit_retreat_goal():
		_hold()


## Routes to a point [member retreat_distance] from the player, directly
## away from it and clamped to the episode budget. Returns whether the
## follower accepted a route.
func _commit_retreat_goal() -> bool:
	if brain.follower == null or brain.npc == null \
			or not is_instance_valid(brain.player):
		return false
	var npc_position: Vector2 = brain.npc.global_position
	var player_position: Vector2 = brain.player.global_position
	var away: Vector2 = npc_position - player_position
	if away.length_squared() < 0.0001:
		# Player exactly on the body: no meaningful away direction; step right.
		away = Vector2.RIGHT
	else:
		away = away.normalized()
	var goal: Vector2 = player_position + away * retreat_distance
	return brain.follower.move_to(_clamp_to_budget(goal))


## Keeps [param goal] inside [member retreat_max_travel] px of the episode
## origin (the character's willingness to give ground is bounded).
func _clamp_to_budget(goal: Vector2) -> Vector2:
	var offset: Vector2 = goal - _episode_origin
	if offset.length() > retreat_max_travel:
		offset = offset.limit_length(retreat_max_travel)
	return _episode_origin + offset


## Holds position and watches: clears the follower's route. Idempotent, so
## it is called every frame in the non-retreating sub-modes.
func _hold() -> void:
	if brain.follower != null:
		brain.follower.stop()
