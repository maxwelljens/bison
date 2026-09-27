class_name Item
extends Resource
## Lootable item definition: identity, presentation and carried weight.
##
## Items are authored as .tres resources so icons and weights can be
## retuned in the editor without code edits. [member name_key] keeps the
## raw Locale key so the UI's automatic translation resolves it.

## Machine id, unique per item type.
@export var id: StringName
## Locale key of the display name, resolved by automatic translation.
@export var name_key: String
## Icon shown in inventory slots.
@export var texture: Texture2D
## Tint applied to [member texture] in inventory slots.
@export var color: Color = Color.WHITE
## Weight added to the haul when carried, in arbitrary units.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
