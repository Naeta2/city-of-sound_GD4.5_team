extends Control

@onready var out : Label = $PanelContainer/Out

func _on_gen_btn_pressed() -> void:
	var a := IdService.new_id("agent")
	var s := IdService.new_id("song")
	var ev := IdService.new_id("ev")
	out.text = "agent=%s\nsong=%s\nev=%s" % [a, s, ev]
