extends Node

var _seq := 0
@export var prefix: String = ""

func new_id(kind: String = "") -> StringName:
	_seq += 1
	var t := Time.get_unix_time_from_system()
	var sep := ("" if kind.is_empty() else ":")
	var pfx := ("" if prefix.is_empty() else prefix + "/")
	var s := "%s%s%s_%d_%d" % [pfx, kind, sep, t, _seq]
	return StringName(s)
