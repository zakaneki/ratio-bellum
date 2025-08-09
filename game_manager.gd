extends Node2D

enum State { PLAYER_INPUT, EXECUTING, ENEMY_TURN }
var current_state = State.PLAYER_INPUT

var grid_size = Vector2i(8, 8) # 8x8 unit grid
var enemy_units = []
var friendly_units = []
var selected_rules = []
# Selection + highlights
var selected_unit: Node = null
var reachable_cells: Array[Vector2i] = []
# Colors/sizes
var reach_color_normal := Color(0.2, 0.9, 0.4, 0.6)
var reach_color_tele := Color(0.6, 0.4, 0.9, 0.7)
var reach_circle_radius := 6.0
# One-from-each-category rule picks for the current turn
var turn_rules := {"movement":"standard","objective":"capture","misc":"three_cmd"}

# RulePanel location (Control with rule_panel.gd)
var rule_panel_path: NodePath = NodePath("/root/Main/CanvasLayer/RulePanel")
var rule_panel: Node = null

# Preload unit scenes
var UNIT_SCENES := {
	"warrior": preload("res://warrior.tscn"),
	"lancer": preload("res://lancer.tscn"),
	"archer": preload("res://archer.tscn"),
	"monk": preload("res://monk.tscn"),
}
var friendly_container_path: NodePath = NodePath("/root/Main/UnitContainers/Friendly")
var enemy_container_path: NodePath = NodePath("/root/Main/UnitContainers/Enemy")
var execute_button_path: NodePath = NodePath("/root/Main/CanvasLayer/ExecuteButton")
var status_label_path: NodePath = NodePath("/root/Main/CanvasLayer/StatusLabel")
var switch_mode_button_path: NodePath = NodePath("/root/Main/CanvasLayer/SwitchModeButton")
var mode_label_path: NodePath = NodePath("/root/Main/CanvasLayer/ModeLabel")
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
var unit_mode := "move" # "move" or "attack"

# Simple roster definitions (stats applied on spawn)
const ROSTER := ["warrior", "lancer", "archer", "monk"]
const RECRUIT_COST := {
	"warrior": 5,
	"lancer": 4,
	"archer": 3,
	"monk": 6
}

const MAX_ACTIVE_UNITS := 3
# Occupancy map: cell -> unit Node
var occupied: Dictionary = {}

