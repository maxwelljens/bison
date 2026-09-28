@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerAirborne
extends PlayerState
## Airborne state: unpowered flight.
##
## Integrates gravity and terminal velocity and steers horizontally
## through the shared [PlayerState] helpers (air control stays
## identical to ground control), and emits the single AIR intent for
## the whole flight. Jumping is NOT handled here: the player leaves
## [PlayerGrounded] only after the coyote window closes, so buffered
## and coyote jumps have already been resolved by the time this state
## runs.


func enter(_previous: PlayerState) -> void:
	intent = PlayerAnimator.Intent.AIR


func physics_process(delta: float) -> void:
	_apply_gravity(delta)

	# Jump cut: a release while rising scales velocity. Launch-frame
	# releases are handled by PlayerGrounded; this catches the normal case
	# (release one or more frames after takeoff) and never-fired jumps.
	_apply_jump_cut()
	_steer(delta)

	intent = PlayerAnimator.Intent.AIR
	player.move_and_slide()
