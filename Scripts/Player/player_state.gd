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