func _ready():
	_compute_grid_layout()
	set_process_input(true) # Enable input processing
	rule_panel = get_node_or_null(rule_panel_path)
	# Randomize rules for the turn
	if rule_panel:
		rule_panel.connect("rules_committed", Callable(self, "_on_rules_committed"))
		# First roll for the first player turn
		rule_panel.call("randomize_rules")
		_on_rules_committed(rule_panel.call("get_selected_rules"))
	var switch_btn := get_node_or_null(switch_mode_button_path) as Button
	if switch_btn:
		switch_btn.pressed.connect(_on_switch_mode_pressed)
	_update_mode_label()
	# NEW: hook Execute button
	_spawn_units()
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
	# NEW: left-click selects a friendly unit and computes reachable cells
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Disable further clicks until action finishes
		set_process_input(false)
		var cell := world_to_grid(event.position)
		if not in_bounds(cell):
			set_process_input(true)
			return
		# If a unit is selected and the clicked cell is in reachable_cells, move there
		if selected_unit != null and cell in reachable_cells and current_state == State.PLAYER_INPUT:
			if unit_mode == "move":
				if await command_move(selected_unit, cell):
					selected_unit = null
					reachable_cells.clear()
					queue_redraw()
				set_process_input(true)
				return
			elif unit_mode == "attack":
				if await command_attack(selected_unit, cell):
					selected_unit = null
					reachable_cells.clear()
					queue_redraw()
				set_process_input(true)
				return
		var u := get_unit_at(cell)
		if is_instance_valid(u) and u.side == "friendly" and current_state == State.PLAYER_INPUT and u.ap > 0:
			if selected_unit == u:
				# Clicked already selected unit: deselect and hide circles
				selected_unit = null
				reachable_cells.clear()
			else:
				selected_unit = u
				reachable_cells = _compute_reachable_cells(u)
			queue_redraw()
		else:
			# Clicked empty or enemy: clear selection
			selected_unit = null
			reachable_cells.clear()
			queue_redraw()
		set_process_input(true)

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
		
	 # Highlight selected unit's tile
	if selected_unit != null:
		var sel_top_left = grid_to_world(selected_unit.grid_pos, false)
		var sel_rect = Rect2(sel_top_left, Vector2(unit_cell_size))
		draw_rect(sel_rect, Color(0.2, 0.7, 1, 0.5), false, 4) # Blue border, thickness 4	
	
	# Draw reachable tiles for movement mode
	if selected_unit != null and reachable_cells.size() > 0 and unit_mode == "move":
		var movement_rule = turn_rules.get("movement")
		var col := reach_color_tele if movement_rule == "teleport" else reach_color_normal
		for c in reachable_cells:
			var center := grid_to_world(c, true)
			draw_circle(center, reach_circle_radius, col)

	# Draw attack arrows for attack mode
	if selected_unit != null and reachable_cells.size() > 0 and unit_mode == "attack":
		var attacker_pos := grid_to_world(selected_unit.grid_pos, true)
		for c in reachable_cells:
			var target_pos := grid_to_world(c, true)
			var mid := (attacker_pos + target_pos) * 0.5 + Vector2(0, -24)
			draw_quadratic_bezier(attacker_pos, mid, target_pos, Color(1, 0.2, 0.2, 0.8), 3)
			# Draw arrowhead at target
			var dir := (target_pos - attacker_pos).normalized()
			var arrow_size := 12.0
			var left := target_pos - dir.rotated(0.5) * arrow_size
			var right := target_pos - dir.rotated(-0.5) * arrow_size
			draw_line(target_pos, left, Color(1, 0.2, 0.2, 0.8), 3)
			draw_line(target_pos, right, Color(1, 0.2, 0.2, 0.8), 3)
			

