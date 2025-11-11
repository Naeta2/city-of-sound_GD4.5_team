extends Node2D

@export var cell_px:int = 16
@export var dot_radius:float = 3.0
@export var dot_color:Color = Color(1, 0.9, 0.2)
@export var text_color:Color = Color(0.95, 0.95, 0.95)
@export var show_id:bool = false  # sinon affiche le name

func _ready() -> void:
	if has_node("/root/CityService"):
		get_node("/root/CityService").connect("city_changed", Callable(self, "_on_changed"))
	_on_changed()

func _on_changed() -> void:
	queue_redraw()

func _draw() -> void:
	if not has_node("/root/CityService"): return
	var CS = get_node("/root/CityService")
	var places: Array = CS.get_places()
	if places.is_empty(): return

	var font := ThemeDB.fallback_font
	var fsize := ThemeDB.fallback_font_size

	for p in places:
		var cell: Vector2i = p["cell"]
		var center := Vector2(cell.x * cell_px + cell_px*0.5, cell.y * cell_px + cell_px*0.5)
		draw_circle(center, dot_radius, dot_color)
		var label := String(p["id"]) if show_id else String(p.get("name", String(p["id"])))
		var pos := center + Vector2(0, dot_radius + 2.0)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fsize, text_color)
