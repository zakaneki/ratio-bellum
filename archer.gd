extends Unit
class_name Archer

func _ready() -> void:
	super._ready()
	class_id = "archer"
	max_hp = 2; hp = max_hp
	move_range = 1
	attack_range = 3
	damage = 2
	
