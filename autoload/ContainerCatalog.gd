extends Node

const TYPES := {
	#grid containers
	&"pocket_small": {"grid": {"w":3,"h":3}},
	&"backpack_basic": {"grid":{"w":8,"h":6}},
	#specialcontainers
	&"hand": {"holds_hand_required": 1},
	&"two_hands":{"holds_hands_required": 2},
	&"equipped_slot":{"equipped":true}, #holds 1 wearable entry no dgrid
	&"room_infinite": {"infinite": true}
}

func has(type_name: StringName) -> bool:
	return TYPES.has(type_name)

func get_def(type_name: StringName) -> Dictionary:
	if not TYPES.has(type_name):
		push_error("ContainerCatalog: unknown type %s" % type_name)
		return {}
	return TYPES[type_name]
