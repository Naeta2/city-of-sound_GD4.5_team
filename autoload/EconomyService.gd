extends Node

signal account_changed(account_id: StringName, balance: int)
signal transfer_done(from_id: StringName, to_id: StringName, amount: int, reason: String)

var _balances: Dictionary = {} #account_id -> int
var _exists: Dictionary = {} #account_id -> bool

func create_account(initial:int=0, account_id:StringName=StringName()) -> StringName:
	var acct := account_id if account_id != StringName() else IdService.new_id("acct")
	_balances[acct] = initial
	_exists[acct] = true
	emit_signal("account_changed", acct, _balances[acct])
	return acct

func get_balance(account_id:StringName) -> int:
	return int(_balances.get(account_id, 0))

func deposit(account_id:StringName, amount:int, reason:String="") -> void :
	if not _exists.get(account_id, false) : return
	_balances[account_id] += amount
	emit_signal("account_changed", account_id, _balances[account_id])

func withdraw(account_id:StringName, amount:int, reason:String="") -> bool:
	if not _exists.get(account_id, false): return false
	if _balances[account_id] < amount: return false
	_balances[account_id] -= amount
	emit_signal("account_changed", account_id, _balances[account_id])
	return true

func transfer(from_id:StringName, to_id:StringName, amount:int, reason:String="") -> bool:
	if amount <= 0: return false
	if not withdraw(from_id, amount, reason): return false
	deposit(to_id, amount, reason)
	emit_signal("transfer_done", from_id, to_id, amount, reason)
	return true
