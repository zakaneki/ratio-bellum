extends Node2D

enum State { PLAYER_INPUT, EXECUTING, ENEMY_TURN }
var current_state = State.PLAYER_INPUT

var grid_size = Vector2i(8, 8) # 8x8 unit grid
var player_units = []
var enemy_units = []
var friendly_units = []
var selected_rules = []
# One-from-each-category rule picks for the current turn
var turn_rules := {"movement":"standard","objective":"capture","misc":"three_cmd"}

# RulePanel location (Control with rule_panel.gd)
var rule_panel_path: NodePath = NodePath("/root/Main/CanvasLayer/RulePanel")
var rule_panel: Node = null

var archer_scene = preload("res://archer.tscn")
var friendly_container_path: NodePath = NodePath("/root/Main/UnitContainers/Friendly")
var enemy_container_path: NodePath = NodePath("/root/Main/UnitContainers/Enemy")
var execute_button_path: NodePath = NodePath("/root/Main/CanvasLayer/ExecuteButton")
var status_label_path: NodePath = NodePath("/root/Main/CanvasLayer/StatusLabel")
# --- NEW: unit grid vs. terrain tilemap (16px) ---
const BASE_UNIT_PX := 192                 # your sprite’s native size
var unit_cell_size: Vector2i = Vector2i(BASE_UNIT_PX, BASE_UNIT_PX) # per-grid-cell pixel size
var unit_scale: float = 1.0               # scale to apply to unit scenes so they fit the cell
var grid_origin: Vector2 = Vector2.ZERO   # top-left pixel where the 8x8 grid starts
# --- end NEW ---

var hovered_cell: Vector2i = Vector2i(-1, -1) # Track which cell is hovered
const COMMANDS_PER_TURN := 3
var commands_remaining: int = COMMANDS_PER_TURN
var coins: int = 0
var turn_index: int = 0

# Simple roster definitions (stats applied on spawn)
const ROSTER := ["warrior", "lancer", "archer", "monk"]
const RECRUIT_COST := {
	"warrior": 5,
	"lancer": 4,
	"archer": 3,
	"monk": 6
}
const MAX_ACTIVE_UNITS := 3
# Simple player spawn cells (left edge)
var player_spawn_cells := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
# Occupancy map: cell -> unit Node
var occupied: Dictionary = {}
func _ready():
	
	_init_grid()
	_compute_grid_layout()
	_spawn_units()
	_spawn_friendly_units()
	set_process_input(true) # Enable input processing
	rule_panel = get_node_or_null(rule_panel_path)
		# Randomize rules for the turn
	if rule_panel:
		rule_panel.call("randomize_rules")
		_on_rules_committed(rule_panel.call("get_selected_rules"))
	if rule_panel:
		rule_panel.connect("rules_committed", Callable(self, "_on_rules_committed"))
		# First roll for the first player turn
		rule_panel.call("randomize_rules")
		_on_rules_committed(rule_panel.call("get_selected_rules"))
	# NEW: hook Execute button
	var exec_btn := get_node_or_null(execute_button_path) as Button
	if exec_btn:
		exec_btn.pressed.connect(_on_execute_pressed)
	_start_player_turn()
	# Redraw grid overlay with any UI changes
	queue_redraw()
	_update_status()

func _input(event):
	if event is InputEventMouseMotion:
		var mouse_pos = event.position
		var cell = world_to_grid(mouse_pos)
		if cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y:
			hovered_cell = cell
		else:
			hovered_cell = Vector2i(-1, -1)
		queue_redraw() # Request redraw

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local = world_pos - grid_origin
	var cell_x = int(local.x / unit_cell_size.x)
	var cell_y = int(local.y / unit_cell_size.y)
	return Vector2i(cell_x, cell_y)

