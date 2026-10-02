extends Control
## Colony screen: read-only run report and the hub that sets out.
##
## Reads the [code]GameFlow[/code] autoload's day and stockpile on entry
## (state outlives scene changes, so a fresh read per visit is always
## correct), then offers Set Out for the day's scavenge and a way back
## to the title.

## Day + stockpile report, rebuilt on every visit.
@export var status_report: RichTextLabel
## Loads the scavenge level and starts the day.
@export var set_out_button: Button
## Returns to the title screen.
@export var quit_button: Button
## Resources listed in the stockpile report, in display order; counts
## come from GameFlow, these only supply order and display names.
@export var stockpile_items: Array[Item] = []


func _ready() -> void:
	status_report.text = _build_report()
	set_out_button.pressed.connect(_on_set_out_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _build_report() -> String:
	var lines: Array[String] = []
	lines.append(tr("COLONY_DAY") % GameFlow.day)
	lines.append("")
	for item: Item in stockpile_items:
		lines.append("%s: %d" % [tr(item.name_key), int(GameFlow.stockpile.get(item.id, 0))])
	if GameFlow.haul_banked:
		lines.append("")
		lines.append(tr("COLONY_BANKED"))
	return "\n".join(lines)


func _on_set_out_pressed() -> void:
	GameFlow.set_out()


func _on_quit_pressed() -> void:
	GameFlow.go_to_title()
