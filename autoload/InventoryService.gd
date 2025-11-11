extends Node

signal agent_inventory_changed(agend_id: StringName)
signal place_inventory_changed(place_id: StringName)

#-- state
var _inv_agent: Dictionary = {}
var _inv_place: Dictionary = {}
var _equip_agent: Dictionary ={}

const DEFAULT_GEAR := {
	"hand_left":{"type": &"hand", "items": []},
	"hand_right":{"type": &"hand", "items":[]}
} 

const EQUIP_SLOTS := [
	"lower",
	"upper_inner",
	"upper_outer",
	"feet",
	"head",
	"back"
]

#saveservice

static func _deep_copy(x):
	if typeof(x) == TYPE_DICTIONARY:
		var out := {}
		for k in x.keys():
			out[k] = _deep_copy(x[k])
		return out
	elif typeof(x) == TYPE_ARRAY:
		var arr := []
		for v in x:
			arr.append(_deep_copy(v))
		return arr
	else:
		return x

static func _safe_dict(x) -> Dictionary:
	return (x.duplicate(true) if typeof(x) == TYPE_DICTIONARY else {})

func dump() -> Dictionary:
	return {
		"agent": _deep_copy(_inv_agent),
		"place": _deep_copy(_inv_place),
		"equip": _deep_copy(_equip_agent)
	}

func restore(d: Dictionary) -> void:
	_inv_agent = _safe_dict(d.get("agent", {}))
	_inv_place = _safe_dict(d.get("place", {}))
	_equip_agent = _safe_dict(d.get("equip", {}))
	for ag in _inv_agent.keys():
		emit_signal("agent_inventory_changed", ag)
	for pl in _inv_place.keys():
		emit_signal("place_inventory_changed", pl)

#setup

func ensure_agent_inventory(agent_id: StringName, gear_template: Dictionary = DEFAULT_GEAR) -> void:
	if not _inv_agent.has(agent_id):
		var inv := {}
		for k in gear_template.keys():
			var ctype: StringName = gear_template[k]["type"]
			inv[k] = _make_container_instance(ctype, k)
		_inv_agent[agent_id] = inv
		emit_signal("agent_inventory_changed", agent_id)
	ensure_agent_equipment(agent_id)

func ensure_agent_equipment(agent_id: StringName) -> void:
	if not _equip_agent.has(agent_id):
		var slots := {}
		for s in EQUIP_SLOTS:
			# Each equip slot is represented by its own pseudo-container of type "equipped_slot" to hold the wearable entry.
			var cont_key = StringName("equip:" + s)
			# Create visible container entry for UI if you want to show equipped items; no grid, 1 entry
			if _inv_agent.has(agent_id) and not _inv_agent[agent_id].has(cont_key):
				_inv_agent[agent_id][cont_key] = _make_container_instance(&"equipped_slot", s)
			slots[s] = {"container_key": cont_key, "entry_id": StringName()}
		_equip_agent[agent_id] = slots

func ensure_place_inventory(place_id: StringName) -> void:
	if not _inv_place.has(place_id):
		_inv_place[place_id] = {"type": &"room_infinite", "items": []}
		emit_signal("place_inventory_changed", place_id)

func _make_container_instance(ctype: StringName, label: String="") -> Dictionary:
	var def := ContainerCatalog.get_def(ctype)
	var inst := {"type": ctype, "items": [], "label": label}
	if def.has("grid"):
		inst["grid"] = {"w": int(def["grid"]["w"]), "h": int(def["grid"]["h"])}
	return inst

# ---- Grid placement helpers -------------------------------------------
# Very simple first-fit scanner (no rotation for now). Future: allow rotations, masks, costs.
static func _fits(grid: Dictionary, pos: Vector2i, dims: Vector2i, occ: PackedByteArray) -> bool:
	var W = int(grid["w"]); var H = int(grid["h"])
	if pos.x < 0 or pos.y < 0 or pos.x + dims.x > W or pos.y + dims.y > H:
		return false
	for yy in range(pos.y, pos.y + dims.y):
		for xx in range(pos.x, pos.x + dims.x):
			var idx = yy * W + xx
			if occ[idx] == 1:
				return false
	return true