func _draw():
	# Draw grid lines
	var grid_color = Color(0.5, 0.5, 0.5, 0.7) # Light gray
	for x in range(grid_size.x + 1):
		var start = grid_origin + Vector2(x * unit_cell_size.x, 0)
		var end = grid_origin + Vector2(x * unit_cell_size.x, grid_size.y * unit_cell_size.y)
		draw_line(start, end, grid_color, 1)
	for y in range(grid_size.y + 1):
		var start = grid_origin + Vector2(0, y * unit_cell_size.y)
		var end = grid_origin + Vector2(grid_size.x * unit_cell_size.x, y * unit_cell_size.y)
		draw_line(start, end, grid_color, 1)
		
	if hovered_cell.x >= 0 and hovered_cell.y >= 0:
		var top_left = grid_to_world(hovered_cell, false)
		var rect = Rect2(top_left, Vector2(unit_cell_size))
		draw_rect(rect, Color(1, 1, 0, 0.5), false, 2) # Yellow border, thickness 2

func _process(_delta):
	match current_state:
		State.PLAYER_INPUT:
			pass
		State.EXECUTING:
			# Player commands are executed immediately; no queued resolution here.
			current_state = State.ENEMY_TURN
		State.ENEMY_TURN:
			for unit in enemy_units:
				unit.apply_enemy_ai()
			_check_win_lose()
			current_state = State.PLAYER_INPUT
			_start_player_turn() # NEW: roll new rules each player turn
			_update_status()

func _update_status() -> void:
	var lbl := get_node_or_null(status_label_path) as Label
	if lbl:
		var side := "Enemy" if current_state == State.ENEMY_TURN else "Player"
		lbl.text = "Turn %d — %s | Commands: %d/%d | Coins: %d" % [
			turn_index, side, commands_remaining, COMMANDS_PER_TURN, coins
		]
		
func _init_grid():
	# Keep your 16px TileMap as-is; unit grid works independently.
	pass

# --- NEW: layout helpers ---
func _compute_grid_layout():
	# Option A: keep 192px per cell (may not fit vertically): comment next 3 lines and set unit_scale = 1.0
	# Option B (default): auto-scale so 8x8 fits the viewport.
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var cell_px := int(floor(min(vp_size.x / grid_size.x, vp_size.y / grid_size.y)))
	unit_cell_size = Vector2i(cell_px, cell_px)
	unit_scale = float(cell_px) / float(BASE_UNIT_PX)

	var board_px := Vector2(grid_size.x * unit_cell_size.x, grid_size.y * unit_cell_size.y)
	grid_origin = (vp_size - board_px) * 0.5

func grid_to_world(cell: Vector2i, align_center := true) -> Vector2:
	var pos := grid_origin + Vector2(cell.x * unit_cell_size.x, cell.y * unit_cell_size.y)
	if align_center:
		pos += Vector2(unit_cell_size) * 0.5
	return pos
# --- end NEW ---

# Spawns 2 random player units; max field units = 3
func _spawn_units():
	# Clear any existing player units
	for u in player_units:
		if is_instance_valid(u):
			vacate_cell(u.grid_pos)
	player_units.clear()

	var choices := ROSTER.duplicate()
	choices.shuffle()
	var to_spawn := choices.slice(0, 2)

	for i in range(to_spawn.size()):
		var pos = player_spawn_cells[i % player_spawn_cells.size()]
		var unit = archer_scene.instantiate()
		unit.scale = Vector2.ONE * unit_scale
		unit.position = grid_to_world(pos, true)
		unit.side = "player"
		unit.init_stats_for_class(to_spawn[i])
		unit.grid_pos = pos
		unit.died.connect(_on_unit_died)
		get_node("/root/Main/UnitContainers").add_child(unit)
		player_units.append(unit)
		occupy_cell(pos, unit)

	# Example: enemies (placeholder)
	var enemy_positions = [Vector2i(6, 6), Vector2i(7, 6)]
	for pos in enemy_positions:
		var enemy = archer_scene.instantiate()
		enemy.scale = Vector2.ONE * unit_scale
		enemy.position = grid_to_world(pos, true)
		enemy.side = "enemy"
		enemy.init_stats_for_class("warrior")
		enemy.grid_pos = pos
		enemy.coin_value = 1
		enemy.died.connect(_on_unit_died)
		var econtainer := get_node_or_null(enemy_container_path)
		(econtainer if econtainer else get_node("/root/Main")).add_child(enemy)
		enemy_units.append(enemy)
		occupy_cell(pos, enemy)

