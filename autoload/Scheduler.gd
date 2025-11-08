class_name SchedulerService

extends Node

signal events_changed()
signal event_fired(ev)
signal event_missed(ev)

const GRACE_MINUTES := 30
const HISTORY_LIMIT := 200

var _events: Array[Dictionary] = [] #ev = {id, owner_id, type, start, payload}
var _history: Array[Dictionary] = []

func _ready() -> void:
	TimeService.connect("time_minute", Callable(self, "_on_minute"))

func dump() -> Dictionary:
	var out := {
		"events": _events,
	}
	if typeof(_history) == TYPE_ARRAY:
		out["history"] = _history
	return out

func restore(d: Dictionary) -> void:
	_events.clear()
	var arr = d.get("events", [])
	for ev in arr:
		var e: Dictionary = ev.duplicate(true)
		if e.has("owner_id"): e["owner_id"] = StringName(e["owner_id"])
		if e.has("type"): e["type"] = StringName(e["type"])
		if e.has("status"): e["status"] = StringName(e["status"])
		var pay = e.get("payload", {})
		if typeof(pay) == TYPE_DICTIONARY:
			if pay.has("place_id"): pay["place_id"] = StringName(pay["place_id"])
			if pay.has("venue_account_id"): pay["venue_account_id"] = StringName(pay["venue_account_id"])
			if pay.has("player_account_id"): pay["player_account_id"] = StringName(pay["player_account_id"])
			e["payload"] = pay
		_events.append(_sanitize_event(e))
	_events.sort_custom(func(a,b): return int(a["start"]) < int(b["start"]))
	if d.has("history"):
		var hist_in = d["history"]
		var hist: Array[Dictionary] = []
		for raw in hist_in:
			if typeof(raw) == TYPE_DICTIONARY:
				var e: Dictionary = raw.duplicate(true)
				if e.has("owner_id"): e["owner_id"] = StringName(e["owner_id"])
				if e.has("type"):     e["type"]     = StringName(e["type"])
				if e.has("status"):   e["status"]   = StringName(e["status"])
				var pay = e.get("payload", {})
				if typeof(pay) == TYPE_DICTIONARY:
					if pay.has("place_id"):          pay["place_id"]          = StringName(pay["place_id"])
					if pay.has("venue_account_id"):  pay["venue_account_id"]  = StringName(pay["venue_account_id"])
					if pay.has("player_account_id"): pay["player_account_id"] = StringName(pay["player_account_id"])
					e["payload"] = pay
				hist.append(_sanitize_event(e))
		_history = hist

func schedule(ev:Dictionary) -> void:
	_events.append(_with_defaults(_sanitize_event(ev)))
	_events.sort_custom(func(a,b): return a.start < b.start)
	emit_signal("events_changed")

func _on_minute(now:int) -> void:
	var changed := false
	var i := 0
	while i < _events.size():
		var ev := _events[i]
		var start := int(ev.get("start", 0))
		if start > now: break
		if _can_fire(ev):
			_fire(ev)
			_events.remove_at(i)
			changed = true
			continue
		else:
			if now <= start + GRACE_MINUTES:
				ev["status"] = "pending"
				i += 1
				emit_signal("events_changed")
			else:
				ev["status"] = "missed"
				emit_signal("event_missed", ev)
				_push_history(ev)
				_events.remove_at(i)
				changed = true
				continue
	if changed:
		emit_signal("events_changed")

func _can_fire(ev: Dictionary) -> bool:
	if bool(ev.get("requires_presence", false)):
		var place_id: StringName = ev.get("payload", {}).get("place_id", StringName())
		var status: StringName = StringName(ev.get("status", &"scheduled"))
		if place_id == StringName() or status == "missed":
			return false
		return PresenceService.is_at(ev["owner_id"], place_id)
	return true

func _fire(ev:Dictionary) -> void:
	emit_signal("event_fired", ev)
	_push_history(ev)
	match String(ev["type"]):
		"practice":
			var mins := int(ev["payload"].get("minutes", 60))
			var skill := StringName(ev["payload"].get("skill", "guitar"))
			var intensity := NeedsService.compute_intensity(ev["owner_id"])
			SkillsService.practice(ev["owner_id"], skill, mins, intensity)
			NeedsService.apply_activity_cost(ev["owner_id"], mins, intensity)
		"gig":
			#placeholder payout/rep
			var p = ev["payload"]
			var amount := int(p.get("payout", 50))
			var from_acct := StringName(p.get("from_agent_account_id", StringName()))
			var to_acct := StringName(p.get("to_agent_account_id", StringName()))
			if from_acct != StringName() and to_acct != StringName():
				EconomyService.transfer(from_acct, to_acct, amount, "Gig payout")
			print("GIG FIRED at", ev["payload"].get("place_id", "unknown"))
		"travel_begin":
			PresenceService.set_location(ev["owner_id"], PresenceService.PLACE_TRANSIT)
		"travel_end":
			var to_place: StringName = ev["payload"].get("to_place_id", StringName())
			if to_place != StringName():
				PresenceService.set_location(ev["owner_id"], to_place)
		"eat":
			var amt := float(ev["payload"].get("amount", 25.0))
			NeedsService.eat(ev["owner_id"], amt)
		"sleep_end":
			var mins := int(ev["payload"].get("duration", 60))
			NeedsService.rest(ev["owner_id"], mins)
		_:
			push_warning("Unhandled event type: %s" % str(ev["type"]))

