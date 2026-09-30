class_name PathTuning
extends Resource
## Search and steering knobs for [PlatformerNavigator].
##
## One Inspector-editable value object shared by reference between the
## pathfinder node and its navigator, so edits take effect on the next query
## with no sync step. Script defaults match the historical node defaults.

@export_category("Search")
## Extra edge cost per jump-value unit; punishes staying high and airborne.
@export var air_penalty: float = 0.25
## Weighted-A* factor on the heuristic; > 1 trades optimality for speed.
@export var heuristic_weight: float = 1.0
## Max downward cells the goal may snap to standable ground.
@export var goal_snap_max_cells: int = 8
## Search budget in expanded states before giving up.
@export var max_expansions: int = 20000
## Skip states that a strictly more capable state at the same cell dominates.
@export var use_dominance_pruning: bool = true
## Cost of grabbing, topping out of or stepping off a ladder, in walk cells.
@export var climb_grab_cost: float = 0.5

@export_category("Drift guard")
## Padding above the higher drift-check point in px (body headroom).
@export var drift_pad_top: float = 3.0
## Padding below the lower drift-check point in px (body height).
@export var drift_pad_bottom: float = 7.0
