extends Node

signal agent_created(agent_id: StringName)
signal agent_changed(agent_id: StringName)

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
		"status": &"healthy",
		"roles": {}
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

#-- orgs

func create_org(org_name: String) -> StringName:
	var id := IdService.new_id("org")
	_agents[id] = {
		"id":id,
		"kind":&"org",
		"name":org_name,
		"account_id": StringName(),
		"skills": {},
		"needs": {},
		"status": &"healthy",
		"roles": {}, #A ->org: map org_id -> role (person side)
		"members": {} #org -> A: map agent_id->role (org side)
	}
	emit_signal("agent_created", id)
	return id

func is_org(agent_id: StringName) -> bool:
	var a := ag_get(agent_id)
	return not a.is_empty() and StringName(a.get("kind", &"")) == &"org"

#role of A in org
func set_role(agent_id: StringName, org_id: StringName, role: StringName) -> void:
	if not _agents.has(agent_id): return
	if not _agents.has(org_id): return
	#person side
	var pa = _agents[agent_id]
	var roles = pa.get("roles", {})
	roles[org_id] = role
	pa["roles"] = roles
	_agents[agent_id] = pa
	emit_signal("agent_changed", agent_id)
	#org side
	var oa = _agents[org_id]
	var mem = oa.get("members", {})
	mem[agent_id] = role
	oa["members"] = mem
	_agents[org_id] = oa
	emit_signal("agent_changed", org_id)

func get_role(agent_id: StringName, org_id:StringName) -> StringName:
	var a := ag_get(agent_id)
	var roles = a.get("roles", {})
	return StringName(roles.get(org_id, StringName()))

func get_org_members(org_id: StringName) -> Dictionary:
	var org := ag_get(org_id)
	return org.get("members", {}) #agent_id : role

func set_org_owner(org_id: StringName, owner_agent_id: StringName) -> void:
	set_role(owner_agent_id, org_id, &"owner")

#helpers

func find_agent_by_account(account_id:StringName) -> StringName:
	for id in _agents.keys():
		var a = _agents[id]
		if StringName(a.get("account_id", StringName())) == account_id:
			return id
	return StringName()
