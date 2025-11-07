extends Node

class_name SchedulerService

signal events_changed()
signal event_fired(ev)
signal event_missed(ev)

const GRACE_MINUTES := 30
const HISTORY_LIMIT := 200

var _events: Array[Dictionary] = [] #ev = {id, owner_id, type, start, payload}
var _history: Array[Dictionary] = []

func _ready() -> void:
	TimeService.connect("time_minute", Callable(self, "_on_minute"))

func schedule(ev:Dictionary) -> void:
	_events.append(ev)
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
		if place_id == StringName() or ev["status"] == "missed":
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
			SkillsService.practice(ev["owner_id"], skill, mins)
		"gig":
			#placeholder payout/rep
			print("GIG FIRED at", ev["payload"].get("place_id", "unknown"))
		"travel_begin":
			PresenceService.set_location(ev["owner_id"], PresenceService.PLACE_TRANSIT)
		"travel_end":
			var to_place: StringName = ev["payload"].get("to_place_id", StringName())
			if to_place != StringName():
				PresenceService.set_location(ev["owner_id"], to_place)
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
