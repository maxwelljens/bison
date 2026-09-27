@icon("res://addons/at-icons/node/speaker.svg")
class_name ChestSfx
extends Node
## Plays sound effects for chest events, mirroring the [PlayerSfx]
## event flow.
##
## The chest forwards its events and this node decides what to play.
## Sounds live in an [enum Event]-keyed resolver, so hooking up a future
## event is three steps: add an [enum Event] entry, add its
## [code]@export[/code] stream, add a match arm in
## [method _stream_for]. Unassigned streams silently skip their event
## (never an error).
##
## Overlapping sounds are handled by a round-robin pool of
## [member voice_count] voices created here in code, so events never cut
## each other off and the scene needs no per-voice wiring.

## Sound events the chest can trigger.
enum Event {
	## Lid opens.
	OPEN,
	## An item finishes buffering in.
	REVEALED,
	## The player takes a revealed item.
	TAKEN,
	## The player puts an item back.
	RETURNED,
	## The loot screen is presented again for an already open chest.
	REOPEN,
	## The loot screen closes.
	CLOSE,
}

## Played when the chest opens.
@export var sound_open: AudioStream = preload("res://Audio/SFX/General Sounds/Buttons/sfx_sounds_button6.ogg")
## Played when an item finishes buffering in.
@export var sound_revealed: AudioStream = preload("res://Audio/SFX/General Sounds/Simple Bleeps/sfx_sounds_Blip1.ogg")
## Played when the player takes an item.
@export var sound_taken: AudioStream = preload("res://Audio/SFX/General Sounds/Coins/sfx_coin_single1.ogg")
## Played when the player puts an item back.
@export var sound_returned: AudioStream = preload("res://Audio/SFX/General Sounds/Menu Sounds/sfx_menu_select2.ogg")
## Played when the loot screen is presented again for an open chest.
@export var sound_reopen: AudioStream = preload("res://Audio/SFX/General Sounds/Interactions/sfx_sounds_interaction1.ogg")
## Played when the loot screen closes.
@export var sound_close: AudioStream = preload("res://Audio/SFX/General Sounds/Menu Sounds/sfx_menu_move1.ogg")

## Number of overlapping sounds allowed before the oldest is reused.
@export_range(1, 16) var voice_count: int = 4
## Volume applied to every voice, in dB.
@export_range(-60.0, 6.0) var volume_db: float = 0.0

# Round-robin voice pool; created in _ready so the scene needs no wiring.
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	for i in voice_count:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = volume_db
		add_child(voice)
		_voices.append(voice)


## Plays one of the [enum Event] sounds; silently skips unassigned ones.
func play(event: Event) -> void:
	play_stream(_stream_for(event))


## Plays an arbitrary stream on the next pooled voice; null is a no-op.
## Escape hatch for future one-off sounds outside the [enum Event] set.
func play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.play()


func _stream_for(event: Event) -> AudioStream:
	match event:
		Event.OPEN:
			return sound_open
		Event.REVEALED:
			return sound_revealed
		Event.TAKEN:
			return sound_taken
		Event.RETURNED:
			return sound_returned
		Event.REOPEN:
			return sound_reopen
		Event.CLOSE:
			return sound_close
	return null
