#static data for items; read only at runtime
extends Node

static func v2i(w:int, h:int) -> Vector2i:
	return Vector2i(max(1,w), max(1,h))

static var ITEMS := {
	&"bill": {"cat":&"currency", "weight": 0.0, "dims": v2i(1,1), "stackable": true, "max_stack": 9999, "hands_required": 0},
	&"credit_stick": {"cat":&"currency","weight":0.01,"dims":v2i(1,1),"stackable":false,"hands_required":0, "default_meta": {"balance": 0, "capacity": 99999}},
	&"guitar_6": {"cat":&"instrument","weight":3.2,"dims":v2i(6,2),"stackable":false,"hands_required":2},
	&"mic_dynamic": {"cat":&"gear","weight":0.45,"dims":v2i(1,2),"stackable":false,"hands_required":0},
	&"sandwich": {"cat":&"consumable","weight":0.2,"dims":v2i(1,1),"stackable":false,"hands_required":0},
	&"pants_basic": {
		"cat":&"wearable",
		"weight":0.6,
		"dims":v2i(2,2),
		"stackable":false,
		"hands_required":0,
		"wear_slots": ["lower"],
		"provides_containers": [
			{"key_suffix":"pocket_left","type":&"pocket_small"},
			{"key_suffix":"pocket_right","type":&"pocket_small"}
		]
	},
	&"tshirt_basic": {"cat":&"wearable","weight":0.2,"dims":v2i(2,2),"stackable":false,"hands_required":0,"wear_slots":["upper_inner"],"provides_containers":[]},
	&"jacket_light": {"cat":&"wearable","weight":0.8,"dims":v2i(3,3),"stackable":false,"hands_required":0,"wear_slots":["upper_outer"],"provides_containers":[{"key_suffix":"inner_pocket","type":&"pocket_small"}]}
}

func has_it(item_id: StringName) -> bool:
	return ITEMS.has(item_id)

func get_def(item_id: StringName) -> Dictionary:
	if not ITEMS.has(item_id):
		push_error("ItemCatalog: unknown item_id %s" % item_id)
		return {}
	return ITEMS[item_id]
