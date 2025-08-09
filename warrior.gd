extends Unit
class_name Warrior

var guard_active: bool = false

func _ready() -> void:
	super._ready()
	class_id = "warrior"
	max_hp = 4; hp = max_hp
	move_range = 1
	attack_range = 1
	damage = 2
	
func reset_turn_flags() -> void:
	super.reset_turn_flags()
	guard_active = false
	
func take_damage(amount: int) -> void:
	var inc := amount
	if guard_active:
		# Warrior Guard: reduces damage by 2 until next turn
		inc = max(0, amount - 2)
	hp -= inc
	if hp <= 0:
		emit_signal("died", self)
		queue_free()
		
func activate_guard() -> void:
	# Warrior Guard
	guard_active = true
