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
}

## Played when the chest opens.
@export var sound_open: AudioStream = preload("res://Audio/SFX/General Sounds/Buttons/sfx_sounds_button6.ogg")

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
	return null
