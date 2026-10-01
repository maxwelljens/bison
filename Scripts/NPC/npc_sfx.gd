class_name NpcSfx
extends AudioStreamPlayer2D
## Plays spatial sound effects for NPC events, driven by the shared event
## flow.
##
## The node itself is an [AudioStreamPlayer2D], so every event is emitted
## from the creature's position in the world and attenuates with distance
## like any other 2D sound. States and the brain never touch audio: they
## forward events (and this node detects landings, footsteps and idle
## calls itself from the body's state), and this node decides what to
## play. Sounds live in an [enum Event]-keyed resolver, so hooking up a
## future action is three steps: add an [enum Event] entry, add its
## [code]@export[/code] stream, add a match arm in [method _stream_for] —
## then call [method play_event] from wherever the event is detected.
## Unassigned streams silently skip their event (never an error).
##
## Overlapping sounds are handled by a round-robin pool of
## [member voice_count] spatial voices — this node is voice 0, and
## [member voice_count] - 1 [AudioStreamPlayer2D] children are created
## here in code so events never cut each other off and the scene needs no
## per-voice wiring — exactly the [PlayerSfx] contract, made spatial.
##
## Audition candidates for the three vocal slots (all unassigned by
## default): [code]Audio/SFX/General Sounds/High Pitched Sounds/sfx_sounds_high*[/code]
## (chirps and squeaks for [enum Event.IDLE_CALL]) and
## [code]Audio/SFX/General Sounds/Weird Sounds/*[/code] (agitated noises for
## [enum Event.WARY_WARN] / [enum Event.AGGRO_CRY]). The
## [code]Death Screams/Alien/*[/code] clips are deliberately NOT proposed:
## they are the player's death scream.

## Sound events an NPC can trigger.
enum Event {
	## No sound. The sentinel states assign to [member NpcState.enter_sfx]
	## when becoming current should stay silent (there is no null enum);
	## [method play_event] returns immediately on it.
	NONE,
	## Ambient call while docile and unthreatened.
	IDLE_CALL,
	## Warning note when the creature turns wary.
	WARY_WARN,
	## Cry as the creature commits to a chase.
	AGGRO_CRY,
	## One footstep (timed here, see [member footstep_interval]).
	STEP,
	## Touchdown after being airborne.
	LAND,
}

@export_category("References")
## The creature body this node listens to for landing/step/idle events.
@export var npc: Npc

@export_category("Voices")
## Number of overlapping sounds allowed before the oldest is reused.
## [br]This node is voice 0; the remaining [code]voice_count - 1[/code]
## voices are [AudioStreamPlayer2D] children built at startup. Voice 0
## carries the sound itself, so creature audio always emits from the
## body's world position.
## [br][b]Note:[/b] the native [AudioStreamPlayer2D] spatial tuning
## ([member AudioStreamPlayer2D.volume_db], [member AudioStreamPlayer2D.bus],
## [member AudioStreamPlayer2D.max_distance], [member AudioStreamPlayer2D.attenuation],
## [member AudioStreamPlayer2D.panning_strength]) is copied from this node
## onto every runtime child voice at startup. Tune it on the Sfx node in
## the Inspector before running; the runtime voices mirror it and are
## otherwise not individually exposed.
@export_range(1, 16) var voice_count: int = 4

@export_category("Sounds")
## Ambient call while docile (unassigned by default: assign one in the
## Inspector or leave empty for silence).
@export var sound_idle_call: AudioStream
## Warning note when wary (unassigned by default: assign one in the
## Inspector or leave empty for silence).
@export var sound_wary_warning: AudioStream
## Cry as the chase begins (unassigned by default: assign one in the
## Inspector or leave empty for silence).
@export var sound_aggro_cry: AudioStream
## Played on touchdown; shares the player's landing asset.
@export var sound_land: AudioStream = preload("res://Audio/SFX/Movement/Jumping and Landing/sfx_movement_jump13_landing.ogg")
## Footstep sounds, cycled in order per step.
@export var sound_footsteps: Array[AudioStream]

@export_category("Cadence")
## Seconds between footsteps while the creature is grounded and moving.
@export_range(0.05, 60.0, 0.05, "suffix:s") var footstep_interval: float = 0.3
## Shortest gap between docile calls, in seconds.
@export_range(1.0, 120.0, 0.5, "suffix:s") var idle_call_interval_min: float = 10.0
## Longest gap between docile calls, in seconds.
@export_range(1.0, 120.0, 0.5, "suffix:s") var idle_call_interval_max: float = 25.0

