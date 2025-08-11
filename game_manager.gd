extends Node2D

# --- Game State ---
enum State { PLAYER_INPUT, EXECUTING, ENEMY_TURN }
var current_state = State.PLAYER_INPUT
var turn_index: int = 0
const COMMANDS_PER_TURN := 3
var commands_remaining: int = COMMANDS_PER_TURN
var coins: int = 5
var unit_mode := "move" # "move" or "attack"
var turn_rules := {"movement":"standard","objective":"capture","misc":"three_cmd"}
var turn_order_shift: bool = false

# --- UI & Panels ---
var ui_font: Font = preload("res://fonts/MedievalSharp-Regular.ttf")
var game_over_panel_scene := preload("res://game_over.tscn")
var pause_menu_scene := preload("res://pause_menu.tscn")
var pause_menu: Panel = null
var rule_panel: Node = null
var game_over_panel: Control = null
var _pause_blocker: ColorRect = null

# --- Grid & Layout ---
var grid_size = Vector2i(8, 8) # 8x8 unit grid
const BASE_UNIT_PX := 192
var unit_cell_size: Vector2i = Vector2i(BASE_UNIT_PX, BASE_UNIT_PX)
var unit_scale: float = 1.0
var grid_origin: Vector2 = Vector2.ZERO

# --- Selection & Highlights ---
var selected_unit: Node = null
var hovered_cell: Vector2i = Vector2i(-1, -1)
var reachable_cells: Array[Vector2i] = []
var swarming_unit: Node = null

# --- Colors & Visuals ---
var reach_color_normal := Color(0.2, 0.9, 0.4, 0.6)
var reach_color_tele := Color(0.6, 0.4, 0.9, 0.7)
var reach_circle_radius := 6.0

# --- Containers & Paths ---
var friendly_container_path: NodePath = NodePath("/root/Main/UnitContainers/Friendly")
var enemy_container_path: NodePath = NodePath("/root/Main/UnitContainers/Enemy")
var rule_panel_path: NodePath = NodePath("/root/Main/CanvasLayer/RulePanel")
var execute_button_path: NodePath = NodePath("/root/Main/CanvasLayer/ExecuteButton")
var status_label_path: NodePath = NodePath("/root/Main/CanvasLayer/StatusLabel")
var switch_mode_button_path: NodePath = NodePath("/root/Main/CanvasLayer/SwitchModeButton")
var mode_label_path: NodePath = NodePath("/root/Main/CanvasLayer/ModeLabel")

# --- Recruitment ---
var recruiting_class: String = ""
var recruit_cells: Array[Vector2i] = []
var recruit_buttons := {} # class_id -> Button
var recruit_button_paths := {
	"warrior": NodePath("/root/Main/CanvasLayer/RecruitPanel/Warrior"),
	"lancer": NodePath("/root/Main/CanvasLayer/RecruitPanel/Lancer"),
	"archer": NodePath("/root/Main/CanvasLayer/RecruitPanel/Archer"),
	"monk": NodePath("/root/Main/CanvasLayer/RecruitPanel/Monk"),
}

# --- Units & Occupancy ---
var friendly_units = []
var enemy_units = []
const ROSTER := ["warrior", "lancer", "archer", "monk"]
const RECRUIT_COST := {
	"warrior": 5,
	"lancer": 4,
	"archer": 4,
	"monk": 3
}
const MAX_ACTIVE_UNITS := 5
var occupied: Dictionary = {}

# --- Unit Scenes ---
var UNIT_SCENES := {
	"warrior": preload("res://warrior.tscn"),
	"lancer": preload("res://lancer.tscn"),
	"archer": preload("res://archer.tscn"),
	"monk": preload("res://monk.tscn"),
}

# --- Fog of War ---
var fog_enabled: bool = false
var fog_initialized: bool = false
var fog_revealed: Dictionary = {} # Vector2i -> true
var fog_alpha := 0.65

# --- Objectives ---
# Capture
var capture_tile: Vector2i = Vector2i(-1, -1)
var capture_turns: int = 0
const CAPTURE_REQUIRED_TURNS := 3

# Survive
var survive_turns: int = 0
const SURVIVE_REQUIRED_TURNS := 15

# Collect
var tokens_initialized: bool = false
var tokens_required: int = 3
var tokens_collected: int = 0
var tokens: Dictionary = {} # cell(Vector2i) -> true

# Area Denial
var area_denial_turns: int = 0
const AREA_DENIAL_REQUIRED_TURNS := 10

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
	pause_menu = pause_menu_scene.instantiate()
	if pause_menu:
		pause_menu.hide()
		pause_menu.connect("start_over", Callable(self, "_on_pause_start_over"))
		pause_menu.connect("main_menu", Callable(self, "_on_pause_main_menu"))
		pause_menu.connect("quit_game", Callable(self, "_on_pause_quit_game"))
		get_node("/root/Main/CanvasLayer").add_child(pause_menu)
		_pause_blocker = ColorRect.new()
		_pause_blocker.color = Color(0, 0, 0, 0.35)
		_pause_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		_pause_blocker.visible = false
		_pause_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
		get_node("/root/Main/CanvasLayer").add_child(_pause_blocker)
		_pause_blocker.move_to_front()
		pause_menu.move_to_front()
	var switch_btn := get_node_or_null(switch_mode_button_path) as Button
	var exec_btn := get_node_or_null(execute_button_path) as Button
	if switch_btn:
		switch_btn.pressed.connect(_on_switch_mode_pressed)
	_update_mode_label()
	# NEW: hook Execute button
	_spawn_units()
	if turn_order_shift:
		await _run_enemy_turn_immediate()
	if exec_btn:
		exec_btn.pressed.connect(_on_execute_pressed)
	for class_id in recruit_button_paths.keys():
		var btn := get_node_or_null(recruit_button_paths[class_id]) as Button
		if btn:
			btn.pressed.connect(func(): _on_recruit_button_pressed(class_id))
			recruit_buttons[class_id] = btn
			btn.focus_mode = Control.FOCUS_NONE  # no focus, no border
	_update_recruit_buttons()
	_start_player_turn()
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").fade_to_gameplay()
	queue_redraw()
	_update_status()

