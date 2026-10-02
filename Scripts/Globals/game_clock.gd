extends Node
## Owns the colony day clock: 06:00 → 21:00, one game-hour per
## [member seconds_per_game_hour] real seconds (40 s ⇒ a 15 h day in
## 10 real minutes). Time advances only while [member running].
##
## At the day's end the time clamps exactly to [constant DAY_END_HOUR],
## the clock stops itself and [signal dusk_reached] fires once - being
## lethal, swapping scores or greying the HUD is the subscribers' job,
## not this node's. A [code]class_name[/code] is deliberately omitted so
## it cannot collide with the [code]GameClock[/code] autoload name.

## Emitted whenever the day phase changes (see [enum Phase]).
signal phase_changed(phase: Phase)
## Emitted exactly once per day, when the clock clamps to [constant DAY_END_HOUR].
signal dusk_reached

## Broad day phases, driven by [member warning_at_hour] and the day's end.
enum Phase { DAY, WARNING, DUSK }

## Real seconds that make up one in-game hour.
@export var seconds_per_game_hour: float = 40.0
## Clock hour at which [constant Phase.DAY] escalates to [constant Phase.WARNING].
@export var warning_at_hour: float = 20.0

## Absolute clock hour the day starts at.
const DAY_START_HOUR: float = 6.0
## Absolute clock hour the day ends at (dusk).
const DAY_END_HOUR: float = 21.0

## Current day phase.
var phase: Phase = Phase.DAY
## Whether time is currently advancing.
var running: bool = false

# Game minutes elapsed since 06:00.
var _day_minutes: float = 0.0


func _process(delta: float) -> void:
	if not running:
		return
	_day_minutes += delta * (60.0 / seconds_per_game_hour)
	if current_hour() >= DAY_END_HOUR:
		_day_minutes = (DAY_END_HOUR - DAY_START_HOUR) * 60.0
		running = false
		_set_phase(Phase.DUSK)
		dusk_reached.emit()
	elif phase == Phase.DAY and current_hour() >= warning_at_hour:
		_set_phase(Phase.WARNING)


## Absolute clock hour as a float (e.g. 14.5 = 14:30).
func current_hour() -> float:
	return DAY_START_HOUR + _day_minutes / 60.0


## Bare 24-hour "HH:MM" with leading zeros; clamps to "21:00".
func clock_text() -> String:
	var total_minutes: int = int(round(_day_minutes))
	var hour_offset: int = int(float(total_minutes) / 60.0)
	var hour: int = int(DAY_START_HOUR) + hour_offset
	var minute: int = total_minutes - hour_offset * 60
	return "%02d:%02d" % [hour, minute]


## Reset to 06:00 and start advancing. Force-emits the DAY phase so a
## scene reload after a dusk-phase death resets the graphic and unfreezes.
func start_day() -> void:
	_day_minutes = 0.0
	running = true
	_set_phase(Phase.DAY)


## Stop advancing time without changing the phase (death freeze).
func stop_clock() -> void:
	running = false


func _set_phase(next: Phase) -> void:
	phase = next
	phase_changed.emit(phase)
