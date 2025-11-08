extends Node

signal agent_created(agent_id: StringName)
signal agent_changed(agenti_id: StringName)

var _agents: Dictionary = {}

func dump() -> Dictionary:
	return {"agents": _agents.duplicate(true)}

func restore(d: Dictionary) -> void:
	_agents = d.get("agents", {}).duplicate(true)
	for id in _agents.keys():
		emit_signal("agent_changed", id)

# -- public API --

func create_agent(agent_name: String) -> StringName:
	var id := IdService.new_id("agent")
	_agents[id] = {
		"id": id,
		"kind" : &"person",
		"name": agent_name,
		"account_id": StringName(),
		"skills": {"guitar": 0.2},
		"needs": {"energy": 70, "hunger": 30},
		"status": &"healthy"
	}
	emit_signal("agent_created", id)
	return id

func ag_get(agent_id: StringName) -> Dictionary:
	return _agents.get(agent_id, {})

func set_ag_name(agent_id: StringName, new_name: String) -> void:
	if not _agents.has(agent_id): return
	_agents[agent_id]["name"] = new_name
	emit_signal("agent_changed", agent_id)

func set_account(agent_id:StringName, account_id:StringName) -> void:
	if not _agents.has(agent_id): return
	_agents[agent_id]["account_id"] = account_id
	emit_signal("agent_changed", agent_id)

func get_ag_skill(agent_id:StringName, skill: StringName) -> float :
	if not _agents.has(agent_id): return 0.0
	return float(_agents[agent_id]["skills"].get(skill, 0.0))

func set_ag_skill(agent_id:StringName, skill: StringName, value: float) -> void:
	if not _agents.has(agent_id): return
	_agents[agent_id]["skills"][skill] = clampf(value,0.0,1.0)
	emit_signal("agent_changed", agent_id)

func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in _agents.keys():
		ids.append(k)
	return ids

func get_ag_need(agent_id: StringName, need: StringName) -> float:
	if not _agents.has(agent_id): return 0.0
	return float(_agents[agent_id]["needs"].get(need,0.0))

func set_ag_need(agent_id: StringName, need: StringName, value: float) -> void:
	if not _agents.has(agent_id): return
	_agents[agent_id]["needs"][need] = clampf(value, 0.0, 100.0)
	emit_signal("agent_changed", agent_id)

func get_ag_status(agent_id: StringName) -> StringName:
	if not _agents.has(agent_id): return &"healthy"
	return StringName(_agents[agent_id].get("status", &"healthy"))

func set_ag_status(agent_id: StringName, status: StringName) -> void:
	if not _agents.has(agent_id): return
	_agents[agent_id]["status"] = status
	emit_signal("agent_changed", agent_id)
