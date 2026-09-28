@icon("res://addons/at-icons/node/chest.svg")
class_name Chest
extends Node2D
## Interactive loot chest: opens on the [b]interact[/b] action while the
## player stands in its trigger area, then rummages its contents open.
##
## The chest is the first interactive entity, so its contract is the
## project's interaction template: an [Area2D] trigger tracks the
## [Player] (so no other body fakes proximity), the root polls the input
## action in its physics step, and the open transaction fans out to Sfx,
## Vfx, the [signal opened] signal and the [Loot] autoload session the
## HUD listens to.
##
## Opening rolls [member loot_pool] once; the rolled items then buffer
## in one at a time over [member rummage_time] while the player is in
## range (leaving pauses mid-item, returning resumes). Revealed items
## are takeable through the [Loot] autoload. Every in-range press
## re-fires [signal opened]; when the screen is already up, the press
## closes it instead (toggle). All feedback
## components degrade silently when their references are unassigned, so
## a bare chest in a test level never errors.
## Visual: swapped from the closed texture on open.
@export var sprite: Sprite2D
## Trigger area whose overlap state gates the interact action.
@export var trigger: Area2D
## Event-driven sound source.
@export var sfx: ChestSfx
## One-shot open burst.
@export var vfx: ChestVfx
## Interact prompt laid out in the scene; faded in/out by the chest.
@export var prompt: ChestPrompt

@export_category("Appearance")
## Shown while closed; falls back to the sprite's own texture when
## unassigned.
@export var texture_closed: Texture2D
## Shown once opened; null keeps the closed look until real art is
## assigned.
@export var texture_open: Texture2D

@export_category("Trigger")
## Size of the trigger rectangle, in px.
@export var trigger_size: Vector2 = Vector2(24.0, 20.0):
	set(value):
		trigger_size = value
		_apply_trigger_size()

@export_category("Prompt")
## Fade duration for the prompt's show/hide, in s.
@export_range(0.0, 1.0, 0.01, "suffix:s") var prompt_fade: float = 0.15

@export_category("Loot")
## Weighted pool rolled on first open; duplicates are allowed.
@export var loot_pool: Array[ChestLootEntry] = []
## Number of items rolled on first open.
@export_range(1, 32) var roll_count: int = 4
## Total seconds to reveal every rolled item, split evenly across them.
@export_range(0.1, 30.0, 0.1, "suffix:s") var rummage_time: float = 3.0

## Fired on every in-range interact press while open or closed; the
## loot session re-presents the screen on each press.
signal opened
## Fired when the visible item list changes (roll, reveal, take, return).
signal contents_changed
## Fired every physics tick while the active item buffers in, 0..1.
signal reveal_progress_changed(progress: float)

# Whether the Player currently overlaps the trigger.
var _in_range: bool = false
# The Player in the trigger, for the controls gate on the interact poll.
var _player: Player
# One-time open state; re-presses still re-emit [signal opened].
var _is_open: bool = false
# Rolled items still buffering in, in reveal order; the head is next.
var _pending: Array[Item] = []
# Revealed items, takeable by the player.
var _revealed: Array[Item] = []
# Whether the one-time content roll already happened.
var _rolled: bool = false
# Seconds one reveal slot takes; fixed when the contents roll.
var _slot_duration: float = 0.0
# Fill of the current reveal slot, 0..1.
var _slot_progress: float = 0.0


func _ready() -> void:
	_apply_closed_texture()
	_apply_trigger_size()
	_apply_prompt_hidden()
	if trigger != null:
		trigger.body_entered.connect(_on_body_entered)
		trigger.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	# Poll the action here, matching the Player's once-per-frame input
	# gather; the trigger state and the player's control lockout (stun,
	# death) are the gates.
	if _in_range and _player != null and _player.controls_enabled() \
			and Input.is_action_just_pressed("interact"):
		_handle_interact()
	_tick_rummage(delta)


## Runs the open transaction: texture swap, SFX, VFX burst, one-time
## loot roll, signal. Re-presses only re-emit [signal opened] and
## re-present the loot screen; pressing E while this chest owns the
## session closes the screen again.
func open() -> void:
	if not _is_open:
		_is_open = true
		if sprite != null and texture_open != null:
			sprite.texture = texture_open
		_set_prompt_loot_text()
		if sfx != null:
			sfx.play(ChestSfx.Event.OPEN)
		if vfx != null:
			vfx.pulse()
		if not _rolled:
			_roll_contents()
			contents_changed.emit()
	else:
		if sfx != null:
			sfx.play(ChestSfx.Event.REOPEN)
	opened.emit()
	Loot.open_session(self)


