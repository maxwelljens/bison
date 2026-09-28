@icon("res://addons/at-icons/node/speaker.svg")
class_name PlayerSfx
extends Node
## Plays sound effects for player events, driven by the same intent flow
## as the [PlayerAnimator].
##
## States never touch audio: the player forwards the current state's
## intent (plus a grounded flag and jump/land events) and this node
## decides what to play. Sounds live in an [enum Event]-keyed resolver,
## so hooking up a future action is three steps: add an [enum Event]
## entry, add its [code]@export[/code] stream, add a match arm in
## [method _stream_for] — then call [method Player.play_sfx] from
## wherever the event is detected. Unassigned streams silently skip
## their event (never an error).
##
## Overlapping sounds are handled by a round-robin pool of
## [member voice_count] voices created here in code, so events never cut
## each other off and the scene needs no per-voice wiring.

## Sound events the player can trigger.
enum Event {
	## Jump launch.
	JUMP,
	## Touchdown after being airborne.
	LAND,
	## Hard landing that stuns.
	HARD_LAND,
	## Lethal landing; the run ends.
	DEATH,
	## One running footstep (timed here, see [member footstep_interval]).
	FOOTSTEP,
	## One-frame skid when releasing move input at speed.
	STOP,
}

## Played on jump launch.
@export var sound_jump: AudioStream = preload("res://Audio/SFX/Movement/Jumping and Landing/sfx_movement_jump13.ogg")
## Played on touchdown; pairs with [member sound_jump].
@export var sound_land: AudioStream = preload("res://Audio/SFX/Movement/Jumping and Landing/sfx_movement_jump13_landing.ogg")
## Played on a hard landing that stuns (unassigned by default: assign one
## in the Inspector or leave empty for silence).
@export var sound_hard_land: AudioStream
## Played on a lethal landing (unassigned by default: assign one in the
## Inspector or leave empty for silence).
@export var sound_death: AudioStream
## Footstep sounds, cycled in order per step.
@export var sound_footsteps: Array[AudioStream]
## Played once per stop (unassigned by default: the pack has no skid
## sound yet; assign one in the Inspector or leave empty for silence).
@export var sound_stop: AudioStream = preload("res://Audio/SFX/Movement/Footsteps/sfx_movement_footstepsloop4_slow.ogg")

## Number of overlapping sounds allowed before the oldest is reused.
@export_range(1, 16) var voice_count: int = 4
## Seconds between footsteps while the RUN intent is active.
@export_range(0.05, 2.0, 0.05) var footstep_interval: float = 0.3
## Volume applied to every voice, in dB.
@export_range(-60.0, 6.0) var volume_db: float = 0.0

# Round-robin voice pool; created in _ready so the scene needs no wiring.
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
# Footstep pacing state.
var _footstep_timer: float = 0.0
var _footstep_index: int = 0
var _running: bool = false
var _grounded: bool = false
# Previous intent, so STOP plays only on its one-frame edge.
var _last_intent: PlayerAnimator.Intent = PlayerAnimator.Intent.IDLE


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


## Receives the state's animation intent every physics frame (same flow
## as [method PlayerAnimator.set_intent]). Footsteps tick while the RUN
## intent is held; STOP plays only on its edge.
func set_intent(intent: PlayerAnimator.Intent) -> void:
	_running = intent == PlayerAnimator.Intent.RUN
	if intent == PlayerAnimator.Intent.STOP and _last_intent != PlayerAnimator.Intent.STOP:
		play(Event.STOP)
	_last_intent = intent


## Gates footsteps on floor contact, so coyote airtime stays silent
## even though Grounded keeps emitting the RUN intent there.
func set_grounded(grounded: bool) -> void:
	_grounded = grounded
	if not grounded:
		_footstep_timer = 0.0


func _physics_process(delta: float) -> void:
	if not _running or not _grounded:
		return
	# Reset to 0 whenever not running so a run always starts with an
	# immediate step.
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = footstep_interval
		_play_footstep()


func _play_footstep() -> void:
	var streams := sound_footsteps
	if streams.is_empty():
		return
	play_stream(streams[_footstep_index])
	_footstep_index = (_footstep_index + 1) % streams.size()


func _stream_for(event: Event) -> AudioStream:
	match event:
		Event.JUMP:
			return sound_jump
		Event.LAND:
			return sound_land
		Event.HARD_LAND:
			return sound_hard_land
		Event.DEATH:
			return sound_death
		Event.STOP:
			return sound_stop
	return null
