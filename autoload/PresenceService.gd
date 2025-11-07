extends Node

signal location_changed(agent_id: StringName, place_id: StringName)

const PLACE_TRANSIT: StringName = &"__transit__"
#PresenceService.get_location(agent_id) == PLACE_TRANSIT -> bool true: in transit false: not in transit

var _where: Dictionary = {} #agent_id -> place_id

func set_location(agent_id: StringName, place_id: StringName):
	_where[agent_id] = place_id
	emit_signal("location_changed", agent_id, place_id)

func get_location(agent_id: StringName) -> StringName:
	return _where.get(agent_id, StringName())

func is_at(agent_id: StringName, place_id: StringName) -> bool:
	return _where.get(agent_id, StringName()) == place_id
