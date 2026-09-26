@icon("res://addons/at-icons/node/chest.svg")
class_name Chest
extends Node2D
## Interactive loot chest: opens on the [b]interact[/b] action while a
## character body stands in its trigger area.
##
## The chest is the first interactive entity, so its contract is the
## project's interaction template: an [Area2D] trigger tracks nearby
## bodies (filtered to [CharacterBody2D] so static tile collision never
## counts), the root polls the input action in its physics step, and
## the open transaction fans out to Sfx, Vfx and the [signal opened]
## signal that the future loot/inventory increment hooks into.
##
## Opening is visually one-way but the chest stays interactable: every
## in-range press re-fires [signal opened], which is what the later
## loot UI will consume. All feedback components degrade silently when
## their references are unassigned, so a bare chest in a test level
## never errors.

## Visual: swapped from the closed texture on open.
@export var sprite: Sprite2D
## Trigger area whose overlap state gates the interact action.
@export var trigger: Area2D
## Event-driven sound source.
@export var sfx: ChestSfx
## One-shot open burst.
@export var vfx: ChestVfx

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
## Whether the interact prompt (created in code) is shown at all.
@export var prompt_enabled: bool = true
## Text of the interact prompt.
@export var prompt_text: String = "E"

## Fired on every in-range interact press while open or closed; the
## loot increment decides what each press yields.
signal opened

# Whether a CharacterBody2D currently overlaps the trigger.
var _in_range: bool = false
# One-time open state; re-presses still re-emit [signal opened].
var _is_open: bool = false
# Code-created floating prompt; hidden until the trigger fires.
var _prompt: Label
# Fade duration for the prompt's show/hide.
var _prompt_fade: float = 0.15


func _ready() -> void:
	_apply_closed_texture()
	_apply_trigger_size()
	_create_prompt()
	if trigger != null:
		trigger.body_entered.connect(_on_body_entered)
		trigger.body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	# Poll the action here, matching the Player's once-per-frame input
	# gather; the trigger state is the only gate.
	if _in_range and Input.is_action_just_pressed("interact"):
		open()


## Runs the open transaction: texture swap, SFX, VFX burst, signal.
func open() -> void:
	if _is_open and texture_open != null and sprite != null:
		# Already open and showing it; re-presses still re-emit.
		opened.emit()
		return
	_is_open = true
	if sprite != null and texture_open != null:
		sprite.texture = texture_open
	if sfx != null:
		sfx.play(ChestSfx.Event.OPEN)
	if vfx != null:
		vfx.pulse()
	opened.emit()


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_in_range = true
		_show_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_in_range = false
		_hide_prompt()


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


## Builds the floating "E" label above the chest, hidden by default.
func _create_prompt() -> void:
	if not prompt_enabled:
		return
	_prompt = Label.new()
	_prompt.text = prompt_text
	_prompt.z_index = 96
	_prompt.position = Vector2(-4.0, -18.0)
	_prompt.modulate.a = 0.0
	add_child(_prompt)


func _show_prompt() -> void:
	if _prompt == null:
		return
	var tween := create_tween()
	tween.tween_property(_prompt, "modulate:a", 1.0, _prompt_fade)


func _hide_prompt() -> void:
	if _prompt == null:
		return
	var tween := create_tween()
	tween.tween_property(_prompt, "modulate:a", 0.0, _prompt_fade)