func draw_quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, color: Color, width: float, steps: int = 16):
	var prev = p0
	for i in range(1, steps + 1):
		var t = float(i) / steps
		var q = (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2
		draw_line(prev, q, color, width)
		prev = q
		
var enemy_turn_running := false

func _process(_delta):
	match current_state:
		State.PLAYER_INPUT:
			enemy_turn_running = false
		State.EXECUTING:
			# Player commands are executed immediately; no queued resolution here.
			current_state = State.ENEMY_TURN
		State.ENEMY_TURN:
			if not enemy_turn_running:
				enemy_turn_running = true
				await _enemy_take_turn_greedy()
				_check_win_lose()
				current_state = State.PLAYER_INPUT
				_start_player_turn()
				_update_status()

func _on_switch_mode_pressed() -> void:
	if unit_mode == "move":
		unit_mode = "attack"
	else:
		unit_mode = "move"
	if selected_unit != null:
		reachable_cells = _compute_reachable_cells(selected_unit)
	_update_mode_label()
	queue_redraw()

func _update_mode_label() -> void:
	var lbl := get_node_or_null(mode_label_path) as Label
	if lbl:
		lbl.text = "Mode: %s" % (unit_mode.capitalize())

func _update_status() -> void:
	var lbl := get_node_or_null(status_label_path) as Label
	if lbl:
		var side := "Enemy" if current_state == State.ENEMY_TURN else "Player"
		lbl.text = "Turn %d — %s | Commands: %d/%d | Coins: %d" % [
			turn_index, side, commands_remaining, COMMANDS_PER_TURN, coins
		]

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

func _spawn_units():
	# Clear any existing units
	for u in friendly_units:
		if is_instance_valid(u):
			vacate_cell(u.grid_pos)
	friendly_units.clear()
	for u in enemy_units:
		if is_instance_valid(u):
			vacate_cell(u.grid_pos)
	enemy_units.clear()
	
	
	_spawn_friendly_units()

	# --- ENEMY UNITS ---
	var to_spawn: Array
	var enemy_count = randi_range(3, 6)
	for y in enemy_count:
		to_spawn.append(ROSTER[randi_range(0, ROSTER.size() - 1)])
	var top_rows := [0, 1]
	var enemy_cells := []
	for y in top_rows:
		for x in range(grid_size.x):
			enemy_cells.append(Vector2i(x, y))
	enemy_cells.shuffle()
	for i in range(to_spawn.size()):
		var pos = enemy_cells.pop_front()
		var unit = _make_unit(to_spawn[i], "enemy", pos)
		get_node(enemy_container_path).add_child(unit)
		enemy_units.append(unit)
		occupy_cell(pos, unit)
	
func _spawn_friendly_units():
	var friendly_positions = []
	var bottom_rows := [grid_size.y - 2, grid_size.y - 1]
	for y in bottom_rows:
		for x in range(grid_size.x):
			friendly_positions.append(Vector2i(x, y))
	friendly_positions.shuffle()

	var choices := ROSTER.duplicate()
	choices.shuffle()
	var to_spawn := choices.slice(0, 2)

	var leash_active = turn_rules.get("movement", "") == "leashed"
	var spawned_cells: Array[Vector2i] = []

	for i in range(to_spawn.size()):
		# If leash is active, ensure each new unit is within 3 tiles of any already spawned friendly unit
		var pos: Vector2i = Vector2i(-1, -1)
		if leash_active and spawned_cells.size() > 0:
			for try_pos in friendly_positions:
				var ok := false
				for other in spawned_cells:
					if abs(try_pos.x - other.x) + abs(try_pos.y - other.y) <= 3:
						ok = true
						break
				if ok:
					pos = try_pos
					break
			if pos == Vector2i(-1, -1):
				# fallback: just pick next available
				pos = friendly_positions.pop_front()
		else:
			pos = friendly_positions.pop_front()

		var unit = _make_unit(to_spawn[i], "friendly", pos)
		var fcontainer := get_node_or_null(friendly_container_path)
		(fcontainer if fcontainer else get_node("/root/Main")).add_child(unit)
		friendly_units.append(unit)
		occupy_cell(pos, unit)
		spawned_cells.append(pos)

func _make_unit(class_id: String, side: String, cell: Vector2i) -> Node:
	var scene = UNIT_SCENES.get(class_id, null)
	if not scene:
		push_error("Unknown unit class: %s" % class_id)
		return null
	var unit = scene.instantiate()
	unit.side = side
	unit.grid_pos = cell
	unit.position = grid_to_world(cell, true)
	unit.scale = Vector2.ONE * unit_scale
	unit.died.connect(_on_unit_died)
	unit.update_health_label()
	unit.update_damage_label()
	return unit
	
func _check_win_lose():
	# TODO: Check objective-specific conditions (turn_rules.objective)
	if friendly_units.size() == 0:
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
	if not is_instance_valid(unit):
		return false
	if not in_bounds(to_cell) or not is_cell_free(to_cell):
		return false
	
	# Enforce unit's move range (orthogonal Manhattan distance)
	var dist = abs(to_cell.x - unit.grid_pos.x) + abs(to_cell.y - unit.grid_pos.y)
	if dist <= 0 or dist > unit.move_range:
		return false
	if not _spend_command_or_fail():
		return false
	# Move
	var target_pos = grid_to_world(to_cell, true)
	await unit.play_move_animation(target_pos)
	vacate_cell(unit.grid_pos)
	unit.grid_pos = to_cell
	unit.position = target_pos
	occupy_cell(to_cell, unit)
	unit.ap -= 1
	unit.update_ap_label()
	if(turn_rules.get("movement") == "sprint"): unit.sprinted_this_turn = true
	return true

func command_attack(attacker: Node, target_cell: Vector2i) -> bool:
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
	if not _spend_command_or_fail():
		return false
	# TODO: Archer line-of-sight blocking by obstacles
	if attacker.class_id == "archer":
		var global_target_pos = grid_to_world(target_cell, true) # true for center of cell
		await attacker.play_attack_animation(global_target_pos)
	else:
		await attacker.play_attack_animation()
	target.take_damage(attacker.get_attack_damage())
	attacker.ap -= 1
	attacker.update_ap_label()
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
	if friendly_units.size() >= MAX_ACTIVE_UNITS:
		return false
	return coins >= int(RECRUIT_COST.get(class_id, 999))

#func recruit_unit(class_id: String) -> bool:
	## Call this at start of turn before spending commands
	#if current_state != State.PLAYER_INPUT:
		#return false
	#if not can_recruit(class_id):
		#return false
	#coins -= int(RECRUIT_COST.get(class_id, 0))
	## Find free spawn cell
	#for i in range(player_spawn_cells.size()):
		#var spawn = player_spawn_cells[i]
		#if is_cell_free(spawn):
			#var u = archer_scene.instantiate()
			#u.scale = Vector2.ONE * unit_scale
			#u.position = grid_to_world(spawn, true)
			#u.side = "friendly"
			#u.grid_pos = spawn
			#u.died.connect(_on_unit_died)
			#get_node("/root/Main/UnitContainers").add_child(u)
			#friendly_units.append(u)
			#occupy_cell(spawn, u)
			#_update_status()
			#return true
	#return false
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
	if unit.side == "friendly":
		friendly_units.erase(unit)
	else:
		enemy_units.erase(unit)
	_update_status()

# --- helpers for movement rules and reachability ---

func _compute_reachable_cells(u: Node) -> Array[Vector2i]:
	if unit_mode == "attack":
		# Use attack range for BFS, only include enemy-occupied cells
		return _bfs_attack_reachable(u, u.attack_range)
	var rule = turn_rules.get("movement")
	match rule:
		"standard":
			return _reachable_standard(u)
		"sprint":
			return _reachable_sprint(u)
		"teleport":
			return _reachable_teleport(u)
		"momentum":
			return _reachable_momentum(u)
		"constrained":
			return _reachable_constrained(u)
		"leashed":
			return _reachable_leashed(u)
		"one_step":
			return _reachable_one_step(u)
		_:
			# Fallback to standard
			return _reachable_standard(u)

func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(clamp(c.x + 1, 0, grid_size.x), c.y),
		Vector2i(clamp(c.x - 1, 0, grid_size.x), c.y),
		Vector2i(c.x, clamp(c.y + 1, 0, grid_size.y)),
		Vector2i(c.x, clamp(c.y - 1, 0, grid_size.y)),
	]