func _input(event):
	if event.is_action_pressed("ui_cancel"): # Escape key
		if pause_menu and pause_menu.visible:
			_hide_pause()
		elif pause_menu:
			_show_pause()
		return
	if pause_menu and pause_menu.visible:
		return
	if event.is_action_pressed("switch_mode"):
		_on_switch_mode_pressed()
		return
	if event.is_action_pressed("end_turn"):
		_on_execute_pressed()
		return
	var cell := Vector2i(-1, -1)
	if event.has_method("has_attribute") and event.has_attribute("position"):
		cell = world_to_grid(event.position)
	elif "position" in event:
		cell = world_to_grid(event.position)
	if event is InputEventMouseMotion:
		if cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y:
			hovered_cell = cell
		else:
			hovered_cell = Vector2i(-1, -1)
		queue_redraw() # Request redraw
	# NEW: left-click selects a friendly unit and computes reachable cells
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Disable further clicks until action finishes
		set_process_input(false)
		if recruiting_class != "":
			if not in_bounds(cell) or not recruit_cells.has(cell):
				# Cancel recruitment if clicked outside grid or non-highlighted cell
				recruiting_class = ""
				recruit_cells.clear()
				set_process_input(true)
				queue_redraw()
				return
			# Deploy unit
			var unit = _make_unit(recruiting_class, "friendly", cell)
			var fcontainer := get_node_or_null(friendly_container_path)
			(fcontainer if fcontainer else get_node("/root/Main")).add_child(unit)
			friendly_units.append(unit)
			occupy_cell(cell, unit)
			coins -= int(RECRUIT_COST.get(recruiting_class, 0))
			_update_status()
			recruiting_class = ""
			recruit_cells.clear()
			set_process_input(true)
			_update_recruit_buttons()
			unit.reset_turn_flags()
			if fog_enabled:
				_reveal_from_unit(unit)
			queue_redraw()
			return
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
				if turn_rules.get("movement") == "sprint" and unit_mode == "attack" and u.sprinted_this_turn and u.class_id != "monk":
				# Optionally show a message to the player
					set_process_input(true)
					return
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
	
	if commands_remaining > 0:
		# Draw reachable tiles for movement mode
		if selected_unit != null and reachable_cells.size() > 0 and unit_mode == "move":
			var movement_rule = turn_rules.get("movement")
			var b = _bfs_reachable(selected_unit, selected_unit.move_range)
			for c in reachable_cells:
				var col := reach_color_tele if movement_rule == "teleport" and selected_unit.tp_cooldown == 0 and not b.has(c) else reach_color_normal
				var center := grid_to_world(c, true)
				draw_circle(center, reach_circle_radius, col)

		# Draw attack arrows for attack mode
		if selected_unit != null and reachable_cells.size() > 0 and unit_mode == "attack":
			var attacker_pos := grid_to_world(selected_unit.grid_pos, true)
			var is_monk = selected_unit.class_id == "monk"
			for c in reachable_cells:
				var target_pos := grid_to_world(c, true)
				if is_monk: draw_circle(target_pos, reach_circle_radius * 5.0, Color(0.2, 1.0, 0.2, 0.7))   
				else: draw_circle(target_pos, reach_circle_radius * 5.0, Color(1, 0.2, 0.2, 0.8))     
				var mid := (attacker_pos + target_pos) * 0.5 + Vector2(0, -24)
				var arrow_color :=  Color(0.2, 1.0, 0.2, 0.8) if is_monk else Color(1, 0.2, 0.2, 0.8)
				draw_quadratic_bezier(attacker_pos, mid, target_pos, arrow_color, 3)
				# Draw arrowhead at target
				var dir := (target_pos - attacker_pos).normalized()
				var arrow_size := 12.0
				var left := target_pos - dir.rotated(0.5) * arrow_size
				var right := target_pos - dir.rotated(-0.5) * arrow_size
				draw_line(target_pos, left, arrow_color, 3)
				draw_line(target_pos, right, arrow_color, 3)
		
	if recruiting_class != "" and recruit_cells.size() > 0:
		for c in recruit_cells:
			var center := grid_to_world(c, true)
			draw_circle(center, reach_circle_radius * 1.5, Color(1, 0.8, 0.2, 0.7))
			
	if turn_rules.get("objective", "") == "collect":
		for c in tokens.keys():
			var center := grid_to_world(c, true)
			draw_circle(center, reach_circle_radius * 5.0, Color(1.0, 0.9, 0.2, 0.9)) # gold
		
		for u in friendly_units:
			if is_instance_valid(u) and u.carrying_token:
				var unit_pos := grid_to_world(u.grid_pos, true)
				var dot_offset := Vector2(-unit_cell_size.x * 0.33, 0)
				var dot_pos := unit_pos + dot_offset
				draw_circle(dot_pos, 5, Color(1.0, 0.9, 0.2, 0.95)) # small yellow dot
	
	if fog_enabled:
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var c := Vector2i(x, y)
				if not fog_revealed.has(c):
					var top_left = grid_to_world(c, false)
					var rect = Rect2(top_left, Vector2(unit_cell_size))
					draw_rect(rect, Color(0, 0, 0, fog_alpha), true)
					
	if turn_rules.get("objective", "") == "capture" and in_bounds(capture_tile):
		var top_left = grid_to_world(capture_tile, false)
		var rect = Rect2(top_left, Vector2(unit_cell_size))
		draw_rect(rect, Color(0.2, 0.8, 1, 0.4), true)
		draw_rect(rect, Color(0.2, 0.8, 1, 1.0), false, 3)
		var lbl_pos = grid_to_world(capture_tile, true) + Vector2(-unit_cell_size.x * 0.33, 0)
		draw_string(ui_font, lbl_pos, "Capture: %d/%d" % [capture_turns, CAPTURE_REQUIRED_TURNS])
	
	if turn_rules.get("objective", "") == "area_denial" and in_bounds(capture_tile):
		var top_left = grid_to_world(capture_tile, false)
		var rect = Rect2(top_left, Vector2(unit_cell_size))
		draw_rect(rect, Color(1.0, 0.3, 0.2, 0.35), true)   # soft red fill
		draw_rect(rect, Color(1.0, 0.3, 0.2, 1.0), false, 3) # red border
		var lbl_pos = grid_to_world(capture_tile, true) + Vector2(-unit_cell_size.x * 0.33, 0)
		draw_string(ui_font, lbl_pos, "Deny: %d/%d" % [area_denial_turns, AREA_DENIAL_REQUIRED_TURNS])

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
			_update_status()
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
		if selected_unit and turn_rules.get("movement") == "sprint" and selected_unit.sprinted_this_turn and selected_unit.class_id != "monk":
			# Optionally show a message to the player
			selected_unit = null
			reachable_cells.clear()
			queue_redraw()
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
	var total_commands = 4 if turn_rules.get("misc", "") == "four_cmd" else COMMANDS_PER_TURN
	if lbl:
		var side := "Enemy" if current_state == State.ENEMY_TURN else "Player"
		var base_text = "Turn %d — %s\nCommands: %d/%d\nCoins: %d" % [
			turn_index, side, commands_remaining, total_commands, coins
		]
		if turn_rules.get("objective", "") == "collect":
			base_text += "\nTokens: %d/%d" % [tokens_collected, tokens_required]
		lbl.text = base_text
	var exec_btn := get_node_or_null(execute_button_path) as Button
	if exec_btn:
		if commands_remaining == 0:
			exec_btn.add_theme_color_override("font_color", Color.hex(0x82ff97ff))
		else:
			exec_btn.remove_theme_color_override("font_color")

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
	var enemy_count = randi_range(3, 5)
	if turn_rules.get("objective", "") == "survive" or turn_rules.get("objective", "") == "area_denial":
		enemy_count += 2 # spawn 2 extra enemies
	for y in enemy_count:
		to_spawn.append(ROSTER[randi_range(0, ROSTER.size() - 1)])
	var top_rows := [0, 1]
	var enemy_cells := []
	for y in top_rows:
		for x in range(grid_size.x):
			enemy_cells.append(Vector2i(x, y))
	enemy_cells.shuffle()
	
	var captain_index := -1
	if turn_rules.get("objective", "") == "assassinate":
		captain_index = randi_range(0, to_spawn.size() - 1)
	
	for i in range(to_spawn.size()):
		var pos = enemy_cells.pop_front()
		var unit = _make_unit(to_spawn[i], "enemy", pos)
		get_node(enemy_container_path).add_child(unit)
		enemy_units.append(unit)
		occupy_cell(pos, unit)
		unit.reset_turn_flags()
		if i == captain_index:
			unit.is_captain = true
			unit.max_hp *= 2
			unit.hp = unit.max_hp
			var sprite := unit.get_node_or_null("AnimatedSprite2D")
			if sprite:
				sprite.scale *= 1.5
			unit.update_health_label()
	
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

	var spawned_cells: Array[Vector2i] = []

	for i in range(to_spawn.size()):
		# If leash is active, ensure each new unit is within 3 tiles of any already spawned friendly unit
		var pos: Vector2i = Vector2i(-1, -1)
		var leash_active = turn_rules.get("movement", "") == "leashed"
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
		unit.teleport_active_modifier = turn_rules.get("movement") == "teleport"
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
	if friendly_units.size() == 0:
		if turn_rules.get("objective", "") == "survive":
			survive_turns = 0
		show_game_over()
	elif enemy_units.size() == 0:
		show_game_over("You Won!")

