extends Control

@onready var name_edit: LineEdit = $VBoxContainer/NameEdit
@onready var out: Label = $VBoxContainer/Out

var _agent_id: StringName
var _acct_id: StringName

func _on_create_agent_btn_pressed() -> void:
	var agent_name := name_edit.text.strip_edges()
	if agent_name.is_empty(): agent_name = "Alice"
	_agent_id = AgentRepo.create_agent(agent_name)
	_acct_id = EconomyService.create_account(50)
	AgentRepo.set_account(_agent_id, _acct_id)
	_print_status("Créé agent=%s, compte=%s, solde=%d" % [_agent_id, _acct_id, EconomyService.get_balance(_acct_id)])

func _on_deposit_btn_pressed() -> void:
	if _acct_id == StringName(): return
	EconomyService.deposit(_acct_id, 10, "debug deposit")
	_print_status("Dépôt $10 -> solde=%d" % EconomyService.get_balance(_acct_id))

func _on_withdraw_btn_pressed() -> void:
	if _acct_id == StringName(): return
	var ok := EconomyService.withdraw(_acct_id, 10, "debug withdraw")
	_print_status(("Retrait 10$ OK -> solde=%d" % EconomyService.get_balance(_acct_id)) if ok else "Retrait refusé")

func _print_status(msg:String):
	out.text = msg