func _reachable_standard(u: Node) -> Array[Vector2i]:
	return _bfs_reachable(u, u.move_range)

func _reachable_sprint(u: Node) -> Array[Vector2i]:
	# Sprint: exactly like standard preview but fixed max 2 tiles this command
	return _bfs_reachable(u, 2)

func _reachable_constrained(u: Node) -> Array[Vector2i]:
	# Constrained: orthogonal only (already enforced by 4-neighbors)
	return _bfs_reachable(u, u.move_range)

func _reachable_leashed(u: Node) -> Array[Vector2i]:
	var cells := _bfs_reachable(u, u.move_range)
	return _apply_leash_if_needed(u, cells)

func _reachable_one_step(u: Node) -> Array[Vector2i]:
	# One-step: unit can only move once per 2 turns.
	# Requires a cooldown flag on the unit (see Unit.gd change below).
	if u.has_method("move_cooldown") and u.move_cooldown > 0:
		return []
	return _bfs_reachable(u, u.move_range)

func _reachable_teleport(u: Node) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	var radius := 3
	for y in range(max(0, u.grid_pos.y - radius), min(grid_size.y, u.grid_pos.y + radius + 1)):
		for x in range(max(0, u.grid_pos.x - radius), min(grid_size.x, u.grid_pos.x + radius + 1)):
			var c := Vector2i(x, y)
			if c == u.grid_pos:
				continue
			if abs(c.x - u.grid_pos.x) + abs(c.y - u.grid_pos.y) <= radius and is_cell_free(c):
				res.append(c)
	return res

