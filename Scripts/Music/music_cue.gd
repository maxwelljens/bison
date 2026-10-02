@icon("res://addons/at-icons/node/file_note.svg")
class_name MusicCue
extends Node
## Announces this scene's soundtrack to the [code]Music[/code] autoload.
##
## Place one on a scene root: when the scene loads, its [method Node._ready]
## calls [code]Music.play_soundtrack()[/code] and the autoload crossfades
## to [member soundtrack]. Scene changes therefore carry their own score
## with no central registry to maintain.
##
## Conventions:
## - No cue in the scene: the music keeps playing, unchanged.
## - Cue with an empty or unassigned [member soundtrack]: the music
##   fades out - this scene wants silence.
## - Two scenes referencing the same [Soundtrack] resource: the second
##   announcement is a no-op, so the score plays through uninterrupted.

## The soundtrack this scene plays while it is the current scene.
@export var soundtrack: Soundtrack


func _ready() -> void:
	Music.play_soundtrack(soundtrack)
