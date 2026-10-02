@icon("res://addons/at-icons/node/note_double.svg")
extends Node
## Global music player - the [code]Music[/code] autoload.
##
## Plays a continuous sequential rotation of the active soundtrack: one
## track after another, wrapping forever. Two child voices
## ([member voice_a] / [member voice_b]) alternate so every switch is a
## crossfade, never a seam.
##
## Scenes declare their score: a [MusicCue] node on the scene root
## announces a [Soundtrack] resource from its [method Node._ready],
## which fires before this node's first-frame autoplay fallback. The
## public surface stays small:
## [codeblock]
## Music.play_soundtrack(set)  # crossfade to a set (null/empty = stop)
## Music.play()                # continue the rotation (no-op if already playing)
## Music.play(3)               # force track 3; rotation continues at 4 afterwards
## Music.stop()                # fade out over fade_out_time
## Music.stop(0.5)             # fade out over 0.5 s
## [/codeblock]
##
## There are no signals and no threat/zone hooks on purpose: callers
## appear when the systems that need them exist. Chase-reactive music
## is recorded as OPEN in DESIGN.md section 8 and is not wired here.

## Floor volume used to silence a voice (dB); the audible target is
## [member volume_db].
const SILENCE_DB := -80.0

@export_category("Refs")
## First crossfade voice; a child of this node, wired in the scene.
@export var voice_a: AudioStreamPlayer
## Second crossfade voice; a child of this node, wired in the scene.
@export var voice_b: AudioStreamPlayer

@export_category("Tracks")
## Fallback rotation, used only when no scene cue announced a
## [Soundtrack] before autoplay's first frame.
@export var tracks: Array[AudioStream] = []
## Begin the fallback rotation on the first frame after boot - skipped
## when a scene cue already announced a soundtrack.
@export var autoplay: bool = true
## Index into [member tracks] the fallback rotation starts on.
@export var start_track: int = 0

@export_category("Transitions")
## Seconds to rise from silence when nothing else is playing (boot).
@export_range(0.0, 10.0, 0.05, "or_greater") var fade_in_time: float = 1.0
## Seconds to fall to silence in [method stop].
@export_range(0.0, 10.0, 0.05, "or_greater") var fade_out_time: float = 1.0
## Seconds to overlap two tracks at a switch.
@export_range(0.0, 10.0, 0.05, "or_greater") var crossfade_time: float = 1.0

@export_category("Output")
## Level written to both voices; the Music bus carries the mix control.
@export var volume_db: float = 0.0:
	set(value):
		volume_db = value
		if _active != null and _audible and not _fade_running():
			_active.volume_db = volume_db

## The voice currently fading up or playing.
var _active: AudioStreamPlayer
## The voice that plays next.
var _idle: AudioStreamPlayer
## The one transition fade in flight, if any.
var _tween: Tween
## Whether playback should be audible (false during [method stop]).
var _audible: bool = false
## Track most recently started; -1 before the first one.
var _current_index: int = -1
## Rotation pointer: the track [method play] resumes on.
var _next_index: int = 0
## The soundtrack announced via [method play_soundtrack], if any.
var _active_set: Soundtrack
## The rotation currently in use: the active soundtrack's tracks, or
## [member tracks] before anything has been announced.
var _rotation: Array[AudioStream] = []


func _ready() -> void:
	_rotation = tracks
	_idle = voice_a
	if voice_a != null:
		voice_a.finished.connect(_on_voice_finished.bind(voice_a))
	if voice_b != null:
		voice_b.finished.connect(_on_voice_finished.bind(voice_b))


## Silence everything before teardown: a stream still playing (or a
## fade still running) when the autoload is freed at exit leaks
## resources and trips ObjectDB warnings on headless runs.
func _exit_tree() -> void:
	_kill_tween()
	for voice: AudioStreamPlayer in _voices():
		voice.stop()


## Autoplay starts on the first frame rather than in [method _ready]:
## exported refs are guaranteed resolved by then (the proven startup
## pattern from AGENTS.md), and a scene cue's _ready has already run -
## so autoplay only fires when nothing announced a soundtrack.
func _process(_delta: float) -> void:
	set_process(false)
	if autoplay and _current_index < 0:
		play(start_track)