func _on_rules_committed(rules: Dictionary) -> void:
	turn_rules = rules
	turn_order_shift = turn_rules.get("misc", "") == "turn_shift"
	var new_fog = turn_rules.get("misc", "") == "fog"
	if new_fog != fog_enabled:
		fog_enabled = new_fog
		if fog_enabled:
			fog_initialized = false
		else:
			fog_revealed.clear()
			fog_initialized = false
		queue_redraw()
		
	if turn_rules.get("objective", "") == "capture":
		var candidates := []
		for y in range(0, 4):
			for x in range(grid_size.x):
				candidates.append(Vector2i(x, y))
		capture_tile = candidates[randi_range(0, candidates.size() - 1)]
		capture_turns = 0
	
	if turn_rules.get("objective", "") == "survive":
		survive_turns = 0
		
	if turn_rules.get("objective", "") == "collect":
		tokens_initialized = false
		tokens_collected = 0
		tokens.clear()
		
	if turn_rules.get("objective", "") == "area_denial":
		var candidates: Array[Vector2i] = []
		for y in range(grid_size.y - 2, grid_size.y):
			for x in range(grid_size.x):
				var c := Vector2i(x, y)
				if is_cell_free(c):
					candidates.append(c)
		capture_tile = candidates[randi_range(0, candidates.size() - 1)]
		area_denial_turns = 0
		queue_redraw()

