extends Unit
class_name Lancer

func _ready() -> void:
	super._ready()
	class_id = "lancer"
	max_hp = 3; hp = max_hp
	move_range = 2
	attack_range = 1
	damage = 2
	update_health_label()
	update_damage_label()

func get_attack_damage() -> int:
	var base := damage
	if moved_this_turn:
		# Lancer Special (Charge): +1 damage if moved earlier this turn, then attacks
		base += 1
	return base
