extends Node2D

@export var cell_px: int = 16
@export var road_thickness: float = 3.0
@export var road_color: Color = Color(0.2,0.2,0.25)
@export var bg_grid: bool = true

const U := 1
const R := 2
const D := 4
const L := 8

func _ready() -> void:
	if has_node("/root/CityService"):
		var CS = get_node("/root/CityService")
		CS.connect("city_changed", Callable(self, "_on_city_changed"))
	_on_city_changed()

func _on_city_changed() -> void:
	queue_redraw()

func _draw() -> void:
	if not has_node("/root/CityService"): return
	var CS = get_node("/root/CityService")
	var size: Vector2i = CS.get_size()
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0: return
	# back grid
	if bg_grid:
		for y in range(h):
			for x in range(w):
				var r := Rect2(Vector2(x*cell_px, y*cell_px), Vector2(cell_px, cell_px))
				draw_rect(r, Color(0.07,0.07,0.1), false, 1.0)
	var half := cell_px * 0.5
	for y in range(h):
		for x in range(w):
			var mask = CS.get_dir_mask(x,y)
			if mask == 0: continue
			var cx := x*cell_px + half
			var cy := y*cell_px + half
			var c := Vector2(cx, cy)
			if (mask & U) != 0:
				draw_line(c, c + Vector2(0, -half), road_color, road_thickness)
			if (mask & D) != 0:
				draw_line(c, c + Vector2(0,  half), road_color, road_thickness)
			if (mask & L) != 0:
				draw_line(c, c + Vector2(-half, 0), road_color, road_thickness)
			if (mask & R) != 0:
				draw_line(c, c + Vector2( half, 0), road_color, road_thickness)
