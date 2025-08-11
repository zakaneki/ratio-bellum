extends Unit
class_name Warrior

var guard_active: bool = false

func _ready() -> void:
	super._ready()
	class_id = "warrior"
	max_hp = 7; hp = max_hp
	move_range = 1
	attack_range = 1
	damage = 2
	coin_value = 4
	update_health_label()
	update_damage_label()
	
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
		play_death_sfx()	
		emit_signal("died", self)
		queue_free()
	update_health_label()
		
func activate_guard() -> void:
	# Warrior Guard
	guard_active = true
	
var last_attack_anim := 1

func play_attack_animation():
	var sprite = $AnimatedSprite2D
	var anim = "attack_1" if last_attack_anim == 1 else "attack_2"
	last_attack_anim = 2 if last_attack_anim == 1 else 1
	_play_sfx_random(sfx_attack)
	sprite.play(anim)
	await sprite.animation_finished
	sprite.play("idle")