# Round-robin spatial voice pool: this node (voice 0) plus the child
# AudioStreamPlayer2D voices created in _ready, so the scene needs no
# wiring.
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice: int = 0
# Footstep pacing state.
var _footstep_timer: float = 0.0
var _footstep_index: int = 0
# Landing detection: was the body on the floor last frame? Seeded on the
# one-shot startup tick (see [method Node._process]) so the first real
# frame never sees a false edge.
var _was_grounded: bool = false
# Seconds until the next docile call fires (re-rolled after each one).
var _idle_call_timer: float = 0.0
# One-shot startup flag (AGENTS.md appendix: refs may be null in _ready).
var _wired: bool = false


func _ready() -> void:
	# Voice 0 is this node: it is already a spatial player, so events
	# assigned to it emit from the creature's world position.
	_voices.append(self)
	# The remaining voices are spatial children sitting at the local
	# origin, so they inherit this node's transform (and its spatial
	# tuning, copied below).
	for i in voice_count - 1:
		var voice := AudioStreamPlayer2D.new()
		voice.volume_db = volume_db
		voice.bus = bus
		voice.max_distance = max_distance
		voice.attenuation = attenuation
		voice.panning_strength = panning_strength
		add_child(voice)
		_voices.append(voice)
	_idle_call_timer = randf_range(idle_call_interval_min, idle_call_interval_max)


## One-shot startup, on the first idle tick (refs may be null in _ready).
## Seeds the landing tracker from the body's live floor contact so a spawn
## that starts grounded does not read as a touchdown — no startup thud.
func _process(_delta: float) -> void:
	if _wired:
		return
	_wired = true
	set_process(false)
	if npc != null:
		_was_grounded = npc.is_on_floor()


## Plays one of the [enum Event] sounds; silently skips unassigned ones
## and is a no-op for [enum Event.NONE].
func play_event(event: Event) -> void:
	if event == Event.NONE:
		return
	play_stream(_stream_for(event))


## Plays an arbitrary stream on the next pooled spatial voice; null is a
## no-op. If the slot is this node (voice 0) the sound plays from the
## creature's own position; child voices inherit that transform too.
## Escape hatch for future one-off sounds outside the [enum Event] set.
func play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.play()


## Detects the body's own events each frame: touchdown on its floor edge,
## footsteps while grounded and moving, and the docile idle call. Every
## path is null-guarded and silent when [member npc] is unassigned.
func _physics_process(delta: float) -> void:
	if npc == null:
		return
	_update_land()
	_update_steps(delta)
	_update_idle_call(delta)


## LAND: a rising edge on the body's floor contact. The tracker is seeded
## by the one-shot startup (see [method Node._process]); if this tick ever
## runs first (frame order is not fixed), it adopts the live value instead
## of firing, so a grounded spawn can never produce a false thud.
func _update_land() -> void:
	var grounded := npc.is_on_floor()
	if not _wired:
		_was_grounded = grounded
		return
	if grounded and not _was_grounded:
		play_event(Event.LAND)
	_was_grounded = grounded


## STEP: tick while grounded and actually moving; reset when still so a
## new run starts with an immediate step (mirrors [PlayerSfx]).
func _update_steps(delta: float) -> void:
	if not npc.is_on_floor() or absf(npc.velocity.x) <= 1.0:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = footstep_interval
		_play_footstep()


## IDLE_CALL: a re-rolled countdown, fired only while the creature is not
## hunting — silence under threat.
func _update_idle_call(delta: float) -> void:
	_idle_call_timer -= delta
	if _idle_call_timer > 0.0:
		return
	_idle_call_timer = randf_range(idle_call_interval_min, idle_call_interval_max)
	if not npc.aggressive:
		play_event(Event.IDLE_CALL)


func _play_footstep() -> void:
	var streams := sound_footsteps
	if streams.is_empty():
		return
	play_stream(streams[_footstep_index])
	_footstep_index = (_footstep_index + 1) % streams.size()


func _stream_for(event: Event) -> AudioStream:
	match event:
		Event.IDLE_CALL:
			return sound_idle_call
		Event.WARY_WARN:
			return sound_wary_warning
		Event.AGGRO_CRY:
			return sound_aggro_cry
		Event.LAND:
			return sound_land
	return null
