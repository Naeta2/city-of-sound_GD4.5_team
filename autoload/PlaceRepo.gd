extends Node

signal place_created(place_id: StringName)
signal place_changed(place_id: StringName)
signal place_removed(place_id: StringName)

var _places: Dictionary = {} #place_id : {id, type, name, meta}

const SPEED_WALK_M_PER_MIN := 80.0
const SPEED_METRO_M_PER_MIN := 400.0

func dump() -> Dictionary:
	var places_out: Dictionary = {}
	for id in _places.keys():
		var p = _places[id].duplicate(true)
		var meta = p.get("meta", {})
		if meta.has("pos") and typeof(meta["pos"]) == TYPE_VECTOR2:
			var v: Vector2 = meta["pos"]
			meta["pos"] = [v.x, v.y]
		p["meta"] = meta
		places_out[str(id)] = p
	return {"places": places_out}

func restore(d: Dictionary) -> void:
	_places.clear()
	var src = d.get("places", {})
	for k in src.keys():
		var p = src[k].duplicate(true)
		p["id"]   = StringName(p.get("id", StringName(k)))
		p["type"] = StringName(p.get("type", StringName()))
		var meta = p.get("meta", {})
		if meta.has("pos") and typeof(meta["pos"]) == TYPE_ARRAY and meta["pos"].size() >= 2:
			var arr = meta["pos"]
			meta["pos"] = Vector2(float(arr[0]), float(arr[1]))
		p["meta"] = meta
		_places[p["id"]] = p

# -- api

func create_place(p_type: StringName, p_name: String, meta: Dictionary={}) -> StringName:
	var id := IdService.new_id("place")
	_places[id] = {
		"id": id,
		"type": p_type, #ex &"venue", &"home", &"studio", &"shop" etc etc
		"name": p_name,
		"meta": meta.duplicate(true)
	}
	emit_signal("place_created", id)
	return id

func get_place(place_id:StringName) -> Dictionary:
	return _places.get(place_id, {})

func set_place_meta(place_id: StringName, key: String, value) -> void:
	if not _places.has(place_id): return
	_places[place_id]["meta"][key] = value
	emit_signal("place_changed", place_id)

func set_all_meta(place_id: StringName, meta: Dictionary) -> void:
	if not _places.has(place_id): return
	_places[place_id]["meta"] = meta.duplicate(true)
	emit_signal("place_changed", place_id)

func remove(place_id: StringName) -> void:
	if not _places.has(place_id): return
	_places.erase(place_id)
	emit_signal("place_removed", place_id)

func list_ids(p_type: StringName = StringName()) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _places.keys():
		if p_type == StringName() or _places[id]["type"] == p_type:
			out.append(id)
	return out

# -- helpers

func get_place_name(place_id: StringName) -> String:
	var p := get_place(place_id)
	return p.get("name", "")

func get_place_type(place_id: StringName) -> StringName:
	var p := get_place(place_id)
	return StringName(p.get("type", StringName()))

func estimate_travel_minutes(from_id: StringName, to_id: StringName, mode: StringName = &"walk") -> int:
	if from_id == StringName() or to_id == StringName(): return 0
	var a := get_place(from_id); var b := get_place(to_id)
	var pa = a.get("meta", {}).get("pos", null); var pb = b.get("meta", {}).get("pos", null)
	if pa == null or pb == null or typeof(pa) != TYPE_VECTOR2 or typeof(pb) != TYPE_VECTOR2:
		return 20 #arbitrary default
	var dist := (pa as Vector2).distance_to(pb as Vector2) # in arbitrary meter
	var speed := (SPEED_METRO_M_PER_MIN if mode == &"metro" else SPEED_WALK_M_PER_MIN)
	return max(1, int(round(dist / speed)))

func set_place_owner(place_id: StringName, owner_agent_id: StringName) -> void:
	if not _places.has(place_id): return
	_places[place_id]["meta"]["owner_agent_id"] = owner_agent_id
	emit_signal("place_changed", place_id)

func get_place_owner(place_id: StringName) -> StringName:
	var p:= get_place(place_id)
	var meta = p.get("meta", {})
	return StringName(meta.get("owner_agent_id", StringName()))
	
