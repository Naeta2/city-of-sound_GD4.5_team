extends Control

@onready var agent_edit: LineEdit = $VBoxContainer/AgentIdEdit
@onready var place_edit: LineEdit = $VBoxContainer/PlaceIdEdit
@onready var depart_spin: SpinBox = $VBoxContainer/DepartInSpin
@onready var dur_spin: SpinBox = $VBoxContainer/DurationSpin
@onready var out: Label = $VBoxContainer/Out

var venue_id : StringName

func _on_schedule_travel_btn_pressed() -> void:
	var ag := StringName(agent_edit.text.strip_edges())
	var dest := venue_id
	if str(ag).is_empty() or str(dest).is_empty():
		out.text = "Needs agent_id and place_id"; return
	var depart_at := TimeService.abs_minutes + int(depart_spin.value)
	#var duration := int(dur_spin.value)
	var ids := Scheduler.schedule_travel(ag, dest, depart_at, PlaceRepo.estimate_travel_minutes(PresenceService.get_location(ag), venue_id))
	out.text = "travel begin=%s end=%s" % [ids["begin_id"], ids["end_id"]]