func _run_enemy_turn_immediate() -> void:
	set_process_input(false)
	enemy_turn_running = true
	current_state = State.ENEMY_TURN
	_update_status()
	await _enemy_take_turn_greedy()
	_check_win_lose()
	enemy_turn_running = false
	set_process_input(true)

func _start_player_turn() -> void:
	# Reset command budget
	if turn_rules.get("misc", "") == "four_cmd":
		commands_remaining = 4
	else:
		commands_remaining = COMMANDS_PER_TURN
	# Reset per-turn flags on units
	for u in friendly_units:
		if is_instance_valid(u):
			u.reset_turn_flags()
	if fog_enabled:
		if not fog_initialized:
			_fog_reset_initial()
	_update_enemy_visibility()
	
	if turn_rules.get("objective", "") == "collect" and not tokens_initialized:
		_collect_init_tokens()
		tokens_initialized = true
		queue_redraw()
	
	if turn_rules.get("objective", "") == "capture":
		var captured := false
		for u in friendly_units:
			if is_instance_valid(u) and u.grid_pos == capture_tile:
				captured = true
				break
		if captured:
			capture_turns += 1
		else:
			capture_turns = 0
		if capture_turns >= CAPTURE_REQUIRED_TURNS:
			show_game_over("You captured the objective!")
			
	if turn_rules.get("objective", "") == "area_denial":
		# If any enemy stands on the tile now, immediate loss
		for e in enemy_units:
			if is_instance_valid(e) and e.grid_pos == capture_tile:
				show_game_over("Enemies seized the zone!")
				return
		# Otherwise, you successfully denied it for another turn
		area_denial_turns += 1
		if area_denial_turns >= AREA_DENIAL_REQUIRED_TURNS:
			show_game_over("You denied the area!")
			return
	
	# Remove previous swarming bonus
	if swarming_unit and is_instance_valid(swarming_unit):
		swarming_unit.move_range = max(1, swarming_unit.move_range - 1)
		swarming_unit = null

	# Apply swarming if active
	if turn_rules.get("movement", "") == "swarming" and enemy_units.size() > 0:
		var candidates = []
		for e in enemy_units:
			if is_instance_valid(e):
				candidates.append(e)
		if candidates.size() > 0:
			swarming_unit = candidates[randi_range(0, candidates.size() - 1)]
			swarming_unit.move_range += 1
	if not turn_order_shift: turn_index += 1
	
	if turn_rules.get("objective", "") == "survive":
		survive_turns += 1
		if survive_turns >= SURVIVE_REQUIRED_TURNS:
			show_game_over("You survived!")
			
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
	var rule = turn_rules.get("movement")
	match rule:
		"sprint": 
			if dist <= 0 or dist > 2: return false
		"teleport":
			if dist <= 0 or dist > 3: return false
		"one_step":
			if unit.move_cd > 0: return false
			if dist <= 0 or dist > unit.move_range: return false
		_:
			if dist <= 0 or dist > unit.move_range: return false
	if not _spend_command_or_fail():
		return false
	# Move
	var b = _bfs_reachable(selected_unit, selected_unit.move_range)
	if rule == "teleport" and not b.has(to_cell):
		unit.tp_cooldown = 3
		unit.update_coin_cd_label()
	if rule == "one_step":
		unit.move_cd = 2 
	var target_pos = grid_to_world(to_cell, true)
	await unit.play_move_animation(target_pos)
	vacate_cell(unit.grid_pos)
	unit.grid_pos = to_cell
	unit.position = target_pos
	occupy_cell(to_cell, unit)
	unit.ap -= 1
	unit.update_ap_label()
	if unit.class_id == "lancer":
		unit.damage += 1
		unit.update_damage_label()
	if turn_rules.get("objective", "") == "collect" and unit.side == "friendly":
		# Pick up if stepping onto a token and not already carrying
		if not unit.carrying_token and tokens.has(unit.grid_pos):
			tokens.erase(unit.grid_pos)
			unit.carrying_token = true
			queue_redraw()
		# Deposit if carrying and in base (bottom two rows)
		if unit.carrying_token and _is_base(unit.grid_pos):
			unit.carrying_token = false
			tokens_collected += 1
			_update_status()
			if tokens_collected >= tokens_required:
				show_game_over("You collected the required tokens!")
	if(turn_rules.get("movement") == "sprint"): unit.sprinted_this_turn = true
	if fog_enabled:
		_reveal_from_unit(unit)
		queue_redraw()
	return true

func command_attack(attacker: Node, target_cell: Vector2i) -> bool:
	if not is_instance_valid(attacker):
		return false
	var target := get_unit_at(target_cell)
	if not is_instance_valid(target):
		return false
	if turn_rules.get("movement") == "sprint" and attacker.sprinted_this_turn and attacker.class_id != "monk":
		return false
	var dist = abs(target_cell.x - attacker.grid_pos.x) + abs(target_cell.y - attacker.grid_pos.y)
	if attacker.class_id == "monk":
		if dist < 0 or dist > attacker.attack_range:
			return false
		if target.side != "friendly":
			return false
		if target.hp >= target.max_hp:
			return false
		if not _spend_command_or_fail():
			return false
		var global_target_pos = grid_to_world(target_cell, true)
		await attacker.play_attack_animation(global_target_pos)
		target.hp = clamp(target.hp + attacker.damage, 0, target.max_hp)
		target.update_health_label()
		attacker.ap -= 1
		attacker.update_ap_label()
		return true
	if dist <= 0 or dist > attacker.attack_range:
		return false
	# Only attack enemies
	if target.side == attacker.side:
		return false
	if not _spend_command_or_fail():
		return false
	if attacker.class_id == "archer":
		var global_target_pos = grid_to_world(target_cell, true)
		await attacker.play_attack_animation(global_target_pos)
	else:
		await attacker.play_attack_animation()
	target.take_damage(attacker.get_attack_damage())
	attacker.ap -= 1
	attacker.update_ap_label()
	return true