static func _occupancy(container_inst: Dictionary) -> PackedByteArray:
	var W = int(container_inst["grid"]["w"])
	var H = int(container_inst["grid"]["h"])
	var occ := PackedByteArray(); occ.resize(W*H); occ.fill(0)
	for e in container_inst["items"]:
		for yy in range(e["pos"].y, e["pos"].y + e["dims"].y):
			for xx in range(e["pos"].x, e["pos"].x + e["dims"].x):
				occ[yy*W+xx] = 1
	return occ

static func _first_fit(container_inst: Dictionary, dims: Vector2i) -> Variant:
	var grid = container_inst.get("grid", null)
	if grid == null:
		return null
	var W = int(grid["w"]); var H = int(grid["h"])
	var occ = _occupancy(container_inst)
	for y in range(H):
		for x in range(W):
			var p = Vector2i(x,y)
			if _fits(grid, p, dims, occ):
				return p
	return null

# ---- Public API: Add / Remove (Agent, with grid) ----------------------
func add_item_to_agent(agent_id: StringName, container_key: StringName, item_id: StringName, count: int = 1, meta: Dictionary = {}) -> Dictionary:
	# Returns {ok: bool, reason: String, entry_id: StringName}
	if count <= 0:
		return {"ok": false, "reason": "count<=0"}
	if not ItemCatalog.has(item_id):
		return {"ok": false, "reason": "unknown_item"}
	var inv = _inv_agent.get(agent_id, null)
	if inv == null:
		return {"ok": false, "reason": "no_inventory"}
	if not inv.has(container_key):
		return {"ok": false, "reason": "unknown_container"}
	var cinst = inv[container_key]
	var ctype: StringName = cinst["type"]
	var idef := ItemCatalog.get_def(item_id)
	var dims: Vector2i = idef.get("dims", Vector2i(1,1))
	# Hands vs grid checks
	if _is_hand_like(ctype):
		if cinst["items"].size() > 0:
			return {"ok": false, "reason": "hand_busy"}
		var hreq = int(idef.get("hands_required", 0))
		var hold_req = int(ContainerCatalog.get_def(ctype).get("holds_hands_required", 0))
		if hreq != hold_req:
			return {"ok": false, "reason": "hands_mismatch"}
		# For 1-hand, forbid absurdly huge dims
		if hold_req == 1 and (dims.x > 3 or dims.y > 3):
			return {"ok": false, "reason": "too_large_for_one_hand"}
		# place at synthetic pos (no grid)
		var entry_id: StringName = _new_item_entry_id()
		var entry = {"id": entry_id, "item_id": item_id, "count": count, "meta": _merge_default_meta(idef, meta), "pos": Vector2i(0,0), "dims": dims}
		cinst["items"].append(entry)
		emit_signal("agent_inventory_changed", agent_id)
		return {"ok": true, "reason": "added", "entry_id": entry_id}
	# Grid containers
	if not cinst.has("grid"):
		return {"ok": false, "reason": "no_grid"}
	# Stacking only for stackable items AND exactly same dims
	if idef.get("stackable", false):
		var max_stack: int = int(idef.get("max_stack", 1))
		for entry in cinst["items"]:
			if entry["item_id"] == item_id and entry["dims"] == dims and entry["count"] < max_stack:
				var take = min(count, max_stack - entry["count"])
				entry["count"] += take
				count -= take
				if count <= 0:
					emit_signal("agent_inventory_changed", agent_id)
					return {"ok": true, "reason": "stacked", "entry_id": entry["id"]}
	# Place as many entries as needed (no rotation)
	var remaining := count
	while remaining > 0:
		var pos = _first_fit(cinst, dims)
		if pos == null:
			return {"ok": false, "reason": "no_space"}
		var entry_id2: StringName = _new_item_entry_id()
		var entry2 = {"id": entry_id2, "item_id": item_id, "count": 1 if not idef.get("stackable", false) else remaining, "meta": _merge_default_meta(idef, meta), "pos": pos, "dims": dims}
		# If stackable we collapse all remaining into this one spot (space already sufficient for the stack visually)
		cinst["items"].append(entry2)
		remaining -= 1 if not idef.get("stackable", false) else remaining
		emit_signal("agent_inventory_changed", agent_id)
	return {"ok": true, "reason": "added", "entry_id": cinst["items"][-1]["id"]}