func _spawn_friendly_units():
	var friendly_positions = [Vector2i(1, 6), Vector2i(2, 6)]
	for pos in friendly_positions:
		var ally = archer_scene.instantiate()
		ally.scale = Vector2.ONE * unit_scale
		ally.position = grid_to_world(pos, true)
		ally.side = "friendly"
		ally.init_stats_for_class("warrior")
		ally.grid_pos = pos
		ally.died.connect(_on_unit_died)
		var fcontainer := get_node_or_null(friendly_container_path)
		(fcontainer if fcontainer else get_node("/root/Main")).add_child(ally)
		friendly_units.append(ally)
		occupy_cell(pos, ally)
		
func _check_win_lose():
	# TODO: Check objective-specific conditions (turn_rules.objective)
	if player_units.size() == 0:
		# Lose condition
		pass
	
	# Called when RulePanel commits a set (also used internally after randomize)
func _on_rules_committed(rules: Dictionary) -> void:
	turn_rules = rules
	# TODO: apply rule effects (movement limits, turn order, visibility, etc.) here as you implement them.

# --- NEW: Start/end of player turn hooks ---
func _start_player_turn() -> void:
	# Reset command budget
	commands_remaining = COMMANDS_PER_TURN
	# Reset per-turn flags on units
	for u in player_units:
		if is_instance_valid(u):
			u.reset_turn_flags()
	for u in friendly_units:
		if is_instance_valid(u):
			u.reset_turn_flags()
	turn_index += 1
	current_state = State.PLAYER_INPUT
	_update_status()
	queue_redraw()
	
func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y

func is_cell_free(cell: Vector2i) -> bool:
	return in_bounds(cell) and not occupied.has(cell)

func occupy_cell(cell: Vector2i, unit: Node) -> void:
	occupied[cell] = unit

func vacate_cell(cell: Vector2i) -> void:
	if occupied.has(cell):
		occupied.erase(cell)

func get_unit_at(cell: Vector2i) -> Node:
	return occupied.get(cell, null)

func _spend_command_or_fail() -> bool:
	if current_state != State.PLAYER_INPUT:
		return false
	if commands_remaining <= 0:
		return false
	commands_remaining -= 1
	_update_status()
	return true

func command_move(unit: Node, to_cell: Vector2i) -> bool:
	if not _spend_command_or_fail():
		return false
	if not is_instance_valid(unit):
		return false
	if not in_bounds(to_cell) or not is_cell_free(to_cell):
		return false
	# Enforce unit's move range (orthogonal Manhattan distance)
	var dist = abs(to_cell.x - unit.grid_pos.x) + abs(to_cell.y - unit.grid_pos.y)
	if dist <= 0 or dist > unit.move_range:
		return false
	# Move
	vacate_cell(unit.grid_pos)
	unit.grid_pos = to_cell
	unit.position = grid_to_world(to_cell, true)
	occupy_cell(to_cell, unit)
	unit.moved_this_turn = true
	return true

func _is_enemy(target: Node, of_side: String) -> bool:
	return is_instance_valid(target) and target.has_method("side") and target.side != of_side and target.side == "enemy"

func command_attack(attacker: Node, target_cell: Vector2i) -> bool:
	if not _spend_command_or_fail():
		return false
	if not is_instance_valid(attacker):
		return false
	var target := get_unit_at(target_cell)
	if not is_instance_valid(target):
		return false
	# Only attack enemies
	if target.side == attacker.side:
		return false
	# Range check (Manhattan)
	var dist = abs(target_cell.x - attacker.grid_pos.x) + abs(target_cell.y - attacker.grid_pos.y)
	if dist <= 0 or dist > attacker.attack_range:
		return false
	# TODO: Archer line-of-sight blocking by obstacles
	target.take_damage(attacker.get_attack_damage())
	return true

