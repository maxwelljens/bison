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
## Max rows below the request the goal snap gathers standable candidates
## from (cells).
@export var goal_snap_max_cells: int = 8
## Max columns left/right of the request the goal snap gathers standable
## candidates from (cells); together with [member goal_snap_max_cells] this
## bounds the candidate box.
@export var goal_snap_side_cells: int = 8
## Vertical-distance weight of the goal snap relative to one horizontal
## cell (unitless, only the ratio matters). Values > 1 prefer a landing lip
## near the request's height over a floor far below, so a goal over a gap
## resolves sideways — or is refused — instead of diving into the chasm.
@export var goal_snap_vertical_weight: float = 3.0
## Search budget in expanded states before giving up.
@export var max_expansions: int = 20000
## Skip states that a strictly more capable state at the same cell dominates.
@export var use_dominance_pruning: bool = true
## Cost of grabbing, topping out of or stepping off a ladder, in walk cells.
@export var climb_grab_cost: float = 0.5

@export_category("Drift guard")
## Planned arcs assume the takeoff reaches at least this fraction of
## move_speed; ≤ 1 conservatises the envelope for momentum-weighted agents
## (their weighted acceleration may not have built full run speed by the
## lip, so an envelope planned at full speed would promise drift they
## cannot execute).
@export_range(0.5, 1.0, 0.01) var takeoff_speed_factor: float = 0.85
## Padding above the higher drift-check point in px (body headroom).
@export var drift_pad_top: float = 3.0
## Padding below the lower drift-check point in px (body height).
@export var drift_pad_bottom: float = 7.0
