class_name PathData
extends RefCounted

var found: bool = false
var waypoints: Array[PathWaypoint] = []
var start_cell: Vector2i = Vector2i.ZERO
var goal_cell: Vector2i = Vector2i.ZERO
var cells_explored: int = 0