func command_special(unit: Node, payload = null) -> bool:
	# One command for exactly one special
	if not _spend_command_or_fail():
		return false
	if not is_instance_valid(unit):
		return false
	match unit.class_id:
		"warrior":
			unit.activate_guard()
			return true
		"lancer":
			# No direct special; lancer's bonus handled in get_attack_damage after moving this turn.
			# Let the player "brace" to clear guard or similar in future; currently no-op counts as special is not useful, so refund.
			commands_remaining += 1
			_update_status()
			return false
		"archer":
			# Focus Shot: +1 damage shot, extended range by +1 (ignores one obstacle — TODO)
			if typeof(payload) == TYPE_VECTOR2I:
				var cell := payload as Vector2i
				var target := get_unit_at(cell)
				if not is_instance_valid(target) or target.side == unit.side:
					return false
				var dist = abs(cell.x - unit.grid_pos.x) + abs(cell.y - unit.grid_pos.y)
				if dist <= 0 or dist > (unit.attack_range + 1):
					return false
				target.take_damage(unit.damage + 1)
				return true
			return false
		"monk":
			# Heal adjacent allied unit by 2
			if typeof(payload) == TYPE_VECTOR2I:
				var cell := payload as Vector2i
				var ally := get_unit_at(cell)
				if not is_instance_valid(ally) or ally.side == "enemy" or ally == unit:
					return false
				# Adjacency check
				var dist = abs(cell.x - unit.grid_pos.x) + abs(cell.y - unit.grid_pos.y)
				if dist != 1:
					return false
				ally.hp = clamp(ally.hp + 2, 0, ally.max_hp)
				return true
			return false
		_:
			return false

# --- NEW: Execute button ends player phase early (or when budget spent) ---
func _on_execute_pressed() -> void:
	if current_state != State.PLAYER_INPUT:
		return
	# End player phase immediately
	current_state = State.EXECUTING
	_update_status()

# --- NEW: Recruitment API (between turns) ---
func can_recruit(class_id: String) -> bool:
	if not ROSTER.has(class_id):
		return false
	if player_units.size() >= MAX_ACTIVE_UNITS:
		return false
	return coins >= int(RECRUIT_COST.get(class_id, 999))

func recruit_unit(class_id: String) -> bool:
	# Call this at start of turn before spending commands
	if current_state != State.PLAYER_INPUT:
		return false
	if not can_recruit(class_id):
		return false
	coins -= int(RECRUIT_COST.get(class_id, 0))
	# Find free spawn cell
	for i in range(player_spawn_cells.size()):
		var spawn = player_spawn_cells[i]
		if is_cell_free(spawn):
			var u = archer_scene.instantiate()
			u.scale = Vector2.ONE * unit_scale
			u.position = grid_to_world(spawn, true)
			u.side = "player"
			u.init_stats_for_class(class_id)
			u.grid_pos = spawn
			u.died.connect(_on_unit_died)
			get_node("/root/Main/UnitContainers").add_child(u)
			player_units.append(u)
			occupy_cell(spawn, u)
			_update_status()
			return true
	return false
# --- end NEW ---

# --- NEW: Death/economy handler ---
func _on_unit_died(unit: Node) -> void:
	# Award coins if enemy died
	if unit.side == "enemy":
		var reward := 1
		if unit.is_captain:
			reward = 3
		else:
			reward = unit.coin_value
		coins += reward
	# Remove from lists and occupancy
	vacate_cell(unit.grid_pos)
	if unit.side == "player":
		player_units.erase(unit)
	elif unit.side == "friendly":
		friendly_units.erase(unit)
	else:
		enemy_units.erase(unit)
	_update_status()