func _on_execute_pressed() -> void:
	if current_state != State.PLAYER_INPUT:
		return
	current_state = State.EXECUTING
	_update_status()
	
func can_recruit(class_id: String) -> bool:
	if not ROSTER.has(class_id):
		return false
	if friendly_units.size() >= MAX_ACTIVE_UNITS:
		return false
	return coins >= int(RECRUIT_COST.get(class_id, 999))

func _on_unit_died(unit: Node) -> void:
	if unit.side == "enemy":
		coins += unit.coin_value
		_update_recruit_buttons()
		if turn_rules.get("misc", "") == "reflective":
			var top_rows := [0, 1]
			var spawn_cells := []
			for y in top_rows:
				for x in range(grid_size.x):
					var cell := Vector2i(x, y)
					if is_cell_free(cell):
						spawn_cells.append(cell)
			if spawn_cells.size() > 0:
				var spawn_cell = spawn_cells[randi_range(0, spawn_cells.size() - 1)]
				var class_id = ROSTER[randi_range(0, ROSTER.size() - 1)]
				var new_enemy = _make_unit(class_id, "enemy", spawn_cell)
				get_node(enemy_container_path).add_child(new_enemy)
				enemy_units.append(new_enemy)
				occupy_cell(spawn_cell, new_enemy)
				new_enemy.reset_turn_flags()
		if turn_rules.get("objective", "") == "assassinate" and unit.is_captain:
			show_game_over("You killed the enemy leader!")
			return
	if turn_rules.get("objective", "") == "collect" and unit.side == "friendly" and unit.carrying_token:
		tokens[unit.grid_pos] = true
		queue_redraw()
	vacate_cell(unit.grid_pos)
	if unit.side == "friendly":
		friendly_units.erase(unit)
	else:
		enemy_units.erase(unit)
	_update_status()
	_check_win_lose()
# --- helpers for movement rules and reachability ---

func _compute_reachable_cells(u: Node) -> Array[Vector2i]:
	if unit_mode == "attack":
		return _bfs_attack_reachable(u, u.attack_range)
	var rule = turn_rules.get("movement")
	match rule:
		"standard":
			return _reachable_standard(u)
		"sprint":
			return _reachable_sprint(u)
		"teleport":
			return _reachable_teleport(u)
		"leashed":
			return _reachable_leashed(u)
		"one_step":
			return _reachable_one_step(u)
		_:
			# Fallback to standard
			return _reachable_standard(u)

func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	var candidates = [
		Vector2i(c.x + 1, c.y),
		Vector2i(c.x - 1, c.y),
		Vector2i(c.x, c.y + 1),
		Vector2i(c.x, c.y - 1),
	]
	for n in candidates:
		if in_bounds(n):
			res.append(n)
	return res

func _reachable_standard(u: Node) -> Array[Vector2i]:
	return _bfs_reachable(u, u.move_range)

func _reachable_sprint(u: Node) -> Array[Vector2i]:
	# Sprint: exactly like standard preview but fixed max 2 tiles this command
	return _bfs_reachable(u, 2)

func _reachable_leashed(u: Node) -> Array[Vector2i]:
	var cells := _bfs_reachable(u, u.move_range)
	return _apply_leash_if_needed(u, cells)

func _reachable_one_step(u: Node) -> Array[Vector2i]:
	if u.move_cd > 0:
		return []
	return _bfs_reachable(u, u.move_range)

func _reachable_teleport(u: Node) -> Array[Vector2i]:
	if u.tp_cooldown != 0: return _bfs_reachable(u, u.move_range)
	var res: Array[Vector2i] = []
	var radius := 3
	for y in range(max(0, u.grid_pos.y - radius), min(grid_size.y, u.grid_pos.y + radius + 1)):
		for x in range(max(0, u.grid_pos.x - radius), min(grid_size.x, u.grid_pos.x + radius + 1)):
			var c := Vector2i(x, y)
			if c == u.grid_pos:
				continue
			if abs(c.x - u.grid_pos.x) + abs(c.y - u.grid_pos.y) <= radius and is_cell_free(c):
				res.append(c)
	var res_t : Dictionary
	for elem in res:
		res_t[elem] = true
	var bfs = _bfs_reachable(u, u.move_range)
	for elem in bfs:
		res_t[elem] = true
	return Array(res_t.keys(), TYPE_VECTOR2I, "", null)

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
	if u.class_id == "monk":
		if u.hp < u.max_hp:
			results.append(u.grid_pos)
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
				if u.class_id == "monk":
					if is_instance_valid(target) and target.side == "friendly" and target.hp < target.max_hp:
						results.append(n)
				elif is_instance_valid(target) and target.side == "enemy":
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