func _reachable_momentum(u: Node) -> Array[Vector2i]:
	# Momentum: If a unit moves, it must continue in the same direction for one extra tile,
	# unless the second tile is blocked. Preview final destinations accordingly.
	var results: Array[Vector2i] = []
	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var step1 = u.grid_pos + dir
		if not in_bounds(step1) or occupied.has(step1):
			continue
		var step2 = step1 + dir
		if in_bounds(step2) and not occupied.has(step2):
			# Can continue the momentum step; destination is step2
			results.append(step2)
		else:
			# Blocked on second step; allowed to stop at step1
			results.append(step1)
	return results

func _bfs_reachable(u: Node, max_steps: int) -> Array[Vector2i]:
	var visited := {}
	var q := []
	visited[u.grid_pos] = 0
	q.append(u.grid_pos)
	var results: Array[Vector2i] = []
	while q.size() > 0:
		var cur: Vector2i = q.pop_front()
		var dist := int(visited[cur])
		for n in _neighbors4(cur):
			if not in_bounds(n):
				continue
			if visited.has(n):
				continue
			# Cannot pass through other units; can stand only on empty tiles
			if occupied.has(n):
				continue
			var nd := dist + 1
			if nd <= max_steps:
				visited[n] = nd
				q.append(n)
				if n != u.grid_pos:
					results.append(n)
	return results

func _bfs_attack_reachable(u: Node, max_steps: int) -> Array[Vector2i]:
	var visited := {}
	var q := []
	visited[u.grid_pos] = 0
	q.append(u.grid_pos)
	var results: Array[Vector2i] = []
	while q.size() > 0:
		var cur: Vector2i = q.pop_front()
		var dist := int(visited[cur])
		for n in _neighbors4(cur):
			if not in_bounds(n):
				continue
			if visited.has(n):
				continue
			var nd := dist + 1
			if nd <= max_steps:
				visited[n] = nd
				q.append(n)
				var target := get_unit_at(n)
				if is_instance_valid(target) and target.side == "enemy":
					results.append(n)
	return results

func _apply_leash_if_needed(u: Node, cells: Array[Vector2i]) -> Array[Vector2i]:
	# Leashed: destination must be within 3 tiles of at least one other friendly unit
	var allies: Array = []
	for a in friendly_units:
		if is_instance_valid(a) and a != u:
			allies.append(a)
	if allies.size() == 0:
		# No allies to leash to; allow all to avoid soft-lock
		return cells
	var filtered: Array[Vector2i] = []
	for c in cells:
		var ok := false
		for a in allies:
			if abs(c.x - a.grid_pos.x) + abs(c.y - a.grid_pos.y) <= 3:
				ok = true
				break
		if ok:
			filtered.append(c)
	return filtered

# ---------- Minimax-lite AI (returns up to 3 ordered enemy moves) ----------

const AI_MAX_ENEMY_MOVES := 3
const AI_W_ALIVE := 100
const AI_W_HP := 10
const AI_W_DMG := 15

# Public entry: compute plan and execute it during enemy turn
func _enemy_take_turn_greedy() -> void:
	# Ensure enemies have AP for their turn
	for e in enemy_units:
		if is_instance_valid(e):
			e.reset_turn_flags()
	# Build snapshot (with id->node map for execution)
	var snapshot := _ai_snapshot_state()
	var plan: Array = []
	for i in range(AI_MAX_ENEMY_MOVES):
		# Generate all legal single actions for enemy side
		var moves := _ai_generate_moves(snapshot, "enemy")
		if moves.is_empty():
			break
		# Score each move by applying it to a cloned snapshot and evaluating
		var best_move := {}
		var best_score := -INF
		for mv in moves:
			var st2 := _ai_state_clone(snapshot)
			_ai_sim_apply_move(st2, mv)
			var sc := _ai_evaluate_state(st2)
			if sc > best_score:
				best_score = sc
				best_move = mv
		if best_move.is_empty():
			break
		# Record and apply into snapshot so next pick accounts for it
		plan.append(best_move)
		_ai_sim_apply_move(snapshot, best_move)
	# Execute the planned moves live (avoid spending player commands)
	for mv in plan:
		await _ai_execute_move(snapshot, mv)