## Crossfade the active score to [param soundtrack]. null or empty
## means silence here (delegates to [method stop]). No-op when this
## exact soundtrack is already playing, so scenes sharing one set
## never interrupt each other. Scenes with no cue leave the music
## untouched.
func play_soundtrack(soundtrack: Soundtrack) -> void:
	if voice_a == null or voice_b == null:
		return
	if soundtrack == null or soundtrack.tracks.is_empty():
		_active_set = null
		stop()
		return
	if soundtrack == _active_set and _audible:
		return
	if soundtrack.loop and soundtrack.tracks.size() > 1:
		push_warning(
			"Music: Soundtrack '%s' has loop on with %d tracks - loop ignored."
			% [soundtrack.resource_path, soundtrack.tracks.size()]
		)
	_active_set = soundtrack
	_rotation = soundtrack.tracks
	_start_track(0)


## Start or resume the rotation. [param track] < 0 continues from where
## playback left off; >= 0 forces that track (the rotation carries on
## from the one after it). No-op when the active rotation is empty,
## when refs are unwired, when already audible on the same track, or
## on [param track] < 0 while already audible.
func play(track: int = -1) -> void:
	if _rotation.is_empty() or voice_a == null or voice_b == null:
		return
	if track < 0:
		if _audible:
			return
		track = _next_index
	track = posmod(track, _rotation.size())
	if _audible and track == _current_index:
		return
	_start_track(track)


## Fade every playing voice to silence. [param fade] < 0 uses
## [member fade_out_time]; 0 stops instantly. Safe to call when already
## silent. Forgets the active soundtrack, so a later cue or [method play]
## starts fresh.
func stop(fade: float = -1.0) -> void:
	_kill_tween()
	_audible = false
	_active_set = null
	var fading := _playing()
	if fading.is_empty():
		_retire()
		return
	var duration := fade_out_time if fade < 0.0 else fade
	if duration <= 0.0:
		for voice: AudioStreamPlayer in fading:
			voice.stop()
		_retire()
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	for voice: AudioStreamPlayer in fading:
		_tween.tween_property(voice, "volume_db", SILENCE_DB, duration)
	_tween.finished.connect(_on_stop_finished, CONNECT_ONE_SHOT)


## Play [param index] on the idle voice, fading it up while every other
## playing voice fades down; then retire the leftovers. Applies the
## active soundtrack's loop flag to the stream (single-track sets only).
func _start_track(index: int) -> void:
	index = posmod(index, _rotation.size())
	var incoming: AudioStreamPlayer = _idle if _idle != null else voice_a
	var switching := _active != null
	_kill_tween()
	var stream := _rotation[index]
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = (
			_active_set != null and _active_set.loop and _rotation.size() == 1
		)
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()
	_current_index = index
	_next_index = posmod(index + 1, _rotation.size())
	_active = incoming
	_idle = voice_b if incoming == voice_a else voice_a
	_audible = true
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(
		incoming,
		"volume_db",
		volume_db,
		crossfade_time if switching else fade_in_time
	)
	for voice: AudioStreamPlayer in _voices():
		if voice != incoming and voice.playing:
			_tween.tween_property(voice, "volume_db", SILENCE_DB, crossfade_time)
	_tween.finished.connect(_on_fade_finished, CONNECT_ONE_SHOT)


## A voice ended on its own: continue the rotation with the next track.
func _on_voice_finished(voice: AudioStreamPlayer) -> void:
	if voice != _active or not _audible or _rotation.is_empty():
		return
	_start_track(_next_index)


## Crossfade done: silence anything that is neither active nor wanted.
func _on_fade_finished() -> void:
	_tween = null
	for voice: AudioStreamPlayer in _voices():
		if voice != _active and voice.playing:
			voice.stop()


## Stop fade done: everything silent, ready for a fresh start.
func _on_stop_finished() -> void:
	for voice: AudioStreamPlayer in _voices():
		if voice.playing:
			voice.stop()
	_retire()


## Forget the active voice; the next [method play] starts from scratch.
func _retire() -> void:
	_tween = null
	_active = null
	_idle = voice_a


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _fade_running() -> bool:
	return _tween != null and _tween.is_valid()


func _voices() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	if voice_a != null:
		out.append(voice_a)
	if voice_b != null:
		out.append(voice_b)
	return out


func _playing() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for voice: AudioStreamPlayer in _voices():
		if voice.playing:
			out.append(voice)
	return out
