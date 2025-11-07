extends Control

@onready var out: Label = $VBoxContainer/Out
@onready var name_edit: LineEdit = $VBoxContainer/NameEdit
@onready var id_edit: LineEdit = $VBoxContainer/IdEdit

func _on_create_btn_pressed() -> void:
	var agent_name := name_edit.text.strip_edges()
	if agent_name.is_empty(): agent_name = "Alice"
	var id := AgentRepo.create_agent(agent_name)
	out.text = "Créé: %s (name=%s)" % [id, agent_name]
	id_edit.text = str(id)

func _on_show_btn_pressed() -> void:
	var id := StringName(id_edit.text.strip_edges())
	var a := AgentRepo.ag_get(id)
	if a.is_empty():
		out.text = "Introuvable: %s" % [id]
		return
	out.text = "Agent %s\nkind=%s\nname=%s\nskills=%s\nneeds=%s" % [a["id"], a["kind"], a["name"], str(a["skills"]), str(a["needs"])]
