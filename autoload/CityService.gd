extends Node

@export_category("City / Base")
@export var ex_seed:int = 12345
@export var ex_size:Vector2i = Vector2i(64, 48)

@export_group("Local Streets")
@export_range(0.0, 1.0, 0.01) var ex_local_density:float = 0.35
@export var ex_local_len_min:int = 3
@export var ex_local_len_max:int = 8
@export_range(0.0, 1.0, 0.01) var ex_straight_bias:float = 0.7

@export_group("Cleanup")
@export var ex_spur_max_len:int = 2
@export var ex_preserve_border:bool = true

@export_group("Metro")
@export var ex_metro_station_count:int = 22
@export var ex_metro_min_spacing:float = 7.0
@export var ex_metro_lines:int = 4
@export var ex_join_dist:float = 4.0

@export_group("Metro — Interconnectivity")
@export var ex_min_interchanges_total:int = 6        # nb minimal de stations partagées (≥2 lignes)
@export var ex_target_hub_degree:int = 3             # viser une station connectée à ≥3 lignes
@export var ex_interchange_join_dist:float = 5.0     # rayon pour fusion/partage entre 2 lignes
@export var ex_hub_join_dist:float = 4.0             # rayon pour promouvoir un hub multi-lignes

@export_group("Grid / World mapping")
@export var ex_cell_px:int = 16
@export var ex_world_origin:Vector2 = Vector2.ZERO
@export var ex_cell_size_m:float = 10.0

signal city_changed

#directions bitmask
const U := 1
const R := 2
const D := 4
const L := 8

var _seed: int = 0

var _w : int = 0
var _h : int = 0
var _dir_masks: PackedByteArray = PackedByteArray() #size = w*h, each cell a uint8 bitmask

var _stations: Array = [] #{"id":int,"pos":Vector2i,"cell":Vector2i}
var _lines: Array = [] #{"id":int, "name":String,"color":Color,"station_ids":Array[int]}

var _places: Array = [] #{"id":StringName, "name":String, "cell":Vector2i}

func _idx(x: int, y: int) -> int: return y * _w + x
func get_size() -> Vector2i: return Vector2i(_w, _h)
func get_dir_mask(x:int, y:int) -> int:
	if x < 0 or y <0 or x >= _w or y >= _h: return 0
	return int(_dir_masks[_idx(x,y)])

#--save

func dump() -> Dictionary:
	return {
		"w": _w, "h": _h,
		"dir_masks": _dir_masks, #PBA serialized by SaveService
		"stations": _stations,
		"lines": _lines,
		"places": _places,
	}

func restore(d: Dictionary) -> void:
	_w = int(d.get("w", 0))
	_h = int(d.get("h",0))
	_dir_masks = d.get("dir_masks", PackedByteArray())
	_stations = d.get("stations", [])
	_lines = d.get("lines", [])
	_places = d.get("places", [])
	emit_signal("city_changed")

#--

func get_places() -> Array:
	return _places

func clear_places() -> void:
	_places.clear()
	emit_signal("city_changed")

