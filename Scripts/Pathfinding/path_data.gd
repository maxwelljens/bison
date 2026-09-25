class_name PathData
extends RefCounted
## Result bundle of a path search.
##
## Returned by [PlatformerPathfinder] to describe the outcome of one query:
## whether a route was found, the waypoints to follow, and a small diagnostic
## of the search itself.

## Whether a route from [member start_cell] to [member goal_cell] exists.
var found: bool = false

## Ordered steps of the route; empty when [member found] is false.
var waypoints: Array[PathWaypoint] = []

## Grid cell the search started from (after goal snapping adjustments).
var start_cell: Vector2i = Vector2i.ZERO

## Grid cell the search targeted (after goal snapping adjustments).
var goal_cell: Vector2i = Vector2i.ZERO

## Diagnostic: how many (cell, jump-value) states the search expanded.
var cells_explored: int = 0
