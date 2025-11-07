extends Node

signal skill_changed(agent_id:StringName, skill: StringName, value: float)
signal practiced(agent_id:StringName, skill: StringName, minutes: int, gain: float)

# -- settings

const BASE_GAIN_PER_HOUR := 0.03
const DIMINISHING_START := 0.6
const DIMINISHING_FACTOR := 0.5

var major_influence := { #stub
	&"rythm": {&"guitar": 0.15, &"drums": 0.2},
	&"ear_training": {&"vocals":0.15, &"mixing":0.1}
}

func practice(agent_id:StringName, skill:StringName, minutes:int, intensity:float = 1.0) -> void:
	if minutes <= 0: return
	var cur := AgentRepo.get_ag_skill(agent_id, skill)
	
	var gain := BASE_GAIN_PER_HOUR * (minutes / 60.0) * clampf(intensity, 0.25,2.0)
	
	if cur >= DIMINISHING_START:
		gain *= lerpf(1.0, DIMINISHING_FACTOR, (cur - DIMINISHING_START) / (1.0 - DIMINISHING_START))
	
	for major in major_influence.keys():
		if major_influence[major].has(skill):
			var mval := AgentRepo.get_ag_skill(agent_id, major)
			if mval > 0.0:
				gain *= (1.0 + major_influence[major][skill] * mval)
	
	var newv := clampf(cur + gain, 0.0, 1.0)
	if newv != cur:
		AgentRepo.set_ag_skill(agent_id, skill, newv)
		emit_signal("skill_changed", agent_id, skill, newv)
	
	emit_signal("practiced", agent_id, skill, minutes, gain)
