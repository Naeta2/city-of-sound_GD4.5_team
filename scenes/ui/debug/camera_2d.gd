extends Camera2D

@export var pan_speed: float = 600.0
@export var zoom_step: float = 0.1
@export var zoom_min: float = 0.2
@export var zoom_max: float = 4.0

@onready var _le_preset_name := $LineEdit
@onready var _ob_presets: OptionButton = $OptionButton

var _dragging := false
var _last_mouse := Vector2.ZERO

const PRESETS_PATH := "user://city_presets.json"

func _ready() -> void:
	_reload_presets_menu()

func _get_cs() -> Node:
	if not has_node("/root/CityService"):
		push_warning("CityService autoload not found.")
		return null
	return get_node("/root/CityService")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(zoom - Vector2(zoom_step, zoom_step))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(zoom + Vector2(zoom_step, zoom_step))
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		position -= mm.relative * (1.0/zoom.x)


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_action_pressed("ui_left"): v.x -= 1
	if Input.is_action_pressed("ui_right"): v.x += 1
	if Input.is_action_pressed("ui_up"): v.y -= 1
	if Input.is_action_pressed("ui_down"): v.y += 1
	if v != Vector2.ZERO:
		position += v.normalized() * pan_speed * delta * (1.0/zoom.x)


func _set_zoom(z: Vector2) -> void:
	var s = clamp(z.x, zoom_min, zoom_max)
	zoom = Vector2(s, s)


func _on_button_pressed() -> void:
	#var _seed := int(ledit.text)
	#var x = int(spinx.value)
	#var y = int(spiny.value)
	#var params : Dictionary = {
		#"local_density":float(spin_den.value),
		#"local_len_min":int(spin_l_min.value),
		#"local_len_max":int(spin_l_max.value),
		#"straight_bias":float(spin_s_bias.value)
	#}
	#CityService.generate(_seed, Vector2i(x,y), params)
	CityService.generate_from_exports()


func _on_reroll_btn_pressed() -> void:
	var CS = _get_cs(); if CS == null: return
	var s := int(Time.get_unix_time_from_system() + 1.0)
	CS.ex_seed = s
	CS.generate_from_exports()


func _on_save_btn_pressed() -> void:
	var CS = _get_cs(); if CS == null: return
	var n = _le_preset_name.text.strip_edges()
	if n.is_empty():
		n = "preset_" + str(Time.get_unix_time_from_system())
	var dict := _read_presets()
	dict[n] = _snapshot_params(CS)
	_write_presets(dict)
	_reload_presets_menu()
	for i in range(_ob_presets.item_count):
		if _ob_presets.get_item_text(i) == n:
			_ob_presets.select(i); break


func _on_load_btn_pressed() -> void:
	var CS = _get_cs(); if CS == null: return
	if _ob_presets.item_count == 0: return
	var n := _ob_presets.get_item_text(_ob_presets.get_selected_id())
	var dict := _read_presets()
	if not dict.has(n):
		return
	_apply_params(CS, dict[n])
	CS.generate_from_exports()

#--

func _snapshot_params(CS: Node) -> Dictionary:
	return {
		"seed": CS.ex_seed,
		"size": [CS.ex_size.x, CS.ex_size.y],
		"local_density": CS.ex_local_density,
		"local_len_min": CS.ex_local_len_min,
		"local_len_max": CS.ex_local_len_max,
		"straight_bias": CS.ex_straight_bias,
		"spur_max_len": CS.ex_spur_max_len,
		"preserve_border": CS.ex_preserve_border,
		"metro_station_count": CS.ex_metro_station_count,
		"metro_min_spacing": CS.ex_metro_min_spacing,
		"metro_lines": CS.ex_metro_lines,
		"join_dist": CS.ex_join_dist,
		"min_interchanges_total": CS.ex_min_interchanges_total,
		"target_hub_degree": CS.ex_target_hub_degree,
		"interchange_join_dist": CS.ex_interchange_join_dist,
		"hub_join_dist": CS.ex_hub_join_dist,
	}

func _apply_params(CS: Node, p: Dictionary) -> void:
	CS.ex_seed = int(p.get("seed", CS.ex_seed))
	CS.ex_size = CityService._parse_vec2i(p.get("size", CS.ex_size), CS.ex_size)
	CS.ex_local_density = float(p.get("local_density", CS.ex_local_density))
	CS.ex_local_len_min = int(p.get("local_len_min", CS.ex_local_len_min))
	CS.ex_local_len_max = int(p.get("local_len_max", CS.ex_local_len_max))
	CS.ex_straight_bias = float(p.get("straight_bias", CS.ex_straight_bias))
	CS.ex_spur_max_len = int(p.get("spur_max_len", CS.ex_spur_max_len))
	CS.ex_preserve_border = bool(p.get("preserve_border", CS.ex_preserve_border))
	CS.ex_metro_station_count = int(p.get("metro_station_count", CS.ex_metro_station_count))
	CS.ex_metro_min_spacing = float(p.get("metro_min_spacing", CS.ex_metro_min_spacing))
	CS.ex_metro_lines = int(p.get("metro_lines", CS.ex_metro_lines))
	CS.ex_join_dist = float(p.get("join_dist", CS.ex_join_dist))
	CS.ex_min_interchanges_total = int(p.get("min_interchanges_total", CS.ex_min_interchanges_total))
	CS.ex_target_hub_degree = int(p.get("target_hub_degree", CS.ex_target_hub_degree))
	CS.ex_interchange_join_dist = float(p.get("interchange_join_dist", CS.ex_interchange_join_dist))
	CS.ex_hub_join_dist = float(p.get("hub_join_dist", CS.ex_hub_join_dist))

#--

func _reload_presets_menu() -> void:
	_ob_presets.clear()
	var dict := _read_presets()
	for k in dict.keys():
		_ob_presets.add_item(str(k))

func _read_presets() -> Dictionary:
	if not FileAccess.file_exists(PRESETS_PATH):
		return {}
	var f := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}

func _write_presets(d: Dictionary) -> void:
	var f := FileAccess.open(PRESETS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write presets to %s" % PRESETS_PATH); return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
