extends Node

var venue_id : StringName
var home_id : StringName

func _ready() -> void:
	venue_id = PlaceRepo.create_place(&"venue", "Le Petit Club", {
		"capacity": 120,
		"pos": Vector2(200, 40),
		"account_id": EconomyService.create_account(1000, &"acct:venue_petit_club")
	})
	home_id = PlaceRepo.create_place(&"home", "Appartement du joueur", {
		"pos" : Vector2(20,30)
	})
	$DebugUI/GridContainer/SchedulerPanel.venue_id = venue_id
	$DebugUI/GridContainer/AgentPanel.home_id = home_id
	$DebugUI/GridContainer/TravelPanel.venue_id = venue_id