func remove_item_from_agent(agent_id: StringName, container_key: StringName, entry_id: StringName, count: int = 1) -> Dictionary:
	var inv = _inv_agent.get(agent_id, null)
	if inv == null or not inv.has(container_key):
		return {"ok": false, "reason": "not_found"}
	var items: Array = inv[container_key]["items"]
	for i in range(items.size()):
		var e = items[i]
		if e["id"] == entry_id:
			var remove_n = min(count, int(e["count"]))
			e["count"] -= remove_n
			var emptied := false
			if e["count"] <= 0:
				items.remove_at(i)
				emptied = true
			emit_signal("agent_inventory_changed", agent_id)
			return {"ok": true, "reason": "removed", "removed": remove_n, "emptied": emptied}
	return {"ok": false, "reason": "entry_not_found"}

# ---- Places & Transfers -----------------------------------------------
func add_item_to_place(place_id: StringName, item_id: StringName, count: int = 1, meta: Dictionary = {}) -> Dictionary:
	ensure_place_inventory(place_id)
	if count <= 0:
		return {"ok": false, "reason": "count<=0"}
	if not ItemCatalog.has(item_id):
		return {"ok": false, "reason": "unknown_item"}
	var items: Array = _inv_place[place_id]["items"]
	var def := ItemCatalog.get_def(item_id)
	if def.get("stackable", false):
		var max_stack: int = int(def.get("max_stack", 1))
		for entry in items:
			if entry["item_id"] == item_id and entry["count"] < max_stack:
				var take = min(count, max_stack - entry["count"])
				entry["count"] += take
				count -= take
				if count <= 0:
					emit_signal("place_inventory_changed", place_id)
					return {"ok": true, "reason": "stacked"}
	var remaining := count
	while remaining > 0:
		var dims: Vector2i = def.get("dims", Vector2i(1,1))
		items.append({"id": _new_item_entry_id(), "item_id": item_id, "count": 1 if not def.get("stackable", false) else remaining, "meta": _merge_default_meta(def, meta), "pos": Vector2i(0,0), "dims": dims})
		remaining -= 1 if not def.get("stackable", false) else remaining
	emit_signal("place_inventory_changed", place_id)
	return {"ok": true, "reason": "added"}

func transfer_agent_to_place(agent_id: StringName, container_key: StringName, place_id: StringName, entry_id: StringName, count: int = 1) -> Dictionary:
	var inv = _inv_agent.get(agent_id, null)
	if inv == null or not inv.has(container_key):
		return {"ok": false, "reason": "not_found"}
	var items: Array = inv[container_key]["items"]
	for i in range(items.size()):
		var e = items[i]
		if e["id"] == entry_id:
			var move_n = min(count, int(e["count"]))
			add_item_to_place(place_id, e["item_id"], move_n, e.get("meta", {}))
			e["count"] -= move_n
			var emptied := false
			if e["count"] <= 0:
				items.remove_at(i)
				emptied = true
			emit_signal("agent_inventory_changed", agent_id)
			return {"ok": true, "reason": "moved", "moved": move_n, "emptied": emptied}
	return {"ok": false, "reason": "entry_not_found"}

func transfer_place_to_agent(place_id: StringName, agent_id: StringName, container_key: StringName, entry_id: StringName, count: int = 1) -> Dictionary:
	var pinv = _inv_place.get(place_id, null)
	if pinv == null:
		return {"ok": false, "reason": "no_place_inv"}
	var items: Array = pinv["items"]
	for i in range(items.size()):
		var e = items[i]
		if e["id"] == entry_id:
			var move_n = min(count, int(e["count"]))
			var res = add_item_to_agent(agent_id, container_key, e["item_id"], move_n, e.get("meta", {}))
			if not res["ok"]:
				return res
			e["count"] -= move_n
			var emptied := false
			if e["count"] <= 0:
				items.remove_at(i)
				emptied = true
			emit_signal("place_inventory_changed", place_id)
			return {"ok": true, "reason": "moved", "moved": move_n, "emptied": emptied}
	return {"ok": false, "reason": "entry_not_found"}

