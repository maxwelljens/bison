extends Control
## Title screen: Start begins a fresh run in the colony, Exit quits.
##
## Presentation only — all run state lives on the [code]GameFlow[/code]
## autoload, so this screen never tracks anything between visits.

## Begins a fresh run and enters the colony hub.
@export var start_button: Button
## Quits the game.
@export var exit_button: Button


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _on_start_pressed() -> void:
	GameFlow.new_run()
	GameFlow.go_to_colony()


func _on_exit_pressed() -> void:
	get_tree().quit()