func add_place(place_id:StringName, p_name: String, cell:Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= ex_size.x or cell.y >= ex_size.y: return false
	if _is_road(cell.x,cell.y): return false
	for p in _places:
		if p["cell"] == cell: return false
	_places.append({"id":place_id,"name":p_name,"cell":cell})
	emit_signal("city_changed")
	return true

#-- helpers

func suggest_place_cell(min_spacing:int=2, tries:int=200) -> Vector2i:
	var rng := RandomNumberGenerator.new();rng.seed = hash("place_suggest") ^ _seed
	var taken2 := min_spacing * min_spacing
	for _i in range(tries):
		var x := rng.randi_range(1, _w-2)
		var y := rng.randi_range(1, _h-2)
		if _is_road(x,y): continue
		if not _is_adjacent_to_road(x,y): continue
		var ok := true
		for p in _places:
			var d = p["cell"] - Vector2i(x,y)
			if d.x*d.x + d.y*d.y < taken2: ok = false; break
		if ok:
			return Vector2i(x,y)
	return Vector2i(-1,-1)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	var rel := world_pos - ex_world_origin / ex_cell_size_m
	var cx = clamp(roundi(rel.x), 0, max(0, _w - 1))
	var cy = clamp(roundi(rel.y), 0, max(0, _h - 1))
	return Vector2i(cx, cy)

func cell_to_world(cell: Vector2i) -> Vector2 :
	return ex_world_origin + Vector2(cell) * ex_cell_size_m


#------------------ gen -------------------------








func generate_from_exports() -> void:
	generate(ex_seed, ex_size, {
		"local_density": ex_local_density,
		"local_len_min": ex_local_len_min,
		"local_len_max": ex_local_len_max,
		"straight_bias": ex_straight_bias,
		"spur_max_len": ex_spur_max_len,
		"preserve_border": ex_preserve_border,
		"metro_station_count": ex_metro_station_count,
		"metro_min_spacing": ex_metro_min_spacing,
		"metro_lines": ex_metro_lines,
		"join_dist": ex_join_dist,
	})

func generate(s:int, size:Vector2i, params: Dictionary = {}) -> void:
	_seed = s
	_w = max(8, size.x)
	_h = max(8, size.y)
	_dir_masks = PackedByteArray()
	_dir_masks.resize(_w*_h)
	_dir_masks.fill(0)
	_build_arterial_skeleton()
	
	var p_density := float(params.get("local_density", 0.35))
	var p_len_min := int(params.get("local_len_min", 3))
	var p_len_max := int(params.get("local_len_max", 9))
	var p_straight_bias := float(params.get("straight_bias", 0.6))
	_add_local_streets(p_density, p_len_min, p_len_max, p_straight_bias)
	_connect_all_components()
	var p_spur_max := int(params.get("spur_max_len", 2)) 
	var p_preserve_border := bool(params.get("preserve_border", true))
	_cleanup_spurs(p_spur_max, p_preserve_border)
	_prune_isolated_points()
	_sanitize_border_links()
	_enforce_reciprocity()
	
	var p_station_count := int(params.get("metro_station_count", 18))
	var p_min_spacing   := float(params.get("metro_min_spacing", 6.0)) # distance cellulaire min entre stations
	var p_k_lines       := int(params.get("metro_lines", 3))

	_generate_metro_stations(p_station_count, p_min_spacing)
	_generate_metro_lines_kmeans_mst(p_k_lines)
	
	_increase_interconnectivity(ex_min_interchanges_total, ex_interchange_join_dist)
	_promote_multiline_hub(ex_target_hub_degree, ex_hub_join_dist)
	
	_postprocess_metro_lines_coverage_and_interchanges(float(params.get("join_dist", 4.0)))
	_final_cover_orphans_by_projection()
	_ensure_full_station_coverage()
	
	emit_signal("city_changed")

#-- places

func sync_places_from_repo(preserve_existing: bool = false, write_back: bool = true) -> void:
	if not preserve_existing:
		_places.clear()
	var ids := []
	if PlaceRepo.has_method("list_ids"):
		ids = PlaceRepo.list_ids()
	elif PlaceRepo.has_method("get_all_place_ids"):
		ids = PlaceRepo.get_all_place_ids()
	else:
		push_warning("PlaceRepo: no ids getter (list_ids / get_all_place_ids).")
		emit_signal("city_changed")
		return
	for pid in ids:
		if not PlaceRepo.has_method("get_place"):
			continue
		var p := PlaceRepo.get_place(pid)
		var n = String(p.get("name", String(pid)))
		var meta = p.get("meta", {})
		var cell := Vector2i(-1, -1)
		if typeof(meta) == TYPE_DICTIONARY and meta.has("grid_cell"):
			cell = _parse_vec2i(meta["grid_cell"], Vector2i(-1, -1))
		if (cell.x < 0 or cell.y < 0) and typeof(meta) == TYPE_DICTIONARY and meta.has("pos"):
			var pos = meta["pos"]
			match typeof(pos):
				TYPE_VECTOR2:
					cell = world_to_cell(pos)
				TYPE_VECTOR2I:
					cell = pos
				_:
					cell = _parse_vec2i(pos, Vector2i(-1, -1))
		if cell.x < 0 or cell.y < 0:
			cell = suggest_place_cell()
		if not _is_valid_place_cell(cell):
			cell = _nearest_valid_place_cell(cell, 12)
		if cell.x < 0 or cell.y < 0:
			push_warning("Could not place '%s' on grid." % [name])
			continue
		var dup := false
		for e in _places:
			if e["cell"] == cell:
				dup = true
				break
		if dup:
			var alt := _nearest_valid_place_cell(cell + Vector2i(1, 0), 8)
			if alt.x >= 0:
				cell = alt
			else:
				continue
		_places.append({ "id": StringName(pid), "name": n, "cell": cell })
		if write_back and PlaceRepo.has_method("set_place_meta_value"):
			PlaceRepo.set_place_meta_value(pid, "grid_cell", [cell.x, cell.y])
	emit_signal("city_changed")


#--road


func _build_arterial_skeleton() -> void:
	randomize()
	var ring := true
	var spacing = max(6, int(min(_w,_h)/6))
	
	if ring:
		for x in range(_w):
			_link_bidirectional(x, 0, x+1, 0)
			_link_bidirectional(x, _h-1, x+1, _h-1)
		for y in range(_h):
			_link_bidirectional(0, y, 0, y+1)
			_link_bidirectional(_w-1, y, _w-1, y+1)
	
	for x in range(spacing, _w, spacing):
		for y in range(_h-1):
			_link_bidirectional(x, y, x, y+1)
	
	for y in range(spacing, _h, spacing):
		for x in range(_w-1):
			_link_bidirectional(x,y,x+1,y)

func _add_local_streets(density:float,len_min:int, len_max:int, straight_bias:float) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = _seed+1
	var starts: Array[Vector2i] = []
	for y in range(_h):
		for x in range(_w):
			if _road_at(x,y): starts.append(Vector2i(x,y))
	if starts.is_empty(): return
	var attempts := int(density * float(_w*_h) / 6.0)
	for i in range(max(1, attempts)):
		var s := starts[rng.randi_range(0, starts.size()-1)]
		_walk_and_carve(rng, s, len_min,len_max, straight_bias)

func _walk_and_carve(rng: RandomNumberGenerator, start: Vector2i, len_min: int, len_max:int, straight_bias:float) -> void:
	var length := rng.randi_range(len_min, len_max)
	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var dir = dirs[rng.randi_range(0,3)]
	var p := start
	for _step in range(length):
		if rng.randf() > straight_bias:
			dir = _turn_choice(rng, dir)
		var q = p + dir
		if q.x < 1 or q.y < 1 or q.x >= _w-1 or q.y >= _h -1:
			break
		_link_bidirectional(p.x, p.y,q.x,q.y)
		p=q

func _turn_choice(rng: RandomNumberGenerator, dir: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	if dir.x != 0 :
		candidates = [Vector2i(0,1), Vector2i(-1,0)]
	else:
		candidates = [Vector2i(1,0), Vector2i(-1,0)]
	return candidates[rng.randi_range(0, candidates.size()-1)]

func _road_at(x:int,y:int) -> bool:
	return get_dir_mask(x,y) != 0


#--


func _connect_all_components() -> void:
	var comps := _collect_components()
	if comps.size() <= 1:
		return
	comps.sort_custom(func(a,b): return a.size() > b.size())
	var main = comps[0]
	for i in range(1, comps.size()):
		_connect_component_to(main, comps[i])
		main = main + comps[i]

func _collect_components() -> Array:
	var visited := PackedByteArray(); visited.resize(_w*_h); visited.fill(0)
	var out := []
	for y in range(_h):
		for x in range(_w):
			if _road_at(x,y) and visited[_idx(x,y)] == 0:
				out.append(_bfs_component(Vector2i(x,y), visited))
	return out

func _bfs_component(src: Vector2i, visited: PackedByteArray) -> Array[Vector2i]:
	var q: Array[Vector2i] = [src]
	var qi := 0  # pointeur de lecture (évite pop_front)
	visited[_idx(src.x, src.y)] = 1
	var comp: Array[Vector2i] = []
	while qi < q.size():
		var p := q[qi]; qi += 1
		comp.append(p)
		for n in _road_neighbors(p):
			var id := _idx(n.x, n.y)
			if visited[id] == 0:
				visited[id] = 1
				q.append(n)
	return comp

func _road_neighbors(p: Vector2i) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	var m := get_dir_mask(p.x, p.y)
	if (m & U) != 0 and _y_in(p.y-1) and (get_dir_mask(p.x, p.y-1) & D) != 0: res.append(Vector2i(p.x, p.y-1))
	if (m & D) != 0 and _y_in(p.y+1) and (get_dir_mask(p.x, p.y+1) & U) != 0: res.append(Vector2i(p.x, p.y+1))
	if (m & L) != 0 and _x_in(p.x-1) and (get_dir_mask(p.x-1, p.y) & R) != 0: res.append(Vector2i(p.x-1, p.y))
	if (m & R) != 0 and _x_in(p.x+1) and (get_dir_mask(p.x+1, p.y) & L) != 0: res.append(Vector2i(p.x+1, p.y))
	return res

func _x_in(x:int) -> bool: return x >= 0 and x < _w
func _y_in(y:int) -> bool: return y >= 0 and y < _h

func _connect_component_to(main: Array[Vector2i], other: Array[Vector2i]) -> void:
	if other.is_empty() or main.is_empty():
		return
	@warning_ignore("integer_division")
	var step_main = max(1, main.size() / 128)
	@warning_ignore("integer_division")
	var step_other = max(1, other.size() / 128)
	var best_a := other[0]
	var best_b := main[0]
	var best_d := 1e9
	for i in range(0, other.size(), step_other):
		var a := other[i]
		for j in range(0, main.size(), step_main):
			var b := main[j]
			var d = abs(a.x-b.x) + abs(a.y-b.y)
			if d < best_d:
				best_d = d; best_a = a; best_b = b

	var path := _grid_bfs_path(best_a, best_b)
	for k in range(path.size()-1):
		var p := path[k]; var q := path[k+1]
		_link_bidirectional(p.x, p.y, q.x, q.y)

func _grid_bfs_path(src: Vector2i, dst: Vector2i) -> Array[Vector2i]:
	if src == dst:
		return [dst]
	var q: Array[Vector2i] = [src]
	var qi := 0
	var came := {}
	came[src] = Vector2i(-999,-999)
	while qi < q.size():
		var p := q[qi]; qi += 1
		if p == dst:
			break
		for n in [Vector2i(p.x+1,p.y), Vector2i(p.x-1,p.y), Vector2i(p.x,p.y+1), Vector2i(p.x,p.y-1)]:
			if n.x < 0 or n.y < 0 or n.x >= _w or n.y >= _h: continue
			if came.has(n): continue
			came[n] = p
			q.append(n)
	var path: Array[Vector2i] = []
	var cur := dst
	while came.has(cur):
		path.push_front(cur)
		cur = came[cur]
	return path

func _cleanup_spurs(max_len:int, preserve_border:bool) -> void:
	if max_len <= 0: return
	var passes := 0
	while passes < 8:
		passes += 1
		var changed := false
		var leaves: Array[Vector2i] = []
		for y in range(_h):
			for x in range(_w):
				if _road_at(x,y) and _degree(x,y) == 1:
					leaves.append(Vector2i(x,y))
		for leaf in leaves:
			if not _road_at(leaf.x, leaf.y): continue
			if _degree(leaf.x, leaf.y) != 1: continue
			var chain: Array[Vector2i] = [leaf]
			var cur := leaf
			var prev := Vector2i(-999,-999)
			while chain.size() <= max_len:
				var nbs := _road_neighbors(cur)
				if prev != Vector2i(-999,-999):
					for i in range(nbs.size()-1, -1, -1):
						if nbs[i] == prev:
							nbs.remove_at(i); break
				if nbs.is_empty(): break
				var nxt := nbs[0]
				prev = cur
				cur = nxt
				chain.append(cur)
				var deg := _degree(cur.x, cur.y)
				if deg == 0 or deg != 2: break
			if chain.size() > 0 and chain.size() <= max_len:
				if preserve_border:
					var touches_border := false
					for p in chain:
						if _is_border(p.x, p.y): touches_border = true; break
					if touches_border:
						continue
				for i in range(chain.size()-1):
					var a := chain[i]
					var b := chain[i+1]
					_unlink(a.x, a.y, b.x, b.y)
					changed = true
		if not changed:
			break

func _prune_isolated_points() -> void:
	for y in range(_h):
		for x in range(_w):
			if _road_at(x,y) and _degree(x,y) == 0:
				_set_mask_remove(x, y, U|R|D|L)



#-- metro



func _generate_metro_stations(target_count:int, min_spacing:float) -> void:
	_stations.clear()
	if target_count <= 0: return
	var candidates: Array[Vector2i] = []
	for y in range(_h):
		for x in range(_w):
			if _is_adjacent_to_road(x,y):
				candidates.append(Vector2i(x,y))
	if candidates.is_empty(): return
	var rng := RandomNumberGenerator.new(); rng.seed = hash("metro_stations") ^ _seed
	var taken2 := int(min_spacing*min_spacing)
	var picked: Array[Vector2i] = []
	var tries := 0
	var max_tries := candidates.size() * 4
	while picked.size() < target_count and tries < max_tries:
		tries += 1
		var c := candidates[rng.randi_range(0, candidates.size()-1)]
		var ok := true
		for p in picked:
			if _dist2(p, c) < taken2:
				ok = false; break
		if ok:
			picked.append(c)
	while picked.size() < target_count and min_spacing > 2.0:
		min_spacing *= 0.85
		taken2 = int(min_spacing*min_spacing)
		for c in candidates:
			if picked.size() >= target_count: break
			var ok := true
			for p in picked:
				if _dist2(p, c) < taken2:
					ok = false; break
			if ok:
				picked.append(c)
	for i in range(picked.size()):
		_stations.append({ "id": i, "pos": picked[i], "cell": picked[i] })

func _generate_metro_lines_kmeans_mst(k_lines:int) -> void:
	_lines.clear()
	if _stations.size() == 0 or k_lines <= 0: return
	var pts: Array[Vector2i] = []
	for s in _stations: pts.append(s["pos"])
	var clusters : Array = _kmeans(pts, k_lines, 16)
	var palette := [Color(0.9,0.2,0.2), Color(0.2,0.7,0.9), Color(0.2,0.9,0.3),
		Color(0.9,0.6,0.2), Color(0.6,0.3,0.9), Color(0.9,0.2,0.7)]
	var lid := 0
	for ci in range(clusters.size()):
		var c: Array = clusters[ci]
		if c.is_empty(): continue
		var ordered: Array[Vector2i] = _mst_order(c)
		var station_ids: Array[int] = []
		for p in ordered:
			var sid := -1
			for s in _stations:
				if s["pos"] == p:
					sid = int(s["id"]); break
			if sid >= 0:
				station_ids.append(sid)
		if station_ids.size() >= 2:
			_lines.append({
				"id": lid,
				"name": "L" + str(lid+1),
				"color": palette[lid % palette.size()],
				"station_ids": station_ids
			})
			lid += 1

func _postprocess_metro_lines_coverage_and_interchanges(join_dist: float) -> void:
	if _stations.is_empty() or _lines.is_empty():
		return
	var spos := {}
	for s in _stations:
		spos[int(s["id"])] = Vector2i(s["pos"])
	var covered := {}
	for _L in _lines:
		for sid in _L["station_ids"]:
			covered[int(sid)] = true
	var uncovered: Array[int] = []
	for s in _stations:
		var sid := int(s["id"])
		if not covered.has(sid):
			uncovered.append(sid)
	for sid in uncovered:
		var s_pos: Vector2i = spos[sid]
		var best_line := -1
		var best_idx := -1
		var best_cost := 1e18
		for li in range(_lines.size()):
			var ids: Array = _lines[li]["station_ids"]
			if ids.size() == 0:
				best_line = li; best_idx = 0; best_cost = 0.0; break
			elif ids.size() == 1:
				var a = spos[int(ids[0])]
				var c := _d(a, s_pos)
				if c < best_cost:
					best_cost = c; best_line = li; best_idx = 1 
			else:
				for i in range(ids.size()-1):
					var a = spos[int(ids[i])]
					var b = spos[int(ids[i+1])]
					var delta := _path_delta_insert(a, b, s_pos)
					if delta < best_cost:
						best_cost = delta; best_line = li; best_idx = i+1
				var head = spos[int(ids[0])]
				var tail = spos[int(ids[ids.size()-1])]
				var dh := _d(s_pos, head)
				var dt := _d(s_pos, tail)
				if dh < best_cost:
					best_cost = dh; best_line = li; best_idx = 0
				if dt < best_cost:
					best_cost = dt; best_line = li; best_idx = ids.size()
		if best_line >= 0:
			_lines[best_line]["station_ids"].insert(best_idx, sid)
	
	var join2 := join_dist * join_dist
	var line_sets := []
	line_sets.resize(_lines.size())
	for li in range(_lines.size()):
		var sset := {}
		for sid in _lines[li]["station_ids"]:
			sset[int(sid)] = true
		line_sets[li] = sset
	var made_interchange := false
	for a in range(_lines.size()):
		for b in range(a+1, _lines.size()):
			var already_shared := false
			for sid_a in line_sets[a].keys():
				if line_sets[b].has(sid_a):
					already_shared = true; break
			if already_shared:
				made_interchange = true
				continue
			var bestA := -1
			var bestB := -1
			var bestd2 := 1e18
			for sid_a in line_sets[a].keys():
				var pa: Vector2i = spos[int(sid_a)]
				for sid_b in line_sets[b].keys():
					var pb: Vector2i = spos[int(sid_b)]
					var d2 := (Vector2(pa) - Vector2(pb)).length_squared()
					if d2 < bestd2:
						bestd2 = d2; bestA = int(sid_a); bestB = int(sid_b)
			if bestA == -1 or bestB == -1:
				continue
			if bestd2 <= join2:
				var canon = min(bestA, bestB)
				var other = max(bestA, bestB)
				for li in [a, b]:
					var arr: Array = _lines[li]["station_ids"]
					for i in range(arr.size()):
						if int(arr[i]) == other:
							arr[i] = canon
					_lines[li]["station_ids"] = _dedupe_consecutive(arr)
				line_sets[a].erase(other); line_sets[b].erase(other)
				line_sets[a][canon] = true; line_sets[b][canon] = true
				made_interchange = true
	if not made_interchange and _lines.size() >= 2:
		var best := { "a":0, "b":1, "sa":-1, "sb":-1, "d2":1e18 }
		for a in range(_lines.size()):
			for b in range(a+1, _lines.size()):
				for sa in _lines[a]["station_ids"]:
					for sb in _lines[b]["station_ids"]:
						var pa = spos[int(sa)]
						var pb = spos[int(sb)]
						var d2 := (Vector2(pa) - Vector2(pb)).length_squared()
						if d2 < best["d2"]:
							best = { "a":a, "b":b, "sa":int(sa), "sb":int(sb), "d2":d2 }
		var canon = min(best["sa"], best["sb"])
		var other = max(best["sa"], best["sb"])
		for li in [best["a"], best["b"]]:
			var arr2: Array = _lines[li]["station_ids"]
			for i2 in range(arr2.size()):
				if int(arr2[i2]) == other:
					arr2[i2] = canon
			_lines[li]["station_ids"] = _dedupe_consecutive(arr2)

func _final_cover_orphans_by_projection() -> void:
	if _stations.is_empty(): return
	if _lines.is_empty():
		var ids_all: Array[int] = []
		for s in _stations: ids_all.append(int(s["id"]))
		if ids_all.size() >= 2:
			_lines.append({"id": 0, "name": "L1", "color": Color(0.9,0.2,0.2), "station_ids": ids_all})
		return
	var spos := {}
	for s in _stations:
		spos[int(s["id"])] = Vector2i(s["pos"])
	var covered := {}
	for _L in _lines:
		for sid in _L["station_ids"]:
			covered[int(sid)] = true
	var orphans: Array[int] = []
	for s in _stations:
		var sid := int(s["id"])
		if not covered.has(sid):
			orphans.append(sid)
	for sid in orphans:
		var s_pos: Vector2i = spos[sid]
		var best_line := -1
		var best_idx := 0
		var best_cost := 1e18
		for li in range(_lines.size()):
			var ids: Array = _lines[li]["station_ids"]
			var res := _seg_insert_cost_and_index(ids, s_pos, spos)
			if res["cost"] < best_cost:
				best_cost = res["cost"]; best_line = li; best_idx = int(res["idx"])
		if best_line >= 0:
			_lines[best_line]["station_ids"].insert(best_idx, sid)
	for li in range(_lines.size()):
		_lines[li]["station_ids"] = _dedupe_consecutive(_lines[li]["station_ids"])

func _increase_interconnectivity(min_total:int, join_dist:float) -> void:
	if _lines.is_empty(): return
	var spos := _station_pos_by_id()
	var target = max(0, min_total)
	var attempts := 0
	var max_attempts := 128
	var join2 := join_dist * join_dist
	while attempts < max_attempts:
		attempts += 1
		var stat := _count_interchanges()
		if int(stat["count"]) >= target:
			break
		var best := {"a":-1, "b":-1, "sa":-1, "sb":-1, "d2":1e18}
		for a in range(_lines.size()):
			for b in range(a+1, _lines.size()):
				var shared := false
				for sid_a in _lines[a]["station_ids"]:
					var ia := int(sid_a)
					if _line_contains(b, ia):
						shared = true; break
				if shared: continue
				var np := _nearest_pair_between_lines(a, b, spos)
				if np["d2"] < best["d2"]:
					best = {"a":a, "b":b, "sa":np["sa"], "sb":np["sb"], "d2":np["d2"]}
		if best["a"] == -1:
			break 
		var a := int(best["a"])
		var b := int(best["b"])
		var sa := int(best["sa"])
		var sb := int(best["sb"])
		if best["d2"] <= join2:
			var canon = min(sa, sb)
			var other = max(sa, sb)
			var a_has_other := _line_contains(a, other)
			var b_has_other := _line_contains(b, other)
			if a_has_other and not b_has_other:
				var resB := _seg_insert_cost_and_index(_lines[b]["station_ids"], spos[other], spos)
				_lines[b]["station_ids"].insert(int(resB["idx"]), other)
			elif b_has_other and not a_has_other:
				var resA := _seg_insert_cost_and_index(_lines[a]["station_ids"], spos[other], spos)
				_lines[a]["station_ids"].insert(int(resA["idx"]), other)
			for li in [a, b]:
				var arr: Array = _lines[li]["station_ids"]
				for i in range(arr.size()):
					if int(arr[i]) == other:
						arr[i] = canon
				_lines[li]["station_ids"] = _dedupe_consecutive(arr)
		else:
			var sa_pos: Vector2i = spos[sa]
			var sb_pos: Vector2i = spos[sb]
			if (_d(sa_pos, sb_pos) < join_dist * 1.5):
				var resA := _seg_insert_cost_and_index(_lines[a]["station_ids"], sb_pos, spos)
				var resB := _seg_insert_cost_and_index(_lines[b]["station_ids"], sa_pos, spos)
				if resA["cost"] <= join_dist:
					_lines[a]["station_ids"].insert(int(resA["idx"]), sb)
				elif resB["cost"] <= join_dist:
					_lines[b]["station_ids"].insert(int(resB["idx"]), sa)
				else:
					continue
			else:
				continue

func _promote_multiline_hub(target_degree:int, hub_dist:float) -> void:
	if _lines.is_empty() or _stations.is_empty(): return
	target_degree = max(2, target_degree)
	var spos := _station_pos_by_id()
	var center := Vector2(float(_w)*0.5, float(_h)*0.5)
	var best_sid := int(_stations[0]["id"])
	var best_d := 1e18
	for s in _stations:
		var sid := int(s["id"])
		var d := (Vector2(s["pos"]) - center).length_squared()
		if d < best_d:
			best_d = d; best_sid = sid
	var hub_pos: Vector2i = spos[best_sid]
	var joined_lines := 0
	var hub2 := hub_dist * hub_dist
	for _L in _lines:
		for sid in _L["station_ids"]:
			if int(sid) == best_sid:
				joined_lines += 1
				break
	var attempts := 0
	for li in range(_lines.size()):
		if joined_lines >= target_degree: break
		attempts += 1
		if attempts > 256: break
		if _line_contains(li, best_sid): continue
		var ids: Array = _lines[li]["station_ids"]
		if ids.is_empty(): continue
		var nearest := int(ids[0])
		var bestd2 := 1e18
		for sid in ids:
			var d2 := (Vector2(spos[int(sid)]) - Vector2(hub_pos)).length_squared()
			if d2 < bestd2:
				bestd2 = d2; nearest = int(sid)
		if bestd2 <= hub2:
			for i in range(ids.size()):
				if int(ids[i]) == nearest:
					ids[i] = best_sid
			_lines[li]["station_ids"] = _dedupe_consecutive(ids)
			joined_lines += 1
		else:
			var res := _seg_insert_cost_and_index(ids, hub_pos, spos)
			if res["cost"] <= hub_dist:
				ids.insert(int(res["idx"]), best_sid)
				_lines[li]["station_ids"] = _dedupe_consecutive(ids)
				joined_lines += 1

func _ensure_full_station_coverage() -> void:
	if _stations.is_empty():
		return
	if _lines.is_empty():
		var ids_all: Array[int] = []
		for s in _stations: ids_all.append(int(s["id"]))
		if ids_all.size() >= 2:
			_lines.append({ "id": 0, "name": "L1", "color": Color(0.9,0.2,0.2), "station_ids": ids_all })
		return
	var spos := _station_pos_by_id()
	var covered := {}
	for _L in _lines:
		for sid in _L["station_ids"]:
			covered[int(sid)] = true
	var orphans: Array[int] = []
	for s in _stations:
		var sid := int(s["id"])
		if not covered.has(sid):
			orphans.append(sid)
	for sid in orphans:
		var s_pos: Vector2i = spos[sid]
		var best_line := -1
		var best_idx := 0
		var best_cost := 1e18
		for li in range(_lines.size()):
			var ids: Array = _lines[li]["station_ids"]
			var res := _seg_insert_cost_and_index(ids, s_pos, spos)
			if res["cost"] < best_cost:
				best_cost = res["cost"]; best_line = li; best_idx = int(res["idx"])
		if best_line >= 0:
			_lines[best_line]["station_ids"].insert(best_idx, sid)
	for li in range(_lines.size()):
		_lines[li]["station_ids"] = _dedupe_consecutive(_lines[li]["station_ids"])




#helpers




func _set_mask(x:int, y:int, mask:int) -> void:
	if x < 0 or y < 0 or x >= _w or y >= _h: return
	var i := _idx(x,y)
	_dir_masks[i] = _dir_masks[i] | mask

func _link_bidirectional(x1:int, y1:int, x2:int, y2:int) -> void:
	if x2 == x1+1 and y2==y1:
		_set_mask(x1,y1, R); _set_mask(x2, y2, L)
	elif x2 == x1-1 and y2 == y1:
		_set_mask(x1, y1, L); _set_mask(x2, y2, R)
	elif y2 == y1+1 and x2 == x1:
		_set_mask(x1, y1, D); _set_mask(x2, y2, U)
	elif y2 == y1-1 and x2 == x1:
		_set_mask(x1, y1, U); _set_mask(x2, y2, D)

func _is_border(x:int, y:int) -> bool:
	return x == 0 or y == 0 or x == _w-1 or y == _h-1

func _degree(x:int, y:int) -> int:
	return _road_neighbors(Vector2i(x,y)).size()

func _unlink(x1:int, y1:int, x2:int, y2:int) -> void:
	# enlève les bits réciproques entre 2 voisins cardinaux
	if x2 == x1+1 and y2 == y1:
		# retirer R à (x1,y1), L à (x2,y2)
		_set_mask_remove(x1, y1, R); _set_mask_remove(x2, y2, L)
	elif x2 == x1-1 and y2 == y1:
		_set_mask_remove(x1, y1, L); _set_mask_remove(x2, y2, R)
	elif y2 == y1+1 and x2 == x1:
		_set_mask_remove(x1, y1, D); _set_mask_remove(x2, y2, U)
	elif y2 == y1-1 and x2 == y1:
		_set_mask_remove(x1, y1, U); _set_mask_remove(x2, y2, D)

func _set_mask_remove(x:int, y:int, mask:int) -> void:
	if x < 0 or y < 0 or x >= _w or y >= _h: return
	var i := _idx(x,y)
	_dir_masks[i] = _dir_masks[i] & (~mask & 0xFF)

func _sanitize_border_links() -> void:
	for x in range(_w):
		if get_dir_mask(x, 0) & U != 0:
			_set_mask_remove(x, 0, U)
		if get_dir_mask(x, _h-1) & D != 0:
			_set_mask_remove(x, _h-1, D)
	for y in range(_h):
		if get_dir_mask(0, y) & L != 0:
			_set_mask_remove(0, y, L)
		if get_dir_mask(_w-1, y) & R != 0:
			_set_mask_remove(_w-1, y, R)

func _enforce_reciprocity() -> void:
	for y in range(_h):
		for x in range(_w):
			var m := get_dir_mask(x,y)
			if m == 0: continue
			if (m & R) != 0:
				if x+1 >= _w or (get_dir_mask(x+1,y) & L) == 0:
					_set_mask_remove(x, y, R)
			if (m & L) != 0:
				if x-1 < 0 or (get_dir_mask(x-1,y) & R) == 0:
					_set_mask_remove(x, y, L)
			if (m & D) != 0:
				if y+1 >= _h or (get_dir_mask(x,y+1) & U) == 0:
					_set_mask_remove(x, y, D)
			if (m & U) != 0:
				if y-1 < 0 or (get_dir_mask(x,y-1) & D) == 0:
					_set_mask_remove(x, y, U)

func _is_road(x:int, y:int) -> bool:
	return get_dir_mask(x,y) != 0

func _is_adjacent_to_road(x:int, y:int) -> bool:
	if _is_road(x,y): 
		return false
	if x > 0     and get_dir_mask(x-1,y) != 0: return true
	if x < _w-1  and get_dir_mask(x+1,y) != 0: return true
	if y > 0     and get_dir_mask(x,y-1) != 0: return true
	if y < _h-1  and get_dir_mask(x,y+1) != 0: return true
	return false

func _dist2(a:Vector2i, b:Vector2i) -> int:
	var dx := a.x-b.x
	var dy := a.y-b.y
	return dx*dx + dy*dy

func _kmeans(points: Array, k:int, iters:int=16) -> Array:
	k = max(1, min(k, points.size()))
	var rng := RandomNumberGenerator.new(); rng.seed = hash("kmeans_init") ^ _seed
	var centers: Array[Vector2] = []
	var used := {}
	while centers.size() < k:
		var idx := rng.randi_range(0, points.size()-1)
		if used.has(idx): continue
		used[idx] = true
		centers.append(Vector2(points[idx]))
	var buckets := []
	for _i in range(iters):
		buckets.clear()
		buckets.resize(k)
		for bi in range(k): buckets[bi] = []
		# assign
		for p in points:
			var best := 0
			var bestd := 1e18
			for ci in range(k):
				var c := centers[ci]
				var d := (Vector2(p) - c).length_squared()
				if d < bestd: bestd = d; best = ci
			buckets[best].append(p)
		# recompute
		for ci in range(k):
			var b: Array = buckets[ci]
			if b.is_empty(): continue
			var s := Vector2.ZERO
			for p in b: s += Vector2(p)
			centers[ci] = s / float(b.size())
	return buckets

func _mst_order(points: Array) -> Array[Vector2i]:
	if points.size() <= 1: return points.duplicate()
	var in_tree := {}
	var tree_edges: Array = []  # pairs of indices
	var idx_map := {}
	for i in range(points.size()): idx_map[points[i]] = i
	var start := 0
	for i in range(points.size()):
		if points[i].x < points[start].x: start = i
	in_tree[start] = true
	while in_tree.size() < points.size():
		var best_a := -1
		var best_b := -1
		var best_d := 1e18
		for a in in_tree.keys():
			for b in range(points.size()):
				if in_tree.has(b): continue
				var d := (Vector2(points[a]) - Vector2(points[b])).length_squared()
				if d < best_d:
					best_d = d; best_a = a; best_b = b
		in_tree[best_b] = true
		tree_edges.append(Vector2i(best_a, best_b))
	return _longest_path_in_tree(points, tree_edges)

func _longest_path_in_tree(points:Array, edges:Array) -> Array[Vector2i]:
	var adj := []
	adj.resize(points.size())
	for i in range(points.size()): adj[i] = []
	for e in edges:
		var a = e.x; var b = e.y
		adj[a].append(b); adj[b].append(a)
	var farA := _bfs_far(0, adj)
	var out := _bfs_path(farA, adj)
	var farB = out[0]
	var parent = out[1]
	var path_idx: Array[int] = []
	var cur = farB
	while cur != -1:
		path_idx.push_front(cur)
		cur = parent.get(cur, -1)
	var ordered: Array[Vector2i] = []
	for id in path_idx:
		ordered.append(Vector2i(points[id]))
	return ordered

func _bfs_far(src:int, adj:Array) -> int:
	var q: Array[int] = [src]
	var qi := 0
	var seen := {}
	seen[src] = true
	var last := src
	while qi < q.size():
		var u := q[qi]; qi += 1
		last = u
		for v in adj[u]:
			if not seen.has(v):
				seen[v] = true
				q.append(v)
	return last

func _bfs_path(src:int, adj:Array) -> Array:
	var q: Array[int] = [src]
	var qi := 0
	var seen := {}
	var par := {}
	seen[src] = true
	par[src] = -1
	var last := src
	while qi < q.size():
		var u := q[qi]; qi += 1
		last = u
		for v in adj[u]:
			if not seen.has(v):
				seen[v] = true
				par[v] = u
				q.append(v)
	return [last, par]
func _d(a: Vector2i, b: Vector2i) -> float:
	return (Vector2(a) - Vector2(b)).length()
func _path_delta_insert(a: Vector2i, b: Vector2i, s: Vector2i) -> float:
	return _d(a, s) + _d(s, b) - _d(a, b)
func _dedupe_consecutive(arr: Array) -> Array:
	if arr.size() <= 1: return arr
	var out := [arr[0]]
	for i in range(1, arr.size()):
		if int(arr[i]) != int(out[out.size()-1]):
			out.append(arr[i])
	return out

func _seg_insert_cost_and_index(ids: Array, s_pos: Vector2i, spos: Dictionary) -> Dictionary:
	if ids.is_empty():
		return {"cost": 0.0, "idx": 0}
	var best_cost := 1e18
	var best_idx := 0
	var S := Vector2(s_pos)
	var head := Vector2(spos[int(ids[0])])
	var tail := Vector2(spos[int(ids[ids.size()-1])])
	var dh := (S - head).length()
	if dh < best_cost:
		best_cost = dh; best_idx = 0
	var dt := (S - tail).length()
	if dt < best_cost:
		best_cost = dt; best_idx = ids.size()
	for i in range(ids.size()-1):
		var A := Vector2(spos[int(ids[i])])
		var B := Vector2(spos[int(ids[i+1])])
		var AB := B - A
		var len2 := AB.length_squared()
		if len2 <= 0.0001:
			var d_ := (S - A).length()
			if d_ < best_cost:
				best_cost = d_; best_idx = i+1
			continue
		var t = clamp(((S - A).dot(AB) / len2), 0.0, 1.0)
		var P = A + AB * t
		var dist = (S - P).length()
		if dist < best_cost:
			best_cost = dist
			best_idx = i+1
	return {"cost": best_cost, "idx": best_idx}

func _station_pos_by_id() -> Dictionary:
	var spos := {}
	for s in _stations:
		spos[int(s["id"])] = Vector2i(s["pos"])
	return spos

func _count_interchanges() -> Dictionary:
	var per_sid := {}
	for _L in _lines:
		var seen := {}
		for sid in _L["station_ids"]:
			var k := int(sid)
			if seen.has(k): continue
			seen[k] = true
			per_sid[k] = int(per_sid.get(k, 0)) + 1
	var c := 0
	for sid in per_sid.keys():
		if int(per_sid[sid]) >= 2:
			c += 1
	return {"count": c, "by_sid": per_sid}

func _nearest_pair_between_lines(li_a:int, li_b:int, spos:Dictionary) -> Dictionary:
	var ids_a: Array = _lines[li_a]["station_ids"]
	var ids_b: Array = _lines[li_b]["station_ids"]
	var best := {"sa":-1, "sb":-1, "d2":1e18}
	for sa in ids_a:
		var pa := Vector2(spos[int(sa)])
		for sb in ids_b:
			var pb := Vector2(spos[int(sb)])
			var d2 := (pa - pb).length_squared()
			if d2 < best["d2"]:
				best = {"sa":int(sa), "sb":int(sb), "d2":d2}
	return best

func _line_contains(li:int, sid:int) -> bool:
	for s in _lines[li]["station_ids"]:
		if int(s) == sid: return true
	return false

func _parse_vec2i(v, fallback: Vector2i) -> Vector2i:
	var t := typeof(v)
	if t == TYPE_VECTOR2I:
		return v
	if t == TYPE_VECTOR2:
		return Vector2i(int(v.x), int(v.y))
	if t == TYPE_ARRAY and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	if t == TYPE_DICTIONARY and v.has("x") and v.has("y"):
		return Vector2i(int(v["x"]), int(v["y"]))
	if t == TYPE_STRING:
		var s := String(v)
		s = s.strip_edges()
		s = s.replace("Vector2i", "").replace("(", "").replace(")", "")
		var parts := s.split(",", false)
		if parts.size() >= 2:
			return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))
	return fallback

func _is_valid_place_cell(c: Vector2i) -> bool :
	if c.x < 0 or c.y < 0 or c.x >= _w or c.y >= _h: return false
	if _is_road(c.x,c.y): return false
	return true

func _nearest_valid_place_cell(from: Vector2i, max_radius:int = 8) -> Vector2i:
	if _is_valid_place_cell(from): return from
	for r in range(1, max_radius + 1):
		for dy in range(-r, r+1):
			for dx in range(-r, r+1):
				if abs(dx) != r and abs(dy) != r: continue
				var p := Vector2i(from.x + dx, from.y + dy)
				if p.x < 0 or p.y <0 or p.x >= _w or p.y >= _h : continue
				if _is_valid_place_cell(p) : return p
	return Vector2i(-1, -1)
