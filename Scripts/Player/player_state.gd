class_name PlayerState
extends Node
## Base class for Player state nodes.
##
## The player owns transitions: it gathers input, calls
## [method physics_process] on the current state each frame, evaluates
## transitions after the state's [method CharacterBody2D.move_and_slide],
## and forwards the state's intent to the [PlayerAnimator]. States
## therefore define a custom [method physics_process] — NOT
## [method Node._physics_process] — so the engine never ticks them on
## their own.

## The owning player; assigned via [method setup] from the player's
## [method Node._ready].
var player: Player

## The animation intent this state wants shown (see [PlayerAnimator.Intent]).
var intent: PlayerAnimator.Intent = PlayerAnimator.Intent.IDLE


## Called once from the player's [method Node._ready] before any state
## logic runs.
func setup(p: Player) -> void:
	player = p


## Called when this state becomes current. [param previous] is the state
## that just exited ([code]null[/code] on initial entry).
func enter(_previous: PlayerState) -> void:
	pass


## Called when this state stops being current.
func exit() -> void:
	pass


## Runs one frame of this state's physics; must end with the player's
## [method CharacterBody2D.move_and_slide] so the player's transition
## check sees this frame's floor data.
func physics_process(_delta: float) -> void:
	pass


## Integrates gravity into the player's vertical velocity, clamped at
## terminal fall speed. Shared by the airborne-phase states; single
## edit point for gravity-related tuning behavior.
func _apply_gravity(delta: float) -> void:
	player.velocity.y = minf(
		player.velocity.y + player.get_gravity_strength() * delta,
		player.max_fall_speed)


## Scales upward velocity down on a jump-release edge (short hop).
## Call once per frame from a state that can be rising.
func _apply_jump_cut() -> void:
	if player.jump_just_released and player.velocity.y < 0.0:
		player.velocity.y *= player.jump_cut_multiplier


## Steers horizontal velocity toward the input target: acceleration
## toward the run speed with input, friction decay without.
func _steer(delta: float) -> void:
	if player.input_direction != 0.0:
		player.velocity.x = move_toward(
			player.velocity.x, player.input_direction * player.move_speed,
			player.acceleration * delta)
	else:
		player.velocity.x = move_toward(
			player.velocity.x, 0.0, player.friction * delta)
