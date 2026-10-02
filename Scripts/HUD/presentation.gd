@icon("res://addons/at-icons/node/icons.svg")
extends Node
## Shared screen presentation rig: background colour, HUD and CRT layers
## in one place, instanced by every screen (levels and menus) so the
## layer stack is authored once instead of copied per level.
##
## The CRT and background show everywhere — the tone follows the player
## into the menus — while the HUD is run-only, gated per screen through
## [member show_hud].

## Whether the HUD layer shows on this screen (true in levels, false on
## the title and colony screens).
@export var show_hud: bool = true
## The HUD instance inside the rig; hidden when [member show_hud] is clear.
@export var hud: Hud


func _ready() -> void:
	if hud != null:
		hud.visible = show_hud
