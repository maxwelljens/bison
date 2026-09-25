class_name PathWaypoint
extends RefCounted

enum Kind { WALK, JUMP, LAND, FALL, DROP_THROUGH }

var kind: Kind = Kind.WALK
var cell: Vector2i = Vector2i.ZERO
var world: Vector2 = Vector2.ZERO
var apex_cell: Vector2i = Vector2i(-1, -1)
var apex_world: Vector2 = Vector2.ZERO
var through_oneway: bool = false