# ---- Queries -----------------------------------------------------------
func get_agent_inventory(agent_id: StringName) -> Dictionary:
	return _inv_agent.get(agent_id, {})

func get_place_inventory(place_id: StringName) -> Dictionary:
	return _inv_place.get(place_id, {})

# ---- Wearables & Equipment slots --------------------------------------
# Public: equip item currently in some container into a slot (validates allowed slot)
func equip_to_slot(agent_id: StringName, slot_name: String, from_container_key: StringName, entry_id: StringName) -> Dictionary:
	ensure_agent_equipment(agent_id)
	var inv = _inv_agent.get(agent_id, null)
	if inv == null or not inv.has(from_container_key):
		return {"ok": false, "reason": "not_found"}
	if not _equip_agent[agent_id].has(slot_name):
		return {"ok": false, "reason": "unknown_slot"}
	var slot_info = _equip_agent[agent_id][slot_name]
	# deny if occupied
	if String(slot_info["entry_id"]) != "":
		return {"ok": false, "reason": "slot_occupied"}
	# find entry in source container
	var src_items: Array = inv[from_container_key]["items"]
	var idx := -1
	for i in range(src_items.size()):
		if src_items[i]["id"] == entry_id:
			idx = i; break
	if idx == -1:
		return {"ok": false, "reason": "entry_not_found"}
	var entry = src_items[idx]
	var idef := ItemCatalog.get_def(entry.item_id)
	if idef.get("cat", StringName()) != &"wearable":
		return {"ok": false, "reason": "not_wearable"}
	var allowed: Array = idef.get("wear_slots", [])
	if not slot_name in allowed:
		return {"ok": false, "reason": "slot_not_allowed"}
	# move entry to the slot container
	var slot_ckey: StringName = slot_info["container_key"]
	var slot_container = inv[slot_ckey]
	if slot_container["items"].size() > 0:
		return {"ok": false, "reason": "slot_container_busy"}
	src_items.remove_at(idx)
	slot_container["items"].append(entry)
	# call wearable attach to spawn provided containers
	var res = equip_wearable(agent_id, slot_ckey, entry_id)
	if not res["ok"]:
		return res
	# record state
	_equip_agent[agent_id][slot_name]["entry_id"] = entry_id
	emit_signal("agent_inventory_changed", agent_id)
	return {"ok": true, "reason": "equipped", "slot": slot_name}

# Public: unequip from slot back to a target container (grid-handled)
func unequip_from_slot(agent_id: StringName, slot_name: String, target_container_key: StringName) -> Dictionary:
	ensure_agent_equipment(agent_id)
	var inv = _inv_agent.get(agent_id, null)
	if inv == null:
		return {"ok": false, "reason": "no_inventory"}
	if not _equip_agent[agent_id].has(slot_name):
		return {"ok": false, "reason": "unknown_slot"}
	var slot_info = _equip_agent[agent_id][slot_name]
	var entry_id: StringName = slot_info["entry_id"]
	if String(entry_id) == "":
		return {"ok": false, "reason": "slot_empty"}
	# find in slot container
	var slot_ckey: StringName = slot_info["container_key"]
	var items: Array = inv[slot_ckey]["items"]
	if items.size() == 0:
		return {"ok": false, "reason": "slot_no_item"}
	var e = items[0]
	# detach provided containers into meta first
	unequip_wearable(agent_id, entry_id)
	# move out into target container
	var res = add_item_to_agent(agent_id, target_container_key, e["item_id"], int(e["count"]), e.get("meta", {}))
	if not res["ok"]:
		return res
	items.clear()
	_equip_agent[agent_id][slot_name]["entry_id"] = StringName()
	emit_signal("agent_inventory_changed", agent_id)
	return {"ok": true, "reason": "unequipped", "moved_to": String(target_container_key)}

