extends VBoxContainer

signal rules_committed(rules: Dictionary)

@export var movement_label_path: NodePath
@export var objective_label_path: NodePath
@export var misc_label_path: NodePath

const MOVEMENT_RULES := [
	{id = "standard",   name = "Standard",   desc = "Units move 1 tile per Move command."},
	{id = "sprint",     name = "Sprint",     desc = "Move 2 tiles; cannot attack after sprinting."},
	{id = "teleport",   name = "Teleport",   desc = "Blink to any empty tile within 3 tiles; 2-turn cooldown."},
	{id = "momentum",   name = "Momentum",   desc = "If a unit moves, it must continue 1 more tile (unless blocked)."},
	{id = "constrained",name = "Constrained",desc = "Orthogonal moves only; no diagonals."},
	{id = "leashed",    name = "Leashed",    desc = "Player units must stay within 3 tiles of each other."},
	{id = "swarming",   name = "Swarming",   desc = "Enemies move +1 tile each turn."},
	{id = "one_step",   name = "One-step",   desc = "Each unit can only move once per 2 turns."}
]

const OBJECTIVE_RULES := [
	{id = "capture",     name = "Capture",     desc = "Occupy tile X for Y turns."},
	{id = "assassinate", name = "Assassinate", desc = "Eliminate the enemy leader."},
	{id = "survive",     name = "Survive",     desc = "Withstand attacks for T turns."},
	{id = "collect",     name = "Collect",     desc = "Bring M tokens to base."},
	{id = "race",        name = "Race",        desc = "Reach the extraction tile first."},
	{id = "area_denial", name = "Area denial", desc = "Prevent enemy on tile for T turns."},
	{id = "points",      name = "Points",      desc = "Gain points per kill; reach target score."}
]

const MISC_RULES := [
	{id = "three_cmd",      name = "Three-Command Limit", desc = "You have 3 commands per turn."},
	{id = "no_attacks",     name = "No Attacks",          desc = "No direct attacks; only interactions."},
	{id = "reflective",     name = "Reflective",          desc = "On kill, spawn a random enemy."},
	{id = "fog",            name = "Fog",                 desc = "Map hidden until explored."},
	{id = "symmetry_swap",  name = "Symmetry Swap",       desc = "Enemy shares your constraints; gets more units."},
	{id = "turn_shift",     name = "Turn Order Shift",    desc = "Enemies act before player movement."},
	{id = "gravity",        name = "Gravity",             desc = "Push off map = 1 HP loss; some moves push."},
	{id = "stubborn_ai",    name = "Stubborn AI",         desc = "Enemies ignore objective; chase nearest unit."}
]

var selected_movement := MOVEMENT_RULES[0]
var selected_objective := OBJECTIVE_RULES[0]
var selected_misc := MISC_RULES[0]

func _ready() -> void:
	randomize()
	_update_ui()

func randomize_rules() -> void:
	selected_movement = MOVEMENT_RULES[randi_range(0, MOVEMENT_RULES.size() - 1)]
	selected_objective = OBJECTIVE_RULES[randi_range(0, OBJECTIVE_RULES.size() - 1)]
	selected_misc = MISC_RULES[randi_range(0, MISC_RULES.size() - 1)]
	_update_ui()

func get_selected_rules() -> Dictionary:
	return {
		"movement": selected_movement.id,
		"objective": selected_objective.id,
		"misc": selected_misc.id
	}

func commit_rules() -> void:
	emit_signal("rules_committed", get_selected_rules())

func _update_ui() -> void:
	var m := (get_node_or_null(movement_label_path) as Label)
	var o := (get_node_or_null(objective_label_path) as Label)
	var x := (get_node_or_null(misc_label_path) as Label)
	if m: m.text = "%s — %s" % [selected_movement.name, selected_movement.desc]
	if o: o.text = "%s — %s" % [selected_objective.name, selected_objective.desc]
	if x: x.text = "%s — %s" % [selected_misc.name, selected_misc.desc]
