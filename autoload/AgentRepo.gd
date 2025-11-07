extends Node

signal agent_created(agent_id: StringName)
signal agent_changed(agenti_id: StringName)

var _agents: Dictionary = {}

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
