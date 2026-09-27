class_name ChestLootEntry
extends Resource
## One weighted entry in a chest's loot pool.

## Item rolled when this entry wins.
@export var item: Item
## Relative chance within the pool; zero or below never rolls.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
