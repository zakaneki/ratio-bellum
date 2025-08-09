# Base Unit class (used for both player and enemy units)
extends CharacterBody2D
class_name Unit
signal died(unit)

# Team: "player", "friendly", "enemy"
var side: String = "enemy"
@export var enemy_frames: SpriteFrames
@export var friendly_frames: SpriteFrames
# Class id: "warrior", "lancer", "archer", "monk"
var class_id: String = "warrior"

# Core stats
var max_hp: int = 1
var hp: int = 1
var move_range: int = 1
var attack_range: int = 1
var damage: int = 1
var ap: int = 2 # Action Points per turn

# Economy drop (for enemies)
@export var coin_value: int = 1
@export var is_captain: bool = false

# Grid position (managed by GameManager)
var grid_pos: Vector2i = Vector2i.ZERO

# Turn-state flags
var moved_this_turn: bool = false
var sprinted_this_turn: bool = false
var move_cooldown: int = 0

func reset_turn_flags() -> void:
	moved_this_turn = false
	sprinted_this_turn = false
	if move_cooldown > 0:
		move_cooldown -= 1
	ap = 2 # Reset AP at start of turn
	update_ap_label()
	update_health_label()
	update_damage_label()

func get_attack_damage() -> int:
	return damage

func take_damage(amount: int) -> void:
	var inc := amount
	hp -= inc
	if hp <= 0:
		emit_signal("died", self)
		queue_free()
	update_health_label()

# Specials are triggered via GameManager; helpers below encapsulate effects.

func _ready() -> void:
	var sprite = $AnimatedSprite2D
	match side:
		"enemy":
			sprite.sprite_frames = enemy_frames
		"friendly":
			sprite.sprite_frames = friendly_frames
	$AnimatedSprite2D.play("idle") 

func update_ap_label():
	var label = $APLabel
	label.text = str(ap) + " AP"
	label.position = Vector2(-90, 30) # Adjust offset as needed
	label.visible = (side == "friendly") # Only show for friendly units
	
func update_health_label():
	var label = $HealthLabel
	label.text = "HP: %d" % hp
	label.position = Vector2(40, -80) # Top right of sprite, adjust as needed
	label.visible = true

func update_damage_label():
	var label = $DamageLabel
	label.text = "DMG: %d" % damage
	label.position = Vector2(-90, -80) # Top left of sprite, adjust as needed
	label.visible = true

func set_ap(value: int):
	ap = value
	update_ap_label()

func set_hp(value: int):
	hp = value
	update_health_label()

func set_damage(value: int):
	damage = value
	update_damage_label()

# Simple enemy AI placeholder (unchanged)
func apply_enemy_ai():
	# Deterministic enemy logic placeholder
	pass

# Legacy rules API (kept for compatibility; no-ops here)
func apply_rules(_rules: Array):
	pass
	

func play_attack_animation():
	var sprite = $AnimatedSprite2D
	sprite.play("attack")
	await sprite.animation_finished
	
func play_move_animation(target_pos: Vector2):
	var sprite = $AnimatedSprite2D
	sprite.play("run")
	var duration := 0.3
	var start := position
	var t := 0.0
	while t < duration:
		t += get_process_delta_time()
		position = start.lerp(target_pos, t / duration)
		await get_tree().process_frame
	position = target_pos
	sprite.play("idle")
