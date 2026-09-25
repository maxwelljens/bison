@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerAirborne
extends PlayerState
## Airborne state: unpowered flight.
##
## Integrates gravity and terminal velocity, keeps the pre-existing air
## control (identical to ground control), and emits the single AIR intent
## for the whole flight. Jumping is NOT handled here: the player leaves
## [PlayerGrounded] only after the coyote window closes, so buffered and
## coyote jumps have already been resolved by the time this state runs.


func enter(_previous: PlayerState) -> void:
	intent = PlayerAnimator.Intent.AIR


func physics_process(delta: float) -> void:
	player.velocity.y = minf(
		player.velocity.y + player.get_gravity_strength() * delta, player.max_fall_speed)

	# Jump cut: a release while rising scales velocity. Launch-frame
	# releases are handled by PlayerGrounded; this catches the normal case
	# (release one or more frames after takeoff) and never-fired jumps.
	if player.jump_just_released and player.velocity.y < 0.0:
		player.velocity.y *= player.jump_cut_multiplier

	var direction := player.input_direction
	if direction != 0.0:
		player.velocity.x = move_toward(
			player.velocity.x, direction * player.move_speed, player.acceleration * delta)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.friction * delta)

	intent = PlayerAnimator.Intent.AIR
	player.move_and_slide()
