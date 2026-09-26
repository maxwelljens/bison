class_name ChestPrompt
extends HBoxContainer
## Interact prompt container for the [Chest]: a key label plus a
## description label, both styled in the scene.
##
## The chest fades the whole container in/out and swaps the description
## text between interaction phases (open → loot). The text keeps the
## Locale key verbatim so Godot's automatic translation resolves it.

## Label whose text carries the localized prompt description.
@export var text_label: Label


## Sets the description text, keeping the Locale key verbatim for
## automatic translation.
func set_text(value: String) -> void:
	if text_label == null:
		return
	text_label.text = value
