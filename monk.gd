extends Unit
class_name Monk

func _ready() -> void:
	super._ready()
	class_id = "monk"
	max_hp = 3; hp = max_hp
	move_range = 1
	attack_range = 1
	damage = 1
	update_health_label()
	update_damage_label()

func can_heal_target(target: Node) -> bool:
	return target is CharacterBody2D and side != "enemy"
	
func heal_target(target: Node, amount: int = 2) -> bool:
	if not can_heal_target(target):
		return false
	var unit := target as Node
	if not unit or not unit.has_method("hp"):
		return false
	# Assume target is same Unit class
	var t := target as Node
	var target_hp = target.hp
	var target_max = target.max_hp
	target.hp = clamp(target_hp + amount, 0, target_max)
	return true
