@icon("res://addons/at-icons/node/note_double.svg")
extends Node
## Global music player - the [code]Music[/code] autoload.
##
## Plays a continuous sequential rotation of the winning soundtrack: one
## track after another, wrapping forever. Two child voices
## ([member voice_a] / [member voice_b]) alternate so every switch is a
## crossfade, never a seam.
##
## [b]Base vs. interrupts:[/b] scenes announce their base score with a
## [MusicCue] node (a [Soundtrack] resource) via [method play_soundtrack];
## temporary conditions (a chase, an alarm) sit above it as requests:
## [codeblock]
## Music.play_soundtrack(set)  # set the base score (null/empty = silence)
## Music.request(set, priority) # interrupt over the base (higher wins)
## Music.release(set)           # end that interrupt; fall back automatically
## Music.play()                # continue the rotation (no-op if already playing)
## Music.play(3)               # force track 3; rotation continues at 4 afterwards
## Music.stop()                # fade out; forgets base AND all requests
## Music.stop(0.5)             # fade out over 0.5 s
## [/codeblock]
##
## The highest-priority live request plays; with no requests the base
## plays. Requests are refcounted (each request needs one release), a
## base change under an interrupt is recorded but not shown until the
## interrupt releases, and ties resolve to the most recently added
## request. [method stop] is the escape hatch: scene "silence here"
## outranks stale interrupts.
##
## The machinery is generic on purpose - no game code calls
## [method request] yet. Chase-reactive music stays recorded as OPEN in
## DESIGN.md section 8 until a threat system wires it.

## Floor volume used to silence a voice (dB); the audible target is
## [member volume_db].
const SILENCE_DB := -80.0

## One requested soundtrack with its priority and live request count.
class Request:
	extends RefCounted
	var soundtrack: Soundtrack
	var priority: int = 0
	var count: int = 0

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
## Whether playback should be audible (false while fading out).
var _audible: bool = false
## Track most recently started; -1 before the first one.
var _current_index: int = -1
## Rotation pointer: the track [method play] resumes on.
var _next_index: int = 0
## The base score (scene cue / phase system); plays when no request is live.
var _base_set: Soundtrack
## The soundtrack currently playing (the winner of base vs. requests).
var _active_set: Soundtrack
## Live interrupt requests, in creation order.
var _requests: Array[Request] = []
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


## Set the base score; the highest-priority live request (if any) keeps
## the stage until it releases. null or empty means silence here and
## clears all requests (delegates to [method stop]) - a scene's
## "silence here" outranks stale interrupts. No-op when this exact
## soundtrack already won, so scenes sharing one set never interrupt
## each other. Scenes with no cue leave the music untouched.
func play_soundtrack(soundtrack: Soundtrack) -> void:
	if voice_a == null or voice_b == null:
		return
	if soundtrack != null and soundtrack.tracks.is_empty():
		soundtrack = null
	if soundtrack == null:
		stop()
		return
	_base_set = soundtrack
	_sync_to_winner()


## Raise a refcounted interrupt above the base. The highest priority
## wins; equal priorities resolve to the most recently added request.
## Safe to call repeatedly - each call needs one matching
## [method release].
func request(soundtrack: Soundtrack, priority: int = 0) -> void:
	if voice_a == null or voice_b == null:
		return
	if soundtrack == null or soundtrack.tracks.is_empty():
		return
	for existing: Request in _requests:
		if existing.soundtrack == soundtrack:
			existing.count += 1
			existing.priority = maxi(existing.priority, priority)
			_sync_to_winner()
			return
	var entry := Request.new()
	entry.soundtrack = soundtrack
	entry.priority = priority
	entry.count = 1
	_requests.append(entry)
	_sync_to_winner()


## Drop one request for [param soundtrack]; at zero the interrupt ends
## and playback falls back to the next request (or the base, whatever
## it is now - a phase change mid-interrupt is picked up here).
## Releasing a set that is not requested is a harmless no-op.
func release(soundtrack: Soundtrack) -> void:
	if soundtrack == null:
		return
	for index: int in _requests.size():
		if _requests[index].soundtrack == soundtrack:
			_requests[index].count -= 1
			if _requests[index].count <= 0:
				_requests.remove_at(index)
			_sync_to_winner()
			return


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


## Fade every playing voice to silence, forgetting the base and every
## request. [param fade] < 0 uses [member fade_out_time]; 0 stops
## instantly. Safe to call when already silent.
func stop(fade: float = -1.0) -> void:
	_base_set = null
	_requests.clear()
	_active_set = null
	_silence(fade)


## Crossfade to the current winner of base vs. requests (or to silence
## when nothing won).
func _sync_to_winner() -> void:
	var winner := _winner()
	if winner == _active_set and _audible:
		return
	_active_set = winner
	if winner == null:
		_silence()
		return
	if winner.loop and winner.tracks.size() > 1:
		push_warning(
			"Music: Soundtrack '%s' has loop on with %d tracks - loop ignored."
			% [winner.resource_path, winner.tracks.size()]
		)
	_rotation = winner.tracks
	_start_track(0)


## The live request with the highest priority (ties: most recently
## added); the base when no requests are live.
func _winner() -> Soundtrack:
	var best: Request = null
	for entry: Request in _requests:
		if best == null or entry.priority >= best.priority:
			best = entry
	return best.soundtrack if best != null else _base_set


## Fade every playing voice to silence without touching state.
func _silence(fade: float = -1.0) -> void:
	_kill_tween()
	_audible = false
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


## Fade-out done: everything silent, ready for a fresh start.
func _on_stop_finished() -> void:
	for voice: AudioStreamPlayer in _voices():
		if voice.playing:
			voice.stop()
	_retire()


## Forget the active voice; the next start plays from scratch.
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
