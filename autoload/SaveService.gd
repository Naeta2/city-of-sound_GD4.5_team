extends Node

signal save_done(path: String, ok: bool)
signal load_done(path: String, ok: bool)

const SAVE_SCHEMA := 1
const DEFAULT_PATH := "user://save.json"

func save(path: String = DEFAULT_PATH) -> bool:
	var data:= {
		"schema": SAVE_SCHEMA,
		"time": TimeService.dump(),
		"agents": AgentRepo.dump(),
		"economy": EconomyService.dump(),
		"presence": PresenceService.dump(),
		"scheduler": Scheduler.dump(),
		"places": PlaceRepo.dump()
	}
	var txt := JSON.stringify(data, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: cannot open " + path)
		return false
	f.store_string(txt)
	f.close()
	emit_signal("save_done", path, true)
	return true

func load(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("No save file at " + path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Load failed: cannot open " + path)
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Load failed: invalid JSON")
		return false
	var schema := int(parsed.get("schema", 0))
	if schema != SAVE_SCHEMA:
		pass #todo : migration in case of structure change
	TimeService.restore(parsed.get("time", {}))
	AgentRepo.restore(parsed.get("agents", {}))
	EconomyService.restore(parsed.get("economy", {}))
	PresenceService.restore(parsed.get("presence", {}))
	PlaceRepo.restore(parsed.get("places", {}))
	Scheduler.restore(parsed.get("scheduler", {}))
	emit_signal("load_done", path, true)
	return true