func upcoming(limit:int=20) -> Array[Dictionary]:
	var n = min(limit, _events.size())
	var out : Array[Dictionary] = []
	out.resize(n)
	for i in n:
		out[i] = _events[i]
	return out

func _push_history(ev:Dictionary) -> void:
	_history.append(ev)
	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()

func schedule_travel(owner_id: StringName, to_place_id: StringName, depart_at: int, duration_min: int) -> Dictionary:
	var begin := {
		"id": IdService.new_id("ev"),
		"owner_id": owner_id,
		"type": "travel_begin",
		"start": depart_at,
		"requires_presence": false,
		"payload": {
			"to_place_id": to_place_id,
			"duration": duration_min
		}
	}
	var arrive := {
		"id": IdService.new_id("ev"),
		"owner_id": owner_id,
		"type": "travel_end",
		"start": depart_at + max(duration_min, 0),
		"requires_presence": false,
		"payload": {"to_place_id": to_place_id}
	}
	schedule(begin)
	schedule(arrive)
	return {"begin_id": begin["id"], "end_id": arrive["id"]}

func _with_defaults(ev:Dictionary) -> Dictionary:
	if not ev.has("status"): ev["status"] = &"scheduled"
	if not ev.has("requires_presence"): ev["requires_presence"] = false
	if not ev.has("payload"): ev["payload"] = {}
	return ev

func schedule_eat(owner_id: StringName, at_minutes: int, amount: float=25.0, requires_presence: bool = false, place_id: StringName=StringName()) -> StringName:
	var ev:= {
		"id": IdService.new_id("ev"),
		"owner_id": owner_id,
		"type": "eat",
		"start": at_minutes,
		"requires_presence": requires_presence,
		"payload": {
			"amount": amount,
			"place_id": place_id
		}
	}
	schedule(ev)
	return ev["id"]

func schedule_sleep(owner_id: StringName, start_minutes: int, duration_minutes : int, requires_presence: bool = false, place_id: StringName = StringName()) -> Dictionary:
	var end_ev := {
		"id": IdService.new_id("ev"),
		"owner_id": owner_id,
		"type": "sleep_end",
		"start": start_minutes + max(duration_minutes, 0),
		"requires_presence": requires_presence,
		"payload": {
			"duration": duration_minutes,
			"place_id": place_id
		}
	}
	schedule(end_ev)
	return {"end_id": end_ev["id"]}



#-- helpersq

func _sanitize_event(e: Dictionary) -> Dictionary:
	var ev = e.duplicate(true)
	ev["id"] = StringName(ev.get("id", StringName()))
	ev["owner_id"] = StringName(ev.get("owner_id", StringName()))
	ev["type"] = StringName(ev.get("type", StringName()))
	ev["status"] = StringName(ev.get("status", &"scheduled"))
	ev["requires_presence"] = bool(ev.get("requires_presence", false))
	ev["start"] = int(ev.get("start", 0))
	var pay = ev.get("payload", {})
	if typeof(pay) != TYPE_DICTIONARY:
		pay = {}
	if pay.has("place_id"):                pay["place_id"] = StringName(pay["place_id"])
	if pay.has("from_agent_account_id"):   pay["from_agent_account_id"] = StringName(pay["from_agent_account_id"])
	if pay.has("to_agent_account_id"):     pay["to_agent_account_id"] = StringName(pay["to_agent_account_id"])
	if pay.has("minutes"):                 pay["minutes"] = int(pay["minutes"])
	if pay.has("duration"):                pay["duration"] = int(pay["duration"])
	if pay.has("amount"):                  pay["amount"] = int(pay["amount"])
	if pay.has("payout"):                  pay["payout"] = int(pay["payout"])
	if pay.has("skill"):                   pay["skill"] = StringName(pay["skill"])
	ev["payload"] = pay
	return ev