# (kept) Attach/detach container logic used by equip_to_slot/unequip_from_slot
func equip_wearable(agent_id: StringName, container_key: StringName, entry_id: StringName) -> Dictionary:
	var inv = _inv_agent.get(agent_id, null)
	if inv == null or not inv.has(container_key):
		return {"ok": false, "reason": "not_found"}
	var item: Dictionary = {}
	for e in inv[container_key]["items"]:
		if e["id"] == entry_id:
			item = e; break
	if item.is_empty():
		return {"ok": false, "reason": "entry_not_found"}
	var idef := ItemCatalog.get_def(item["item_id"])
	var prov = idef.get("provides_containers", [])
	if prov.is_empty():
		# still mark equipped for state consistency
		item["meta"]["equipped"] = true
		_restore_attached_containers_from_meta(agent_id, item)
		emit_signal("agent_inventory_changed", agent_id)
		return {"ok": true, "reason": "equipped_no_containers"}
	item["meta"]["equipped"] = true
	_restore_attached_containers_from_meta(agent_id, item)
	item["meta"]["attached_containers"] = item["meta"].get("attached_containers", {})
	for p in prov:
		var cid = StringName("wear:" + str(entry_id) + ":" + String(p["key_suffix"]))
		if not _inv_agent[agent_id].has(cid):
			var inst = _make_container_instance(p["type"], String(p["key_suffix"]))
			inst["attached_to_entry"] = entry_id
			_inv_agent[agent_id][cid] = inst
		emit_signal("agent_inventory_changed", agent_id)
	return {"ok": true, "reason": "equipped"}

func unequip_wearable(agent_id: StringName, entry_id: StringName) -> Dictionary:
	var inv = _inv_agent.get(agent_id, null)
	if inv == null:
		return {"ok": false, "reason": "no_inventory"}
	var keys = inv.keys()
	for k in keys:
		var c = inv[k]
		if typeof(c) == TYPE_DICTIONARY and c.get("attached_to_entry", StringName()) == entry_id:
			var entry = _find_entry_by_id(inv, entry_id)
			if entry.is_empty():
				continue
			entry.meta["attached_containers"] = entry.meta.get("attached_containers", {})
			entry.meta["attached_containers"][k] = c
			inv.erase(k)
			emit_signal("agent_inventory_changed", agent_id)
	return {"ok": true, "reason": "unequipped"}

# ---- Credit stick helpers --------------------------------------------- ---------------------------------------------
func adjust_credit_stick_entry(entry: Dictionary, delta: int) -> Dictionary:
	# Change balance by delta (can be negative). Enforce 0..capacity.
	if entry.get("item_id", StringName()) != &"credit_stick":
		return {"ok": false, "reason": "not_credit_stick"}
	var meta = entry.get("meta", {})
	var cap := int(meta.get("capacity", 0))
	var bal := int(meta.get("balance", 0))
	var nb = clamp(bal + delta, 0, cap)
	entry["meta"]["balance"] = nb
	return {"ok": true, "reason": "adjusted", "balance": nb, "capacity": cap}

# ---- Helpers -----------------------------------------------------------
func _find_entry_by_id(inv: Dictionary, entry_id: StringName) -> Dictionary:
	for k in inv.keys():
		var cont = inv[k]
		if typeof(cont) != TYPE_DICTIONARY:
			continue
		var arr: Array = cont.get("items", [])
		for e in arr:
			if e.get("id", StringName()) == entry_id:
				return e
	return {}

func _find_entry_by_id_in_agent(agent_id: StringName, entry_id: StringName) -> Dictionary:
	var inv = _inv_agent.get(agent_id, null)
	if inv == null:
		return {}
	return _find_entry_by_id(inv, entry_id)

func _restore_attached_containers_from_meta(agent_id: StringName, entry: Dictionary) -> void:
	var attached = entry.get("meta", {}).get("attached_containers", {})
	for cid in attached.keys():
		if not _inv_agent[agent_id].has(cid):
			_inv_agent[agent_id][cid] = attached[cid].duplicate(true)

func _is_hand_like(ctype: StringName) -> bool:
	var cdef := ContainerCatalog.get_def(ctype)
	return cdef.has("holds_hands_required")

func _new_item_entry_id() -> StringName:
	if has_node("/root/IdService"):
		return StringName(get_node("/root/IdService").call("new_id", &"item"))
	return StringName("item_%s" % str(Time.get_ticks_msec()))

func _merge_default_meta(def: Dictionary, meta: Dictionary) -> Dictionary:
	var out := meta.duplicate(true)
	if def.has("default_meta"):
		for k in def.default_meta.keys():
			if not out.has(k):
				out[k] = def.default_meta[k]
	return out
