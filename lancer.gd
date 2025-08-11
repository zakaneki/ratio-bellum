extends Unit
class_name Lancer

func _ready() -> void:
	super._ready()
	class_id = "lancer"
	max_hp = 6; hp = max_hp
	move_range = 2
	attack_range = 1
	damage = 2
	coin_value = 3
	update_health_label()
	update_damage_label()


func reset_turn_flags():
	super.reset_turn_flags()
	damage = 2
	update_damage_label()
