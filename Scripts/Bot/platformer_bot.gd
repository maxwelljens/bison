@icon("res://addons/at-icons/node2d/bot.svg")
class_name PlatformerBot
extends CharacterBody2D
## Movement motor for the AI pathfinding bot.
##
## Same platformer mechanics as the player controller (acceleration/friction,
## coyote time, jump buffering, terminal velocity) but driven by plain input
## booleans instead of the input map, so a controller such as
## [BotPathFollower] can steer it. Adds bot-specific capabilities: a
## one-shot launch impulse per jump (for right-sized gap hops), a
## drop-through pulse for stepping down through one-way platforms, and a
## ladder mode mirroring the player's climbs (held up/down grabs, vertical
## climbing, shimmy step-offs, jump-off, and the same chain-top stop rule).

## Collision bit of the project's "One-way" physics layer; masked out while
## climbing so one-way rungs and landings never block a climb.
const ONE_WAY_BIT: int = 2
## TileMapLayer group used to resolve [member tilemap] when unassigned.
const MAP_GROUP := "navigation"

@export_category("Movement")
## Top run speed in px/s.
@export var move_speed: float = 130.0
## Ground acceleration in px/s² toward the target speed.
@export var acceleration: float = 1200.0
## Deceleration in px/s² when no input is held.
@export var friction: float = 1500.0

@export_category("Jump")
## Default jump impulse in px/s (negative = up).
@export var jump_velocity: float = -300.0
## Upward speed kept when the jump is released early, in px/s. A clamp rather
## than the player's multiplier cut, so the bot still rises ~1 tile past the
## path's apex and clears landing lips.
@export var jump_release_speed: float = 120.0
## Seconds after leaving a ledge during which jumping is still allowed.
@export var coyote_time: float = 0.1
## Seconds a jump press before landing is remembered and fired on touchdown.
@export var jump_buffer_time: float = 0.1
## Terminal fall speed in px/s.
@export var max_fall_speed: float = 600.0

## Sprite flipped via `flip_h` to face the movement direction.
@export var sprite: Sprite2D

@export_category("Ladder")
## Vertical climb speed in px/s.
@export var climb_speed: float = 60.0
## TileMapLayer holding the ladder tiles. When unassigned, resolved from the
## `navigation` group on the first grab (same convention as the pathfinder).
@export var tilemap: TileMapLayer

## Input state, written by the controller each physics frame.
var input_left: bool = false
var input_right: bool = false
var input_jump: bool = false
var input_up: bool = false
var input_down: bool = false
## Optional one-shot launch speed in px/s (positive) consumed by the next jump
## instead of [member jump_velocity]; used for matched-impulse gap hops.
var pending_jump_impulse: float = 0.0
## Rung cell currently grabbed while climbing; the shimmy's home column.
var ladder_rung: Vector2i = Vector2i.ZERO

# Gravity read at startup; never hardcoded so tuning stays in project settings.
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_jump_down: bool = false
var _drop_timer: float = 0.0
var _full_collision_mask: int = 0
# Ladder state: world y of the chain's bottom edge and of the climb stop
# (with whether the stop can be stood on), the grabbed rung's centre x,
# and the one-shot tilemap resolution flag.
var _climbing: bool = false
var _run_bottom_y: float = 0.0
var _stop_y: float = 0.0
var _stop_standable: bool = false
var _column_x: float = 0.0
var _tilemap_resolved: bool = false


func _ready() -> void:
	_full_collision_mask = collision_mask


## Gravity in px/s², for ballistic math in the follower.
func get_gravity_strength() -> float:
	return _gravity


## Kinematics snapshot of this bot's live physics for pathfinding requests.
func kinematics() -> AgentKinematics:
	return AgentKinematics.new(jump_velocity, _gravity, move_speed, climb_speed)


## Pulses a drop-through: for [param duration] seconds the collision mask is
## zeroed so the body falls through one-way (and solid) tiles below. A short
## hack; the mask is restored in [method _physics_process].
func drop_through(duration: float = 0.12) -> void:
	_drop_timer = duration


## True while the bot is on a ladder.
func is_climbing() -> bool:
	return _climbing


## Grabs the ladder rung at the body's centre ([param up] intent) or below
## its feet ([param down] intent, descending off a landing above a chain),
## mirroring the player's held-intent grabs. On success enters the climb:
## the chain extents clamp it, and [member ladder_rung] names the rung.
func try_enter_ladder(up: bool) -> bool:
	if _climbing:
		return false
	_resolve_tilemap()
	if tilemap == null:
		return false
	var rungs := _rung_candidates(not up)
	if rungs.is_empty():
		return false
	ladder_rung = rungs[0]
	for cell in rungs:
		if cell.y > ladder_rung.y:
			ladder_rung = cell
	if not up:
		# A descend grab needs room to descend: at the chain's bottom
		# edge there is nothing left to go down, and re-grabbing there
		# would flap the state every frame while the input is held.
		var bottom_y := LadderMap.cell_bottom_y(tilemap,
				LadderMap.run_bottom_cell(tilemap, ladder_rung))
		if bottom_y <= collision_rect_global().end.y + 1.0:
			return false
	var top := LadderMap.run_top_cell(tilemap, ladder_rung)
	_run_bottom_y = LadderMap.cell_bottom_y(tilemap,
			LadderMap.run_bottom_cell(tilemap, ladder_rung))
	_stop_y = LadderMap.cell_top_y(tilemap, top)
	_stop_standable = false
	if LadderMap.has_standable_top(tilemap, top):
		_stop_standable = true
	elif LadderMap.has_standable_top(tilemap, top + Vector2i.UP):
		_stop_y = LadderMap.cell_top_y(tilemap, top + Vector2i.UP)
		_stop_standable = true
	_column_x = tilemap.to_global(tilemap.map_to_local(ladder_rung)).x
	velocity = Vector2.ZERO
	_climbing = true
	return true


