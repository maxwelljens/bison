@icon("res://addons/at-icons/node/lever.svg")
class_name NpcPursue
extends NpcState
## Chase state: flags the body as hunting, switches to the pursuit pace
## and re-routes at the player's live position until the rage budget
## burns down to [member calm_at].

func _init() -> void:
	# The chase announces itself once as it becomes current.
	enter_sfx = NpcSfx.Event.AGGRO_CRY


@export_category("Transitions")
## State entered when the pressure drops to [member calm_at]; the meter is
## reset to zero first — that reset is the player's window to leave.
@export var calm_state: NpcState
## Stands down below this pressure.
@export_range(0.0, 1.0, 0.01) var calm_at: float = 0.2

@export_category("Behaviour")
## Pursuit pace in px/s, applied to move_speed on entry.
@export_range(0.0, 500.0, 0.5, "suffix:px/s") var pursuit_speed: float = 58.0
## Seconds between re-routes toward the live player position.
@export_range(0.05, 5.0, 0.05, "suffix:s") var reroute_interval: float = 0.25

@export_category("Pressure")
## Seconds to drain 1→0 while sensed — the fixed chase budget; the meter
## never refills during a chase.
@export_range(0.1, 60.0, 0.1, "suffix:s") var rage_time: float = 4.0
## Seconds to drain 1→0 while not sensed; shorter than [member rage_time]
## so broken contact burns the budget down faster.
@export_range(0.1, 60.0, 0.1, "suffix:s") var lost_contact_rage_time: float = 2.0

@export_category("Feedback")
## Tint lerped onto the body while hunting.
@export var aggressive_tint: Color = Color(1.0, 0.45, 0.4)

# Seconds until the next pursuit re-route.
var _reroute_timer: float = 0.0


## Flags the body as hunting, takes the pursuit pace, applies the contact
## rule to anyone already standing in the contact zone, aims the tint and
## fires the first re-route immediately.
func enter(_previous: NpcState) -> void:
	# Entry intent: the transition frame must not show the predecessor's
	# intent while this state runs its first tick.
	intent = Intent.CHARGE
	if brain.npc != null:
		brain.npc.aggressive = true
		brain.npc.move_speed = pursuit_speed
		brain.npc.check_contact_kill()
	brain.tint_target = aggressive_tint
	_reroute_timer = reroute_interval
	_pursue()


## Re-routes at the player's live position every [member reroute_interval]
## seconds. A false route (unreachable or climb-only) is ignored — the
## creature strands and the fixed chase budget keeps burning down (it
## cannot climb, by design). Standing down at [member calm_at] resets the
## meter first, then requests the calm state.
func physics_process(delta: float) -> void:
	_reroute_timer -= delta
	if _reroute_timer <= 0.0:
		_reroute_timer = reroute_interval
		_pursue()
	if brain.npc != null:
		intent = Intent.CHARGE if absf(brain.npc.velocity.x) > 1.0 else Intent.IDLE
	if brain.pressure <= calm_at:
		# The meter restarting from zero is the player's window to leave.
		brain.pressure = 0.0
		brain.request(calm_state)


## One re-route to the player's current position.
func _pursue() -> void:
	if brain.follower == null or brain.pathfinder == null \
			or not is_instance_valid(brain.player):
		return
	brain.follower.move_to(brain.player.global_position)


## Hunting ends on every exit path: the body stops being lethal.
func exit() -> void:
	if brain.npc != null:
		brain.npc.aggressive = false


## Rage burn-down: the shared fill/decay rule never runs during a chase —
## the meter only drains, faster once contact breaks, and never refills.
func update_pressure(delta: float) -> void:
	brain.pressure -= delta / (rage_time if brain.sensed else lost_contact_rage_time)
	brain.pressure = clampf(brain.pressure, 0.0, 1.0)
