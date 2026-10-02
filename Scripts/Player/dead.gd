@icon("res://addons/at-icons/node/lever.svg")
class_name PlayerDead
extends PlayerState
## Dead state: terminal freeze after a lethal landing.
##
## Entered when a landing's fall distance reaches the player's lethal
## threshold. Input is dead (the player zeroes it every frame), velocity
## is held at zero so the body stays exactly where it collapsed, and the
## DEAD intent plays the one-shot death animation. Entry also marks the
## run dead on [code]GameFlow[/code] — the warren exit stops accepting
## returns and the confirmation drops. No state ever leaves this one:
## after [member run_end_delay] the [code]GameFlow[/code] autoload
## routes the run back to the title screen (the run's day and stockpile
## reset on the next Start press). Any open loot screen is closed on
## entry and the day clock stops.

## Real seconds the death beat holds before GameFlow ends the run.
@export_range(0.1, 10.0, 0.1, "suffix:s") var run_end_delay: float = 2.0


func enter(_previous: PlayerState) -> void:
	player.velocity = Vector2.ZERO
	intent = PlayerAnimator.Intent.DEAD
	Loot.close_session()
	GameClock.stop_clock()
	GameFlow.mark_player_dead()
	get_tree().create_timer(run_end_delay).timeout.connect(_end_run, CONNECT_ONE_SHOT)


func physics_process(_delta: float) -> void:
	player.velocity = Vector2.ZERO
	intent = PlayerAnimator.Intent.DEAD
	player.move_and_slide()


func _end_run() -> void:
	GameFlow.end_run()
