extends Node

signal time_minute(abs_minutes:int)
signal hour_changed(day: int, hour:int)
signal day_changed(day: int)

@export var speed: float = 10.0 #in game minutes per real second
var paused: bool = false

const MIN_PER_HOUR := 60
const MIN_PER_DAY := 24 * MIN_PER_HOUR

var _accum := 0.0
var abs_minutes: int = 0
var _last_hour: int = 0
var _last_day: int = 0

func _ready() -> void:
	_last_day = get_day()
	_last_hour = get_hour()

func _process(delta: float) -> void:
	if paused or speed <= 0.0:
		return
	_accum += delta * speed
	while _accum >= 1.0:
		_accum -= 1.0
		abs_minutes += 1
		emit_signal("time_minute", abs_minutes)
		
		var d := get_day()
		var h := get_hour()
		if d != _last_day:
			_last_day = d
			emit_signal("day_changed", d)
		if h != _last_hour:
			_last_hour = h
			emit_signal("hour_changed", d, h)

func dump() -> Dictionary:
	return {
		"abs_minutes": abs_minutes,
		"speed": speed,
		"paused": paused
	}

func restore(d: Dictionary) -> void:
	abs_minutes = int(d.get("abs_minutes", 0))
	speed = float(d.get("speed", speed))
	paused = bool(d.get("paused", paused))
	_last_day = get_day()
	_last_hour = get_hour()

# -- helpers

func get_day() -> int :
	return int(abs_minutes / MIN_PER_DAY)

func get_minute_of_day() -> int:
	return abs_minutes % MIN_PER_DAY

func get_hour() -> int :
	return int(get_minute_of_day() / MIN_PER_HOUR)

func get_minute() -> int:
	return get_minute_of_day() % MIN_PER_HOUR

func format_hhmm() -> String:
	var h := get_hour()
	var m := get_minute()
	return "%02d:%02d" % [h, m]

func format_d_hhmm() -> String:
	return "J%02d %s" % [get_day(), format_hhmm()]

# -- controles

func set_paused(p: bool) -> void :
	paused = p

func set_speed(x: float) -> void:
	speed = max(x, 0.0)

func advance_minutes(mins:int) -> void:
	if mins <= 0: return
	var target := abs_minutes + mins
	while abs_minutes < target:
		abs_minutes += 1
		emit_signal("time_minute", abs_minutes)
		var d := get_day()
		var h := get_hour()
		if d != _last_day:
			_last_day = d
			emit_signal("day_changed", d)
		if h != _last_hour:
			_last_hour = h
			emit_signal("hour_changed", d, h)
