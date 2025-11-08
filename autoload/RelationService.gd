extends Node

#directed graph A->B
#awareness: unilateral knowledge of other's existence

signal relation_changed(from_id: StringName, to_id: StringName, rel: Dictionary)

const BASE_REL := {
	"trust": 0.0,
	"liking": 0.0,
	"awareness": 0.0,
	"last_update": 0
	}

const RANGES := {
	"trust": Vector2(-100.0, 100.0),
	"liking": Vector2(-100.0, 100.0),
	"awareness": Vector2(0.0,100.0)
}

const DECAY_PER_DAY := {
	"trust": 1.0,
	"liking": 1.0,
	"awareness": 0.2
}

const KNOWS_THRESHOLDS := 5.0

#storage: key = "A|B" -> {trust:float,liking:float.......}
var _edges: Dictionary = {}

#intern

static func _key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [String(a), String(b)]

func _ensure(a: StringName, b: StringName) -> Dictionary:
	var k := _key(a,b)
	if not _edges.has(k):
		var rel := BASE_REL.duplicate(true)
		rel["last_update"] = TimeService.abs_minutes
		_edges[k] = rel
	return _edges[k]

func _clamp_for_key(key:String, value:float) -> float:
	if RANGES.has(key):
		var v2: Vector2 = RANGES[key]
		return clampf(value, v2.x, v2.y)
	return value #unclamped key

func _apply_values(rel: Dictionary, values:Dictionary, add_mode: bool) -> bool:
	var changed := false
	for k in values.keys():
		if k == "last_update":
			continue
		var cur := float(rel.get(k, 0.0))
		var val := float(values[k])
		var nv := _clamp_for_key(k, (cur + val) if add_mode else val)
		if nv != cur:
			rel[k] = nv
			changed = true
	return changed

# api

func get_rel(a: StringName, b: StringName) -> Dictionary :
	return _ensure(a, b).duplicate(true)

func set_rel(a: StringName, b: StringName, values: Dictionary) -> void:
	var r:= _ensure(a,b)
	var changed := _apply_values(r, values, false)
	if changed:
		r["last_update"] = TimeService.abs_minutes
		emit_signal("relation_changed", a, b, r)

func add_rel(a: StringName, b: StringName, deltas: Dictionary) -> void:
	var r := _ensure(a, b)
	var changed := _apply_values(r, deltas, true)
	if changed:
		r["last_update"] = TimeService.abs_minutes
		emit_signal("relation_changed", a, b, r)

func get_val(a: StringName, b: StringName, key: String) -> float:
	return float(_ensure(a,b).get(key, 0.0))

#helpers

func knows(a: StringName, b: StringName) -> bool:
	return get_val(a, b, "awareness") >= KNOWS_THRESHOLDS

#meeting/direct interaction. Call in mirror to symetrize
func meet(a: StringName, b: StringName, liking_seed: float = 0.0, trust_seed: float = 0.0) -> void:
	add_rel(a,b, {
		"awareness": 20.0,
		"liking": liking_seed,
		"trust": trust_seed
	})

#hear of. don't mirror
func hear_of(a: StringName, b: StringName, strength:float=5.0, liking_hint:float=0.0) -> void:
	add_rel(a,b, {
		"awareness": max(0.0, strength),
		"liking": liking_hint
	})

#early global score
func overall(a: StringName, b: StringName) -> float:
	var r := _ensure(a,b)
	var trust := float(r.get("trust",0.0))
	var liking:= float(r.get("liking", 0.0))
	return clampf(0.6*trust+0.4*liking, -100.0, 100.0)

func label(a:StringName, b: StringName) -> StringName:
	var s := overall(a,b)
	if s >= 60.0: return &"ally"
	if s >= 20.0: return &"friendly"
	if s > -20.0: return &"neutral"
	if s > -60.0: return &"unfriendly"
	return &"hostile"

#slow decay
func decay_tick() -> void:
	if _edges.is_empty(): return
	for k in _edges.keys():
		var r: Dictionary = _edges[k]
		for key in DECAY_PER_DAY.keys():
			var per_day := float(DECAY_PER_DAY[key])
			if per_day <= 0.0:
				continue
			var step := per_day / 24.0
			r[key] = move_toward(float(r.get(key, 0.0)), 0.0, step)

func _ready() -> void:
	if Engine.has_singleton("TimeService"):
		TimeService.connect("hour_changed", Callable(self,"_on_hour"))

func _on_hour(_d: int, _h: int) -> void:
	decay_tick()

#saveload

func dump() -> Dictionary:
	return {"edges": _edges.duplicate(true)}

func restore(d: Dictionary) -> void:
	_edges.clear()
	var src = d.get("edges", {})
	for k in src.keys():
		_edges[k] = src[k].duplicate(true)
