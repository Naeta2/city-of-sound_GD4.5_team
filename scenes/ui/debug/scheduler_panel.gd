extends Control

@onready var clock: Label = $VBoxContainer/ClockLabel
@onready var agent_id_edit: LineEdit = $VBoxContainer/AgentIdEdit
@onready var skill_edit: LineEdit = $VBoxContainer/SkillEdit
@onready var start_in_spin: SpinBox = $VBoxContainer/StartInMinSpin
@onready var duration_spin: SpinBox = $VBoxContainer/DurationSpin
@onready var list: ItemList = $VBoxContainer/UpcomingList

var venue_id: StringName

func _ready() -> void:
	TimeService.connect("time_minute", Callable(self, "_on_minute"))
	Scheduler.connect("events_changed", Callable(self, "_refresh_list"))
	Scheduler.connect("event_fired", Callable(self, "_on_fired"))
	SaveService.connect("load_done", Callable(self, "_on_load_done"))
	
	_on_minute(TimeService.abs_minutes)

func _on_load_done(_path:String, ok:bool) -> void:
	if ok:
		_refresh_list()
	else:
		push_error("Échec du chargement")

func _on_minute(_now:int) -> void:
	clock.text = TimeService.format_d_hhmm()

func _on_schedule_btn_pressed() -> void:
	var ag := StringName(agent_id_edit.text.strip_edges())
	if str(ag).is_empty():
		clock.text = "Set agent_id first"
		return
	var start := TimeService.abs_minutes + int(start_in_spin.value)
	var ev := {
		"id": IdService.new_id("ev"),
		"owner_id": ag,
		"type": "practice",
		"start": start,
		"status": "scheduled",
		"payload": {
			"skill": StringName(skill_edit.text.strip_edges()),
			"minutes": int(duration_spin.value)
		}
	}
	Scheduler.schedule(ev)
	_refresh_list()

func _refresh_list():
	list.clear()
	for ev in Scheduler.upcoming():
		var start := int(ev.get("start", 0))
		var md := start % (24*60)
		var h := int(md / 60)
		var m := int(md % 60)
		list.add_item("%02d:%02d %s (%s) %s" % [h, m, String(ev.type), String(ev.owner_id), ev.get("status", "scheduled")])

func _on_fired(ev:Dictionary):
	print("Event fired:", ev)

func _on_sched_gig_btn_pressed() -> void:
	var ag := StringName(agent_id_edit.text.strip_edges())
	if str(ag).is_empty():
		clock.text = "Set agent_id first"
		return
	var start := TimeService.abs_minutes + int(start_in_spin.value)
	var ev := {
		"id": IdService.new_id("ev"),
		"owner_id": ag,
		"type": "gig",
		"start": start,
		"requires_presence": true,
		"status": "scheduled",
		"payload": {
			"place_id": venue_id,
			"skill": StringName(skill_edit.text.strip_edges()),
			"minutes": int(duration_spin.value),
			"from_agent_account_id": PlaceRepo.get_place(venue_id)["meta"]["account_id"],
			"to_agent_account_id": AgentRepo.ag_get(ag)["account_id"],
			"payout": 50
		}
	}
	Scheduler.schedule(ev)
	_refresh_list()

func _on_tp_to_venue_btn_pressed() -> void:
	var ag_id := StringName(agent_id_edit.text.strip_edges())
	if str(ag_id).is_empty():
		clock.text = "Set agent_id first"
		return
	PresenceService.set_location(ag_id, &"venue:petit_club")

func _on_eat_btn_pressed() -> void:
	var ag := StringName(agent_id_edit.text.strip_edges())
	if str(ag).is_empty():
		clock.text = "Set agent_id first"
		return
	Scheduler.schedule_eat(ag, TimeService.abs_minutes + 10, 30.0, false)

func _on_sleep_btn_pressed() -> void:
	var ag := StringName(agent_id_edit.text.strip_edges())
	if str(ag).is_empty():
		clock.text = "Set agent_id first"
		return
	var HOME := &"place:home/alice"
	PresenceService.set_location(ag, HOME)
	Scheduler.schedule_sleep(ag, TimeService.abs_minutes, 6*60, true, HOME)
