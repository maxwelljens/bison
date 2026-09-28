@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerStunned
extends PlayerState
## Stunned state: hard-landing control lockout with a momentum slide.
##
## Entered when a landing's fall distance reaches the player's stun
## threshold. Input is dead (the player zeroes it every frame), the
## kept horizontal momentum decelerates under the player's friction
## like an unpowered skid, and the STUN intent loops the stun animation
## for [member stun_time]. Recovery is the player's call: back to
## [PlayerGrounded] when the timer expires on the floor, or straight to
## [PlayerAirborne] when the slide carries the body off a ledge.

## Seconds the stun lockout lasts before control returns.
@export_range(0.0, 3.0, 0.05, "suffix:s") var stun_time: float = 0.75

var _remaining: float = 0.0


## True once the stun timer has run out; the player reads this for its
## recovery rule.
func expired() -> bool:
	return _remaining <= 0.0


func enter(_previous: PlayerState) -> void:
	_remaining = stun_time
	intent = PlayerAnimator.Intent.STUN


func physics_process(delta: float) -> void:
	_remaining -= delta
	if not player.is_on_floor():
		_apply_gravity(delta)
	# Input is zeroed while stunned, so the steer call is a pure
	# friction slide of the kept momentum.
	_steer(delta)
	intent = PlayerAnimator.Intent.STUN
	player.move_and_slide()
