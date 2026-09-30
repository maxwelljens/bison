class_name AgentKinematics
extends RefCounted
## Ballistic snapshot of an agent's live physics for one route request.
##
## The numbers AND movement capabilities that vary per agent; tile size
## belongs to the world and is injected from the baked grid inside the
## navigator, so callers never need a grid detail. Produced by the body
## being driven (see [method PlatformerBot.kinematics]).

## Launch impulse in px/s (negative = upward).
var jump_velocity: float
## Gravity in px/s².
var gravity: float
## Horizontal run speed in px/s.
var move_speed: float
## Vertical ladder speed in px/s.
var climb_speed: float
## Whether the agent may jump: false prunes every jump-launch edge from the
## search (walks and gravity-driven falls remain).
var can_jump: bool = true
## Whether the agent may use ladders: false prunes every CLIMB edge from the
## search (walking or falling past a chain remains, the chain is never entered).
var can_climb: bool = true
## Whether the agent may drop through one-way platform surfaces: false prunes
## every DROP_THROUGH edge from the search.
var can_drop_through: bool = true


## Stores the agent's kinematics and capabilities; [param p_climb_speed]
## prices ladder travel. Capability parameters default to true so existing
## callers keep full movement without changes.
func _init(
		p_jump_velocity: float,
		p_gravity: float,
		p_move_speed: float,
		p_climb_speed: float = 60.0,
		p_can_jump: bool = true,
		p_can_climb: bool = true,
		p_can_drop_through: bool = true,
) -> void:
	jump_velocity = p_jump_velocity
	gravity = p_gravity
	move_speed = p_move_speed
	climb_speed = p_climb_speed
	can_jump = p_can_jump
	can_climb = p_can_climb
	can_drop_through = p_can_drop_through