const AI_MAX_ENEMY_MOVES := 3
const AI_W_ALIVE := 100
const AI_W_HP := 12
const AI_W_DMG := 15
const AI_W_PROX := 10.0      # proximity weight
const AI_W_HEAL := 5.0       # heal potential weight
const AI_W_FINISH := 20.0    # finishing a low-HP target now
const AI_W_THREAT := 2.0    # being in many enemy ranges is bad
const AI_W_AP_ATTACK_NOW = 8.0
const AI_W_AP_MOVE_ATTACK = 6.0

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
		# Fallback: if no move is best move, check if attack/heal is possible
		if best_move.type == "move" and best_move.has("to"):
			var piece = null
			var dest_piece = piece_at(snapshot, best_move.to)
			for p in snapshot.pieces:
				if p.id == best_move.unit_id:
					piece = p
					break
			if piece != null and dest_piece != {} and piece.id == dest_piece.id:
				# This is a "do nothing" move (move to own cell)
				var attack_moves := []
				for mv2 in moves:
					if mv2.type == "attack":
						attack_moves.append(mv2)
				attack_moves.shuffle()
				if attack_moves.size() > 0:
					best_move = attack_moves[0]
		# Record and apply into snapshot so next pick accounts for it
		plan.append(best_move)
		_ai_sim_apply_move(snapshot, best_move)
	if turn_order_shift: 	
		turn_index += 1
		_update_status()
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
			"range": u.attack_range,
			"class_id": u.class_id
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
			"range": u.attack_range,
			"class_id": u.class_id
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
			if c == p.pos and p.class_id != "monk": continue
			var man = abs(c.x - p.pos.x) + abs(c.y - p.pos.y)
			if man <= p.range:
				var tgt := piece_at(st, c)
				if p.class_id == "monk":
					# Monk: can heal friendly units (not self) with missing HP
					if tgt != {} and tgt.side == p.side and tgt.hp < tgt.max_hp:
						res.append(c)
				else:
					# Others: can attack enemy units
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
	var res: Array = [p.pos]
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
		if p.class_id == "lancer":
			p.dmg += 1
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
			
		# Monk heals (including self), others deal damage
		if p.class_id == "monk":
			# Only heal same side and only if missing HP
			if st.pieces[tgt_idx].side == p.side and int(st.pieces[tgt_idx].hp) < int(st.pieces[tgt_idx].max_hp):
				st.pieces[tgt_idx].hp = clamp(int(st.pieces[tgt_idx].hp) + int(p.dmg), 0, int(st.pieces[tgt_idx].max_hp))
				p.ap = max(0, p.ap - 1)
		else:
			# Damage enemy
			if st.pieces[tgt_idx].side != p.side:
				st.pieces[tgt_idx].hp -= int(p.dmg)
				p.ap = max(0, p.ap - 1)
				# Kill if needed
				if int(st.pieces[tgt_idx].hp) <= 0:
					# Free occupancy and remove piece
					st.occ.erase(tgt_pos)
					st.pieces.remove_at(tgt_idx)

# Helper: per-side heal potential without double counting same target
func side_heal_potential(st: Dictionary, side: String) -> float:
	var best_heal_for := {} # target_id -> max heal from any monk
	for healer in st.pieces:
		if healer.side != side: continue
		if healer.class_id != "monk": continue
		# consider self + adjacent allies within range
		# self
		var self_missing = max(0, int(healer.max_hp) - int(healer.hp))
		if self_missing > 0:
			var self_heal = min(int(healer.dmg), self_missing)
			best_heal_for[healer.id] = max(best_heal_for.get(healer.id, 0), self_heal)
		# neighbors
		for n in _neighbors4(healer.pos):
			var tgt := piece_at(st, n)
			if tgt == {}: continue
			if tgt.side != side: continue
			var missing = max(0, int(tgt.max_hp) - int(tgt.hp))
			if missing <= 0: continue
			var heal_amt = min(int(healer.dmg), missing)
			best_heal_for[tgt.id] = max(best_heal_for.get(tgt.id, 0), heal_amt)
	var sum := 0
	for k in best_heal_for.keys():
		sum += int(best_heal_for[k])
	return float(sum)

