extends Node

signal need_changed(agent_id: StringName, need: StringName, value: float)
signal status_changed(agent_id: StringName, status: StringName)

#-- base settings

const HUNGER_PER_MIN := 0.02
const ENERGY_PER_MIN := -0.03
const REST_GAIN_PER_MIN := 0.5
const EAT_GAIN := 25.0

const PRACTICE_ENERGY_COST_PER_MIN := 0.10
const PRACTICE_HUNGER_COST_PER_MIN := 0.08

# states globals

const HURT_HUNGER := 100.0
const HURT_ENERGY := 0.0
const RECOVER_HUNGER := 90.0
const RECOVER_ENERGY := 20.0

func _ready() -> void:
	TimeService.connect("time_minute", Callable(self, "_on_minute"))

func _on_minute(_abs:int) -> void:
	for ag in AgentRepo.get_all_ids():
		_add_need(ag, &"hunger", HUNGER_PER_MIN)
		_add_need(ag, &"energy", ENERGY_PER_MIN)
		_update_status(ag)

func _add_need(agent_id:StringName, need:StringName, delta:float) -> void :
	var v := AgentRepo.get_ag_need(agent_id, need)
	var nv := clampf(v + delta, 0.0, 100)
	if nv != v:
		AgentRepo.set_ag_need(agent_id, need, nv)
		emit_signal("need_changed", agent_id, need, nv)

func eat(agent_id:StringName, amount:float = EAT_GAIN) -> void:
	var v := AgentRepo.get_ag_need(agent_id, &"hunger")
	var nv := clampf(v - amount, 0.0, 100.0)
	if nv!= v:
		AgentRepo.set_ag_need(agent_id, &"hunger", nv)
		emit_signal("need_changed", agent_id, &"hunger", nv)
		_update_status(agent_id)

func rest(agent_id:StringName, minutes:int) -> void:
	if minutes <= 0: return
	var gain := REST_GAIN_PER_MIN * float(minutes)
	var v := AgentRepo.get_ag_need(agent_id, &"energy")
	var nv := clampf(v + gain, 0.0, 100.0)
	if nv !=v:
		AgentRepo.set_ag_need(agent_id, &"energy", nv)
		emit_signal("need_changed", agent_id, &"energy", nv)
		_update_status(agent_id)

func _update_status(agent_id:StringName) -> void:
	var hunger := AgentRepo.get_ag_need(agent_id, &"hunger")
	var energy := AgentRepo.get_ag_need(agent_id, &"energy")
	var cur := AgentRepo.get_ag_status(agent_id)
	var nxt := cur
	
	if hunger >= HURT_HUNGER or energy <= HURT_ENERGY:
		nxt = &"hurt"
	elif hunger < RECOVER_HUNGER or energy > RECOVER_ENERGY:
		nxt = &"healthy"
	
	if nxt != cur:
		AgentRepo.set_ag_status(agent_id, nxt)
		emit_signal("status_changed", agent_id, nxt)

#-- helpers

func compute_intensity(agent_id:StringName) -> float:
	var energy := AgentRepo.get_ag_need(agent_id, &"energy")
	var hunger := AgentRepo.get_ag_need(agent_id, &"hunger")
	
	var e_factor := lerpf(0.5, 1.5, energy / 100.0)
	var h_malus := lerpf(1.0, 0.8, clampf(hunger / 100.0, 0.0, 1.0))
	return clampf(e_factor * h_malus, 0.25, 2.0)

func apply_activity_cost(agent_id:StringName, minutes:int, effort:float=1.0) -> void:
	if minutes <= 0: return
	var e_delta := - PRACTICE_ENERGY_COST_PER_MIN * minutes * effort
	var h_delta := PRACTICE_HUNGER_COST_PER_MIN * minutes * effort
	_add_need(agent_id, &"energy", e_delta)
	_add_need(agent_id, &"hunger", h_delta)
	_update_status(agent_id)