## Global rectangle of the collision shapes (shape transforms included).
func collision_rect_global() -> Rect2:
	var rect := Rect2()
	var empty := true
	for owner_id in get_shape_owners():
		var xform: Transform2D = shape_owner_get_transform(owner_id)
		for index in range(shape_owner_get_shape_count(owner_id)):
			var shape := shape_owner_get_shape(owner_id, index)
			if shape == null:
				continue
			var shape_rect: Rect2 = xform * shape.get_rect()
			if empty:
				rect = shape_rect
				empty = false
			else:
				rect = rect.merge(shape_rect)
	return global_transform * rect


## The tilemap cell holding the surface under the body's feet.
func ladder_cell_under_feet() -> Vector2i:
	var rect := collision_rect_global()
	return tilemap.local_to_map(tilemap.to_local(
			Vector2(rect.get_center().x, rect.end.y)))


## The ladder cell the body's centre currently occupies (the rung in use).
func ladder_cell() -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(collision_rect_global().get_center()))


func _physics_process(delta: float) -> void:
	if _drop_timer > 0.0:
		_drop_timer -= delta
		collision_mask = 0
	elif _climbing:
		collision_mask = _full_collision_mask & ~ONE_WAY_BIT
	else:
		collision_mask = _full_collision_mask

	var jump_pressed := input_jump and not _was_jump_down
	var jump_released := _was_jump_down and not input_jump
	_was_jump_down = input_jump

	if _climbing:
		_climb_physics(delta, jump_pressed)
		return
	if (input_up or input_down) and try_enter_ladder(input_up):
		_climb_physics(delta, jump_pressed)
		return

	var on_floor := is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		velocity.y = minf(velocity.y + _gravity * delta, max_fall_speed)

	if jump_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		# One-shot matched impulse overrides the default jump velocity.
		velocity.y = -pending_jump_impulse if pending_jump_impulse > 0.0 else jump_velocity
		pending_jump_impulse = 0.0
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if jump_released and velocity.y < -jump_release_speed:
		velocity.y = -jump_release_speed

	var direction := 0.0
	if input_left:
		direction -= 1.0
	if input_right:
		direction += 1.0
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()


## One ladder frame: a pressed jump jumps off (one-shot impulse or the full
## [member jump_velocity]), otherwise up/down climb (0 = hang) and
## left/right shimmies along the rung tile at run speed. The chain edges
## clamp the feet: the climb stop stands the bot up on a real surface,
## sinking past the chain's bottom edge or shimmying out of the rung tile
## steps off into a free fall.
func _climb_physics(delta: float, jump_pressed: bool) -> void:
	if jump_pressed:
		velocity.y = -pending_jump_impulse if pending_jump_impulse > 0.0 else jump_velocity
		pending_jump_impulse = 0.0
		_climbing = false
		move_and_slide()
		return
	var vertical := 0.0
	if input_up:
		vertical += 1.0
	if input_down:
		vertical -= 1.0
	velocity.y = -vertical * climb_speed
	var direction := 0.0
	if input_left:
		direction -= 1.0
	if input_right:
		direction += 1.0
	velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
	if direction != 0.0:
		sprite.flip_h = direction < 0.0
	move_and_slide()
	var half_tile := tilemap.tile_set.tile_size.x * 0.5
	if absf(global_position.x - _column_x) > half_tile:
		velocity.y = 0.0
		_climbing = false
		return
	var slack := climb_speed * delta
	var feet_y := collision_rect_global().end.y
	if vertical > 0.0 and feet_y <= _stop_y + slack:
		global_position.y += _stop_y - feet_y
		velocity.y = 0.0
		if _stop_standable:
			_climbing = false
	elif vertical < 0.0 and feet_y >= _run_bottom_y - slack:
		_climbing = false


## Ladder cells for a grab attempt: the cell holding the body's centre, plus
## the cell below the feet for descending off an unflagged landing above a
## chain. Mirrors the player's candidates.
func _rung_candidates(down_intent: bool) -> Array[Vector2i]:
	var rungs: Array[Vector2i] = []
	var centre := ladder_cell()
	if LadderMap.is_ladder_cell(tilemap, centre):
		rungs.append(centre)
	if down_intent:
		var below := ladder_cell_under_feet() + Vector2i.DOWN
		if LadderMap.is_ladder_cell(tilemap, below) and not rungs.has(below):
			rungs.append(below)
	return rungs


## Resolves [member tilemap] from the [constant MAP_GROUP] group once, so a
## dropped-in bot works without scene wiring.
func _resolve_tilemap() -> void:
	if tilemap != null or _tilemap_resolved:
		return
	_tilemap_resolved = true
	for candidate in get_tree().get_nodes_in_group(MAP_GROUP):
		if candidate is TileMapLayer:
			tilemap = candidate
			return
