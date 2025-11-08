extends Node

signal location_changed(agent_id: StringName, place_id: StringName)

const ALLOW_UNKNOWN_PLACES := true

const PLACE_TRANSIT: StringName = &"__transit__"
#PresenceService.get_location(agent_id) == PLACE_TRANSIT -> bool true: in transit false: not in transit

var _where: Dictionary = {} #agent_id -> place_id

func dump() -> Dictionary:
	return {"where": _where.duplicate()}

func restore(d: Dictionary) -> void:
	_where.clear()
	var w = d.get("where", {})
	for k in w.keys():
		_where[StringName(k)] = StringName(w[k])
		emit_signal("location_changed", StringName(k), StringName(w[k]))

func set_location(agent_id: StringName, place_id: StringName):
	if place_id != PLACE_TRANSIT:
		var exists := false
		if Engine.has_singleton("PlaceRepo"):
			var p := PlaceRepo.get_place(place_id)
			exists = not p.is_empty()
		if not exists:
			if ALLOW_UNKNOWN_PLACES:
				push_warning("PresenceService: unknown place_id '%s' (allowed)" % str(place_id))
			else :
				push_error("PresenceService: unknown place_id '%s' (rejected)" % str(place_id))
				return
	_where[agent_id] = place_id
	emit_signal("location_changed", agent_id, place_id)

func get_location(agent_id: StringName) -> StringName:
	return _where.get(agent_id, StringName())

func is_at(agent_id: StringName, place_id: StringName) -> bool:
	return _where.get(agent_id, StringName()) == place_id

func place_exists(place_id: StringName) -> bool:
	if place_id == PLACE_TRANSIT : return true
	if not Engine.has_singleton("PlaceRepo"): return false
	return not PlaceRepo.get_place(place_id).is_empty()
