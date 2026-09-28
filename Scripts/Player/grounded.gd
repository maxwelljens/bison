@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerGrounded
extends PlayerState
## Grounded state: floor contact, coyote grace, and jump launching.
##
## Owns the coyote timer: the player leaves this state only when the floor
## is lost AND the coyote window has expired, so buffered and coyote jumps
## fire here exactly as they did in the flat controller. Gravity still
## integrates during the grace window after walking off a ledge, and air
## control stays identical to ground control, as before.

## Seconds after leaving a ledge during which jumping is still allowed.
@export_range(0.0, 0.5) var coyote_time: float = 0.1
## Seconds a jump press before landing is remembered and fired on touchdown.
@export_range(0.0, 0.5) var jump_buffer_time: float = 0.1
## Horizontal speed in px/s at or above which releasing move input shows
## the stop intent.
@export_range(0.0, 100.0, 1.0) var run_min_speed: float = 10.0

var _coyote_timer: float = 0.0
var _had_direction: bool = false


## True while the coyote window keeps this state active off the floor;
## the player reads this for its exit rule.
func coyote_active() -> bool:
	return _coyote_timer > 0.0


func enter(_previous: PlayerState) -> void:
	_had_direction = player.input_direction != 0.0
	intent = PlayerAnimator.Intent.RUN if _had_direction else PlayerAnimator.Intent.IDLE


func physics_process(delta: float) -> void:
	if player.is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		_apply_gravity(delta)

	# Jump fires only when both grace windows are live: buffered press AND
	# (on the ledge or within coyote time after leaving it).
	if player.jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		player.velocity.y = player.jump_velocity
		player.jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		player.jumped_this_frame = true

	# Variable jump height: early release while rising scales velocity down
	# instead of stopping, so a tap gives a short hop. The launch frame's
	# own release edge is seen here; releases on later frames land in
	# PlayerAirborne.
	_apply_jump_cut()

	var direction := player.input_direction
	_steer(delta)

	_update_intent(direction)
	player.move_and_slide()


func _update_intent(direction: float) -> void:
	if direction != 0.0:
		_had_direction = true
		intent = PlayerAnimator.Intent.RUN
	elif _had_direction and absf(player.velocity.x) >= run_min_speed:
		# One-frame STOP intent; the animator holds it for stop_hold_time
		# and lets IDLE resume afterwards.
		intent = PlayerAnimator.Intent.STOP
		_had_direction = false
	else:
		_had_direction = false
		intent = PlayerAnimator.Intent.IDLE
