extends Node

func seed_if_empty(player_id: StringName) -> void:
	if PlaceRepo.list_ids().size() > 0:
		return
	var club_account := EconomyService.create_account(1000, &"acct:venue_petit_club")
	var venue_id := PlaceRepo.create_place(&"venue", "Le Petit Club", {"pos": Vector2(20,40), "account_id":club_account})
	var home_id := PlaceRepo.create_place(&"home", "Appartement du Joueur", {"pos": Vector2(20,30)})
	var studio_id := PlaceRepo.create_place(&"studio", "Studio A", {"pos":Vector2(12,08)})
	CityService.sync_places_from_repo()
	
	var ag := AgentRepo.ag_get(player_id)
	if ag.is_empty():
		return
	if StringName(ag.get("account_id", StringName())) == StringName():
		var player_acct := EconomyService.create_account(200)
		AgentRepo.set_account(player_id, player_acct)
	PresenceService.set_location(player_id, home_id)
