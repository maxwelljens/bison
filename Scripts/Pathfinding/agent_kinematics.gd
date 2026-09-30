class_name AgentKinematics
extends RefCounted
## Ballistic snapshot of an agent's live physics for one route request.
##
## The four numbers that vary per agent; tile size belongs to the world and
## is injected from the baked grid inside the navigator, so callers never
## need a grid detail. Produced by the body being driven (see
## [method PlatformerBot.kinematics]).

## Launch impulse in px/s (negative = upward).
var jump_velocity: float
## Gravity in px/s².
var gravity: float
## Horizontal run speed in px/s.
var move_speed: float
## Vertical ladder speed in px/s.
var climb_speed: float


## Stores the agent's kinematics; [param p_climb_speed] prices ladder travel.
func _init(
		p_jump_velocity: float,
		p_gravity: float,
		p_move_speed: float,
		p_climb_speed: float = 60.0,
) -> void:
	jump_velocity = p_jump_velocity
	gravity = p_gravity
	move_speed = p_move_speed
	climb_speed = p_climb_speed
