@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerDead
extends PlayerState
## Dead state: terminal freeze after a lethal landing.
##
## Entered when a landing's fall distance reaches the player's lethal
## threshold. Input is dead (the player zeroes it every frame), velocity
## is held at zero so the body stays exactly where it collapsed, and the
## DEAD intent plays the one-shot death animation. No state ever leaves
## this one: the run ends here until the scene is reloaded (the
## permadeath flow of DESIGN.md §9 is unwired). Any open loot screen is
## closed on entry.


func enter(_previous: PlayerState) -> void:
	player.velocity = Vector2.ZERO
	intent = PlayerAnimator.Intent.DEAD
	Loot.close_session()


func physics_process(_delta: float) -> void:
	player.velocity = Vector2.ZERO
	intent = PlayerAnimator.Intent.DEAD
	player.move_and_slide()
