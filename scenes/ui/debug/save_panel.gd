extends Control

func _on_save_btn_pressed() -> void:
	SaveService.save()

func _on_load_btn_pressed() -> void:
	SaveService.load()
