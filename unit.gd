# Base Unit class (used for both player and enemy units)
extends CharacterBody2D

signal died(unit)

# Team: "player", "friendly", "enemy"
@export var side: String = "enemy"

# Class id: "warrior", "lancer", "archer", "monk"
var class_id: String = "warrior"

# Core stats
var max_hp: int = 1
var hp: int = 1
var move_range: int = 1
var attack_range: int = 1
var damage: int = 1

# Economy drop (for enemies)
@export var coin_value: int = 1
@export var is_captain: bool = false

# Grid position (managed by GameManager)
var grid_pos: Vector2i = Vector2i.ZERO

# Turn-state flags
var moved_this_turn: bool = false
var guard_active: bool = false

func init_stats_for_class(id: String) -> void:
	class_id = id
	match id:
		"warrior":
			max_hp = 4; hp = max_hp
			move_range = 1
			attack_range = 1
			damage = 2
		"lancer":
			max_hp = 3; hp = max_hp
			move_range = 2
			attack_range = 1
			damage = 2
		"archer":
			max_hp = 2; hp = max_hp
			move_range = 1
			attack_range = 3
			damage = 2
		"monk":
			max_hp = 3; hp = max_hp
			move_range = 1
			attack_range = 1
			damage = 1
		_:
			# fallback
			max_hp = 2; hp = max_hp
			move_range = 1
			attack_range = 1
			damage = 1

func reset_turn_flags() -> void:
	moved_this_turn = false
	guard_active = false

func get_attack_damage() -> int:
	var base := damage
	if class_id == "lancer" and moved_this_turn:
		# Lancer Special (Charge): +1 damage if moved earlier this turn, then attacks
		base += 1
	return base

func take_damage(amount: int) -> void:
	var inc := amount
	if guard_active:
		# Warrior Guard: reduces damage by 2 until next turn
		inc = max(0, amount - 2)
	hp -= inc
	if hp <= 0:
		emit_signal("died", self)
		queue_free()

# Specials are triggered via GameManager; helpers below encapsulate effects.

func activate_guard() -> void:
	# Warrior Guard
	guard_active = true

func can_heal_target(target: Node) -> bool:
	return class_id == "monk" and target is CharacterBody2D and side != "enemy"

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

# Simple enemy AI placeholder (unchanged)
func apply_enemy_ai():
	# Deterministic enemy logic placeholder
	pass

# Legacy rules API (kept for compatibility; no-ops here)
func apply_rules(_rules: Array):
	pass