## Interact press: toggles the loot screen; the first press runs the
## open transaction, further presses close and re-open it.
func _handle_interact() -> void:
	if _is_open and Loot.session == self:
		if sfx != null:
			sfx.play(ChestSfx.Event.CLOSE)
		Loot.close_session(self)
	else:
		open()


## Revealed items currently in the chest, takeable by the player.
func revealed_items() -> Array[Item]:
	return _revealed.duplicate()


## Items still buffering in, in reveal order.
func pending_items() -> Array[Item]:
	return _pending.duplicate()


## Fill of the currently buffering item, 0..1.
func slot_progress() -> float:
	return _slot_progress


## Removes one revealed instance of the item; false when not takeable.
func take_item(item: Item) -> bool:
	var index := _revealed.find(item)
	if index == -1:
		return false
	_revealed.remove_at(index)
	if sfx != null:
		sfx.play(ChestSfx.Event.TAKEN)
	contents_changed.emit()
	return true


## Puts a taken item back in, already revealed (no re-rummage).
func return_item(item: Item) -> void:
	_revealed.append(item)
	if sfx != null:
		sfx.play(ChestSfx.Event.RETURNED)
	contents_changed.emit()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_in_range = true
		_player = body as Player
		_show_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_in_range = false
		_player = null
		_hide_prompt()
		Loot.close_session(self)


## Writes the closed texture onto the sprite; keeps the sprite's own
## texture when no closed texture was assigned.
func _apply_closed_texture() -> void:
	if texture_closed != null and sprite != null:
		sprite.texture = texture_closed


## Pushes the exported size into the trigger's collision shape.
func _apply_trigger_size() -> void:
	if trigger == null:
		return
	var shape_node := trigger.get_child(0) as CollisionShape2D
	if shape_node == null:
		return
	var shape := shape_node.shape as RectangleShape2D
	if shape == null:
		return
	shape.size = trigger_size


## Switches the prompt description to the loot phase, fired when the
## chest physically opens.
func _set_prompt_loot_text() -> void:
	if prompt == null:
		return
	prompt.set_text("INFO_LOOT")


## Starts the prompt fully faded out so it is invisible until the
## trigger fires.
func _apply_prompt_hidden() -> void:
	if prompt == null:
		return
	prompt.modulate.a = 0.0
	prompt.visible = false


func _show_prompt() -> void:
	if prompt == null:
		return
	prompt.visible = true
	var tween := create_tween()
	tween.tween_property(prompt, "modulate:a", 1.0, prompt_fade)


func _hide_prompt() -> void:
	if prompt == null:
		return
	var tween := create_tween()
	tween.tween_property(prompt, "modulate:a", 0.0, prompt_fade)
	tween.tween_callback(prompt.hide)


## Rolls [member roll_count] items from the weighted pool on first
## open; duplicates are allowed and the roll order doubles as the
## reveal order.
func _roll_contents() -> void:
	_rolled = true
	_pending.clear()
	_revealed.clear()
	var pool: Array[ChestLootEntry] = []
	for entry: ChestLootEntry in loot_pool:
		if entry != null and entry.item != null and entry.weight > 0.0:
			pool.append(entry)
	var total_weight := 0.0
	for entry: ChestLootEntry in pool:
		total_weight += entry.weight
	if total_weight <= 0.0:
		return
	_slot_duration = rummage_time / float(roll_count)
	for i in roll_count:
		var roll := randf() * total_weight
		for entry: ChestLootEntry in pool:
			roll -= entry.weight
			if roll <= 0.0:
				_pending.append(entry.item)
				break


## Advances the head reveal while the player is in range and the loot
## screen is up; leaving the trigger or pressing E to close the screen
## pauses it mid-item, either coming back resumes (DESIGN.md
## pause-on-leave).
func _tick_rummage(delta: float) -> void:
	if not _is_open or not _in_range or Loot.session != self or _pending.is_empty():
		return
	_slot_progress += delta / maxf(_slot_duration, 0.001)
	if _slot_progress >= 1.0:
		_reveal_head()
	else:
		reveal_progress_changed.emit(_slot_progress)


## Completes the head reveal: moves it into the takeable list.
func _reveal_head() -> void:
	_slot_progress = 0.0
	var item: Item = _pending.pop_front()
	_revealed.append(item)
	if sfx != null:
		sfx.play(ChestSfx.Event.REVEALED)
	contents_changed.emit()