# Evaluate state: positive is good for enemy
func _ai_evaluate_state(st: Dictionary) -> float:
	var e_alive := 0
	var p_alive := 0
	var e_hp := 0
	var p_hp := 0
	var e_dmg := 0
	var p_dmg := 0
	var proximity_score := 0.0
	var heal_score := 0.0
	var finish_score := 0.0
	var threat_penalty := 0.0
	var ap_incentive := 0.0 

	# Pre-split lists for convenience
	var enemies := []
	var players := []
	for p in st.pieces:
		if p.side == "enemy": enemies.append(p)
		else: players.append(p)

	for p in st.pieces:
		if p.side == "enemy":
			e_alive += 1
			e_hp += int(p.hp)
			var cur_ap := int(p.ap) if p.has("ap") else 0
			if p.class_id != "monk":
				e_dmg += int(p.dmg)
				for q in players:
					var dist = abs(p.pos.x - q.pos.x) + abs(p.pos.y - q.pos.y)
					if dist > 0 and dist <= int(p.range) and q.hp <= int(p.dmg):
						finish_score += AI_W_FINISH
			else:
				# Monk: average distance to wounded allies (incl. self if wounded)
				var wounded: Array = []
				for q in enemies:
					if q.hp < q.max_hp:
						wounded.append(q)
				if wounded.size() > 0:
					var t_dist := 0
					for q in wounded:
						t_dist += abs(p.pos.x - q.pos.x) + abs(p.pos.y - q.pos.y)
					var a_dist := float(t_dist) / wounded.size()
					proximity_score += AI_W_PROX / float(a_dist + 1)
					
			# Threat penalty: count how many players can hit this enemy
			var threats := 0
			for q in players:
				var d2 = abs(p.pos.x - q.pos.x) + abs(p.pos.y - q.pos.y)
				if d2 > 0 and d2 <= int(q.range):
					if(q.class_id != "monk"): threats += 1
			if threats > 0:
				threat_penalty += AI_W_THREAT * float(threats)
			# For each enemy unit, compute distance to nearest player and whether it can
			# attack now or move-and-attack this turn given its cur_ap.
			if players.size() > 0 and cur_ap > 0:
				var min_dist_to_player := 100000
				for q in players:
					var d = abs(p.pos.x - q.pos.x) + abs(p.pos.y - q.pos.y)
					if d < min_dist_to_player:
						min_dist_to_player = d
				# needed_move: how many tiles we must move to be within attack range
				var needed_move = max(0, int(min_dist_to_player) - int(p.range))
				var move_per_ap = p.move
				if needed_move == 0:
				# already in attack range: need 1 AP to attack
					if cur_ap >= 1:
						ap_incentive += AI_W_AP_ATTACK_NOW
				else:
				# cannot attack from here without moving
					# number of 1-AP move actions required (ceil division)
					var move_actions_needed := int(ceil(float(needed_move) / float(move_per_ap)))
					# total AP cost to move-and-attack
					var total_ap_needed := move_actions_needed + 1  # +1 for attack
					if cur_ap >= total_ap_needed:
						var leftover_ap := cur_ap - total_ap_needed
						var s := 1.0 + float(leftover_ap) * 0.5
						ap_incentive += AI_W_AP_MOVE_ATTACK * s
		else:
			p_alive += 1
			p_hp += int(p.hp)
			if p.class_id != "monk":
				p_dmg += int(p.dmg)
	# Calculate global average proximity (enemy to player)
	var total_dist := 0
	var count := 0
	for e in enemies:
		for p in players:
			total_dist += abs(e.pos.x - p.pos.x) + abs(e.pos.y - p.pos.y)
			count += 1
	var avg_dist := float(total_dist) / count if count > 0 else 0.0
	proximity_score += AI_W_PROX / (avg_dist + 1)
	# Monk heal potential (per-side, without double counting same target)
	var enemy_heal := side_heal_potential(st, "enemy")
	var player_heal := side_heal_potential(st, "friendly")
	heal_score += enemy_heal * AI_W_HEAL
	heal_score -= player_heal * AI_W_HEAL
	var capture_bonus := 0.0
	if turn_rules.get("objective", "") == "capture" and in_bounds(capture_tile):
		for p in st.pieces:
			if p.side == "enemy":
				var dist = abs(p.pos.x - capture_tile.x) + abs(p.pos.y - capture_tile.y)
				capture_bonus += max(0, 12 - dist * 1)
	var captain_proximity_bonus := 0.0
	var enemy_cohesion_bonus := 0.0
	var captain_pos = null
	if turn_rules.get("objective", "") == "assassinate":
		# Find captain position
		for p in st.pieces:
			if p.side == "enemy" and p.has("is_captain") and p.is_captain:
				captain_pos = p.pos
				break
		if captain_pos != null:
			for p in st.pieces:
				if p.side == "enemy" and not (p.has("is_captain") and p.is_captain):
					var dist = abs(p.pos.x - captain_pos.x) + abs(p.pos.y - captain_pos.y)
					captain_proximity_bonus += max(0, 10 - dist * 2)
		# Cohesion: encourage enemies to stay close to each other
		for p in st.pieces:
			if p.side == "enemy":
				var close_count := 0
				for q in st.pieces:
					if q.side == "enemy" and p != q:
						var dist = abs(p.pos.x - q.pos.x) + abs(p.pos.y - q.pos.y)
						if dist <= 2:
							close_count += 1
				enemy_cohesion_bonus += close_count * 2
	var area_denial_bonus := 0.0
	if turn_rules.get("objective", "") == "area_denial" and in_bounds(capture_tile):
		for p in st.pieces:
			if p.side == "enemy":
				var dist = abs(p.pos.x - capture_tile.x) + abs(p.pos.y - capture_tile.y)
				# Strong incentive to approach the zone
				area_denial_bonus += max(0, 20 - dist * 3)
				# Extra if already on the tile (would win)
				if dist == 0:
					area_denial_bonus += 50
	var score := 0.0
	score += area_denial_bonus
	score += captain_proximity_bonus
	score += enemy_cohesion_bonus
	score += capture_bonus
	score += AI_W_ALIVE * float(e_alive - p_alive)
	score += AI_W_HP * float(e_hp - p_hp)
	score += AI_W_DMG * float(e_dmg - p_dmg)
	score += proximity_score
	score += finish_score
	score -= threat_penalty
	score += heal_score
	score += ap_incentive
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
		if unit.class_id == "lancer":
			unit.damage += 1
			unit.update_damage_label()
		if turn_rules.get("objective", "") == "area_denial" and unit.side == "enemy" and unit.grid_pos == capture_tile:
			show_game_over("Enemies seized the zone!")
			return
		_update_enemy_visibility()
	elif mv.type == "attack":
		var tgt_cell: Vector2i = mv.target
		var target := get_unit_at(tgt_cell)
		if unit is Monk:
			if not is_instance_valid(target):
				return
			if target.side != "enemy":
				return
			if target.hp >= target.max_hp:
				return
			var global_target_pos = grid_to_world(tgt_cell, true) # true for center of cell
			await unit.play_attack_animation(global_target_pos)
			target.hp = clamp(target.hp + unit.damage, 0, target.max_hp)
			target.update_health_label()
			unit.ap -= 1
			if fog_enabled and not fog_revealed.has(unit.grid_pos):
				fog_revealed[unit.grid_pos] = true
				_update_enemy_visibility()
			return
		if not is_instance_valid(target) or target.side == unit.side:
			return
		if unit.class_id == "archer":
			var global_target_pos = grid_to_world(tgt_cell, true)
			await unit.play_attack_animation(global_target_pos)
		else:
			await unit.play_attack_animation()
		target.take_damage(unit.get_attack_damage())
		unit.ap = max(0, unit.ap - 1)
		if fog_enabled and not fog_revealed.has(unit.grid_pos):
			fog_revealed[unit.grid_pos] = true
			_update_enemy_visibility()
		