# Snapshot current scene into a lightweight state
# Returns { pieces: Array[Piece], occ: Dictionary[pos->id], id_to_node: Dictionary[id->Node] }
func _ai_snapshot_state() -> Dictionary:
	var pieces: Array = []
	var occ := {}
	var id_to_node := {}
	var next_id := 1

	for u in enemy_units:
		if not is_instance_valid(u): continue
		var id := next_id; next_id += 1
		var piece := {
			"id": id,
			"side": u.side,
			"hp": u.hp,
			"max_hp": u.max_hp if u.has_method("max_hp") else u.max_hp,
			"dmg": u.damage,
			"ap": u.ap,
			"pos": u.grid_pos,
			"move": u.move_range,
			"range": u.attack_range
		}
		pieces.append(piece)
		occ[piece.pos] = id
		id_to_node[id] = u
		
	for u in friendly_units:
		if not is_instance_valid(u): continue
		var id := next_id; next_id += 1
		var piece := {
			"id": id,
			"side": u.side,
			"hp": u.hp,
			"max_hp": u.max_hp,
			"dmg": u.damage,
			"ap": u.ap,
			"pos": u.grid_pos,
			"move": u.move_range,
			"range": u.attack_range
		}
		pieces.append(piece)
		occ[piece.pos] = id
		id_to_node[id] = u


	return { "pieces": pieces, "occ": occ, "id_to_node": id_to_node }

# Deep clone state (pieces and occ only; id_to_node is not needed during simulation)
func _ai_state_clone(st: Dictionary) -> Dictionary:
	var pcs := []
	for p in st.pieces:
		pcs.append(p.duplicate(true))
	var occ := {}
	for k in st.occ.keys():
		occ[k] = st.occ[k]
	return { "pieces": pcs, "occ": occ }

# Attackable cells: enemy-occupied cells within Manhattan distance <= range
func attack_cells(st: Dictionary, p: Dictionary) -> Array:
	if p.ap <= 0: return []
	var res: Array = []
	# Bound the search box
	for y in range(max(0, p.pos.y - p.range), min(grid_size.y, p.pos.y + p.range + 1)):
		for x in range(max(0, p.pos.x - p.range), min(grid_size.x, p.pos.x + p.range + 1)):
			var c := Vector2i(x, y)
			if c == p.pos: continue
			var man = abs(c.x - p.pos.x) + abs(c.y - p.pos.y)
			if man <= p.range:
				var tgt := piece_at(st, c)
				if tgt != {} and tgt.side != p.side:
					res.append(c)
	return res

func piece_at(st: Dictionary, pos: Vector2i) -> Dictionary:
	if not st.occ.has(pos): return {}
	var pid = st.occ[pos]
	for p in st.pieces:
		if p.id == pid: return p
	return {}

# BFS movement cells
func bfs_moves(st: Dictionary, p: Dictionary) -> Array:
	if p.ap <= 0: return []
	var max_steps = p.move
	var q := [p.pos]
	var dist := { p.pos: 0 }
	var res: Array = []
	while q.size() > 0:
		var cur: Vector2i = q.pop_front()
		var d = dist[cur]
		for n in _neighbors4(cur):
			if not in_bounds(n): continue
			if dist.has(n): continue
			# Can't go through occupied cells
			if st.occ.has(n): continue
			var nd = d + 1
			if nd <= max_steps:
				dist[n] = nd
				q.append(n)
				if n != p.pos:
					res.append(n)
	return res

