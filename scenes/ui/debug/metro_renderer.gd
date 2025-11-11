extends Node2D
@export var cell_px := 16
@export var station_radius := 4.0

func _ready():
	if has_node("/root/CityService"):
		get_node("/root/CityService").connect("city_changed", Callable(self, "_on_changed"))
	_on_changed()

func _on_changed(): queue_redraw()

func _draw():
	if not has_node("/root/CityService"): return
	var CS = get_node("/root/CityService")
	var w_h = CS.get_size()
	var lines: Array = CS._lines
	var stations: Array = CS._stations
	# index station_id -> pos
	var spos := {}
	for s in stations:
		spos[int(s["id"])] = s["pos"]
	for L in lines:
		var col: Color = L["color"]
		var ids: Array = L["station_ids"]
		for i in range(ids.size()-1):
			var a := Vector2(spos[ids[i]]) * cell_px + Vector2(cell_px*0.5, cell_px*0.5)
			var b := Vector2(spos[ids[i+1]]) * cell_px + Vector2(cell_px*0.5, cell_px*0.5)
			draw_line(a, b, col, 2.5)
	for s in stations:
		var p := Vector2(s["pos"]) * cell_px + Vector2(cell_px*0.5, cell_px*0.5)
		draw_circle(p, station_radius, Color.WHITE)
		draw_circle(p, station_radius-1.0, Color(0,0,0))