func _update_recruit_buttons():
	for class_id in recruit_buttons.keys():
		var btn = recruit_buttons[class_id]
		# Do not disable; let _on_recruit_button_pressed gate affordability.
		btn.disabled = not can_recruit(class_id)
		var cost := int(RECRUIT_COST.get(class_id, 0))
		var room := friendly_units.size() < MAX_ACTIVE_UNITS
		var afford := coins >= cost
		btn.text = "Recruit %s (%d)" % [class_id.capitalize(), cost]
		btn.tooltip_text = (
			"Click to recruit" if (afford and room)
			else ("Not enough coins" if not afford else "Max units on field")
		)

func _on_recruit_button_pressed(class_id: String) -> void:
	if recruiting_class == class_id:
		# Cancel recruitment if same button is pressed again
		recruiting_class = ""
		recruit_cells.clear()
		queue_redraw()
		return
	if not can_recruit(class_id):
		return
	recruiting_class = class_id
	recruit_cells = []
	var leash_active = turn_rules.get("movement", "") == "leashed"
	if leash_active:
		# Collect all cells within leash range (3) of any friendly unit
		var leash_range := 3
		var candidate_cells := {}
		for ally in friendly_units:
			if not is_instance_valid(ally):
				continue
			for dy in range(-leash_range, leash_range + 1):
				for dx in range(-leash_range, leash_range + 1):
					var cell = ally.grid_pos + Vector2i(dx, dy)
					if abs(dx) + abs(dy) > leash_range:
						continue
					if is_cell_free(cell):
						candidate_cells[cell] = true
		recruit_cells = Array(candidate_cells.keys(), TYPE_VECTOR2I, "", null)
	else:
		# Default: highlight bottom two rows for placement
		var bottom_rows := [grid_size.y - 2, grid_size.y - 1]
		for y in bottom_rows:
			for x in range(grid_size.x):
				var cell := Vector2i(x, y)
				if is_cell_free(cell):
					recruit_cells.append(cell)
	queue_redraw()
	
func show_game_over(message: String = "Game Over!"):
	if game_over_panel == null:
		game_over_panel = game_over_panel_scene.instantiate()
		game_over_panel.play_again.connect(_on_play_again_pressed)
		game_over_panel.quit_game.connect(_on_quit_pressed)
		var label = game_over_panel.get_node_or_null("VBoxContainer/GameOver")
		if label:
			label.text = message
		get_node("/root/Main/CanvasLayer").add_child(game_over_panel)
	else:
		game_over_panel.visible = true

	# Disable input
	set_process_input(false)

func _on_play_again_pressed():
	# Remove game over panel and restart game
	if game_over_panel:
		game_over_panel.queue_free()
		game_over_panel = null
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_quit_pressed():
	get_tree().quit()

func _on_pause_start_over():
	get_tree().reload_current_scene()

func _on_pause_main_menu():
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").fade_to_menu()
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_pause_quit_game():
	get_tree().quit()

func _show_pause():
	if _pause_blocker: _pause_blocker.show()
	if pause_menu: pause_menu.show()

func _hide_pause():
	if pause_menu: pause_menu.hide()
	if _pause_blocker: _pause_blocker.hide()
	
func _fog_reset_initial() -> void:
	# Start fresh: reveal bottom two rows + friendly attack ranges
	fog_revealed.clear()
	var bottom_rows := [grid_size.y - 2, grid_size.y - 1]
	for y in bottom_rows:
		for x in range(grid_size.x):
			var c := Vector2i(x, y)
			if in_bounds(c):
				fog_revealed[c] = true
	# Reveal from all friendlies (their attack ranges)
	_reveal_from_all_friendlies()
	fog_initialized = true
	queue_redraw()

func _reveal_from_all_friendlies() -> void:
	for u in friendly_units:
		if is_instance_valid(u):
			_reveal_from_unit(u)

func _reveal_from_unit(u: Node) -> void:
	if not is_instance_valid(u): return
	var r := int(u.attack_range)
	# Include the unit’s own tile (optional)
	if in_bounds(u.grid_pos):
		fog_revealed[u.grid_pos] = true
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if abs(dx) + abs(dy) > r:
				continue
			var c = u.grid_pos + Vector2i(dx, dy)
			if in_bounds(c):
				fog_revealed[c] = true
	_update_enemy_visibility()

func _update_enemy_visibility():
	if not fog_enabled:
		for e in enemy_units:
			if is_instance_valid(e):
				e.visible = true
		return
	for e in enemy_units:
		if is_instance_valid(e):
			e.visible = fog_revealed.has(e.grid_pos)
			
func _is_base(cell: Vector2i) -> bool:
	return cell.y >= grid_size.y - 2

func _collect_init_tokens() -> void:
	tokens.clear()
	tokens_collected = 0
	var candidates: Array[Vector2i] = []
	for y in range(0, 4):
		for x in range(grid_size.x):
			var c := Vector2i(x, y)
			if is_cell_free(c):
				candidates.append(c)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var n = min(tokens_required + 2, candidates.size())
	for i in range(n):
		tokens[candidates[i]] = true