# Generate legal single-action moves for a side in the given state
# Each move: { type: "move"/"attack", unit_id: int, to: Vector2i | target: Vector2i }
func _ai_generate_moves(st: Dictionary, side: String) -> Array:
	var moves: Array = []
	
	# Build moves, attacks first for better ordering
	for p in st.pieces:
		if p.side != side: continue
		if p.ap <= 0: continue

		# Attacks
		for c in attack_cells(st, p):
			moves.append({ "type": "attack", "unit_id": p.id, "target": c })

		# Moves (only a few best that approach nearest opponent)
		var mv_cells := bfs_moves(st, p)
		if mv_cells.size() > 0:
			# Score each move by min distance to any opponent after moving (lower is better)
			var scored := []
			for c in mv_cells:
				var bestd := 9999
				for q in st.pieces:
					if q.side == p.side: continue
					var d = abs(c.x - q.pos.x) + abs(c.y - q.pos.y)
					if d < bestd: bestd = d
				scored.append({ "cell": c, "score": bestd })
			scored.sort_custom(func(a, b): return int(a.score - b.score))
			for i in range(scored.size()):
				moves.append({ "type": "move", "unit_id": p.id, "to": scored[i].cell })

	return moves

# Apply a move to the simulation state
func _ai_sim_apply_move(st: Dictionary, mv: Dictionary) -> void:
	# Helper for finding piece index
	var idx := -1
	for i in range(st.pieces.size()):
		if st.pieces[i].id == mv.unit_id:
			idx = i; break
	if idx == -1:
		return
	var p = st.pieces[idx]

	if mv.type == "move":
		var to: Vector2i = mv.to
		# Remove old occ
		if st.occ.has(p.pos): st.occ.erase(p.pos)
		p.pos = to
		st.occ[to] = p.id
		p.ap = max(0, p.ap - 1)
	elif mv.type == "attack":
		var tgt_pos: Vector2i = mv.target
		if not st.occ.has(tgt_pos):
			return
		var tgt_id = st.occ[tgt_pos]
		var tgt_idx := -1
		for j in range(st.pieces.size()):
			if st.pieces[j].id == tgt_id:
				tgt_idx = j; break
		if tgt_idx == -1:
			return
		# Damage
		st.pieces[tgt_idx].hp -= p.dmg
		p.ap = max(0, p.ap - 1)
		# Kill if needed
		if st.pieces[tgt_idx].hp <= 0:
			# Free occupancy and remove piece
			st.occ.erase(tgt_pos)
			st.pieces.remove_at(tgt_idx)

# Evaluate state: positive is good for enemy
func _ai_evaluate_state(st: Dictionary) -> float:
	var e_alive := 0
	var p_alive := 0
	var e_hp := 0
	var p_hp := 0
	var e_dmg := 0
	var p_dmg := 0
	for p in st.pieces:
		if p.side == "enemy":
			e_alive += 1
			e_hp += int(p.hp)
			e_dmg += int(p.dmg)
		else:
			p_alive += 1
			p_hp += int(p.hp)
			p_dmg += int(p.dmg)
	var score := 0.0
	score += AI_W_ALIVE * float(e_alive - p_alive)
	score += AI_W_HP * float(e_hp - p_hp)
	score += AI_W_DMG * float(e_dmg - p_dmg)
	return score

func _ai_execute_move(snapshot: Dictionary, mv: Dictionary) -> void:
	var id_to_node = snapshot.get("id_to_node", {})
	var unit: Node = id_to_node.get(mv.unit_id, null)
	if unit == null or not is_instance_valid(unit):
		return
	if mv.type == "move":
		var to: Vector2i = mv.to
		# live move without spending player commands
		if not in_bounds(to) or occupied.has(to):
			return
		var target_pos = grid_to_world(to, true)
		await unit.play_move_animation(target_pos)
		vacate_cell(unit.grid_pos)
		unit.grid_pos = to
		unit.position = target_pos
		occupy_cell(to, unit)
		unit.ap = max(0, unit.ap - 1)
	elif mv.type == "attack":
		var tgt_cell: Vector2i = mv.target
		var target := get_unit_at(tgt_cell)
		if not is_instance_valid(target) or target.side == unit.side:
			return
		if unit.class_id == "archer":
			var global_target_pos = grid_to_world(tgt_cell, true)
			await unit.play_attack_animation(global_target_pos)
		else:
			await unit.play_attack_animation()
		target.take_damage(unit.get_attack_damage())
		unit.ap = max(0, unit.ap - 1)
