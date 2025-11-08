extends Node

var venue_id : StringName
var home_id : StringName
var studio_id: StringName

func _ready() -> void:
	WorldSeed.seed_if_empty(StringName())
	$DebugUI/GridContainer/SchedulerPanel.venue_id = venue_id
	$DebugUI/GridContainer/AgentPanel.home_id = home_id
	$DebugUI/GridContainer/TravelPanel.venue_id = venue_id
