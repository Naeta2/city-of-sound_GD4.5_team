extends Node

func seed_if_empty(player_id: StringName) -> void:
	if PlaceRepo.list_ids().size() > 0: return
	var venue_id := PlaceRepo.create_place(&"venue", "Le Petit Club", {
		"pos": Vector2(200, 40),
		"account_id": EconomyService.create_account(1000, &"acct:venue_petit_club"),
		#"owner_agent_id": ...
	})
	var home_id := PlaceRepo.create_place(&"home", "Appartement du Joueur", {
		"pos": Vector2(20,30)
	})
	var studio_id := PlaceRepo.create_place(&"studio", "Studio A", {
		"pos": Vector2(120,80)
	})
	
	var player := AgentRepo.ag_get(player_id)
	if player.is_empty(): return
	var acct = player.get("account_id", StringName())
	if acct == StringName():
		var new_acct := EconomyService.create_account(200, StringName())
		AgentRepo.set_account(player_id, new_acct)
	PresenceService.set_location(player_id, home_id)
