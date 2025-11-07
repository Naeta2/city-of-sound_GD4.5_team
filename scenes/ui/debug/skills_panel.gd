extends Control

@onready var agent_id_edit: LineEdit = $VBoxContainer/AgentIdEdit
@onready var skill_edit: LineEdit = $VBoxContainer/SkillEdit
@onready var minutes_spin: SpinBox = $VBoxContainer/MinutesSpin
@onready var out: Label = $VBoxContainer/Out

func _ready():
	SkillsService.connect("skill_changed", Callable(self, "_on_skill_changed"))
	SkillsService.connect("practiced", Callable(self, "_on_practiced"))

func _on_practice_btn_pressed() -> void:
	var ag := StringName(agent_id_edit.text.strip_edges())
	var sk := StringName(skill_edit.text.strip_edges())
	var mins := int(minutes_spin.value)
	if str(ag).is_empty() or str(sk).is_empty():
		out.text = "Renseigne agent_id et skill."
		return
	var before := AgentRepo.get_ag_skill(ag, sk)
	SkillsService.practice(ag, sk, mins, 1.0)
	var after := AgentRepo.get_ag_skill(ag, sk)
	out.text = "Practice %s %d min: %.3f → %.3f" % [sk, mins, before, after]

func _on_skill_changed(agent_id, skill, value):
	# simple log
	print("skill_changed", agent_id, skill, value)

func _on_practiced(agent_id, skill, minutes, gain):
	print("practiced", agent_id, skill, minutes, gain)
