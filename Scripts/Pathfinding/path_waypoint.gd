class_name PathWaypoint
extends RefCounted
## One step of a computed path.
##
## A waypoint names a grid cell and the action the agent performs there.
## Jumps additionally carry their apex so the follower can steer the arc.

## The action performed at this waypoint.
enum Kind {
	## Grounded movement along a run of floor cells.
	WALK,
	## Launch: jump from a standstill or a run.
	JUMP,
	## Touchdown: the airborne run ends here.
	LAND,
	## Unpowered vertical drop from a ledge (no jump impulse).
	FALL,
	## Step down through a one-way platform surface (needs the press-down action).
	DROP_THROUGH,
	## Vertical travel along a ladder chain: grab at the first cell, climb to
	## the last, then top out or step off.
	CLIMB,
}

## Which action this waypoint represents.
var kind: Kind = Kind.WALK

## Grid cell of the waypoint.
var cell: Vector2i = Vector2i.ZERO

## Cell center in world pixels.
var world: Vector2 = Vector2.ZERO

## Highest cell of the jump arc; [code](-1, -1)[/code] when not applicable.
var apex_cell: Vector2i = Vector2i(-1, -1)

## [member apex_cell] center in world pixels; only meaningful when an apex exists.
var apex_world: Vector2 = Vector2.ZERO

## True when the route passes through a one-way surface (drop-through or
## a jump that starts on one-way ground).
var through_oneway: bool = false
