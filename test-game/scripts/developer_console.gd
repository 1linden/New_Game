extends Node

const PASSWORD := "Linden"
const MAX_LEVEL := 15

var is_authenticated: bool = false
var is_console_open: bool = false
var is_password_prompt: bool = false
var god_mode_enabled: bool = false
var was_paused_before_console: bool = false
var last_scene: Node
var canvas_layer: CanvasLayer
var overlay: ColorRect
var panel: Panel
var title_label: Label
var input_line: LineEdit
var message_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	create_console_ui()


func _process(_delta: float) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == last_scene:
		return

	last_scene = current_scene
	if god_mode_enabled:
		apply_god_mode_to_current_player.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("close_menu"):
		if is_console_open:
			hide_console()
			get_viewport().set_input_as_handled()
			return

		if close_current_pause_menu():
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("console"):
		toggle_console()
		get_viewport().set_input_as_handled()
		return

func close_current_pause_menu() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	if not current_scene.has_method("is_pause_menu_open") or not current_scene.has_method("close_pause_menu"):
		return false

	if not current_scene.is_pause_menu_open():
		return false

	current_scene.close_pause_menu()
	return true


func create_console_ui() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "DeveloperConsole"
	canvas_layer.layer = 100
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas_layer)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(overlay)

	panel = Panel.new()
	panel.custom_minimum_size = Vector2(520, 120)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_top = -60
	panel.offset_right = 260
	panel.offset_bottom = 60
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	title_label = Label.new()
	title_label.text = "Developer Console"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title_label)

	input_line = LineEdit.new()
	input_line.focus_mode = Control.FOCUS_ALL
	input_line.keep_editing_on_text_submit = true
	input_line.placeholder_text = "Command"
	input_line.text_submitted.connect(_on_input_submitted)
	layout.add_child(input_line)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(message_label)

	hide_console()


func toggle_console() -> void:
	if is_console_open:
		hide_console()
		return

	if is_authenticated:
		show_command_console()
	else:
		show_password_prompt()


func show_password_prompt() -> void:
	open_console()
	is_password_prompt = true
	overlay.visible = true
	title_label.text = "Enter Developer Password"
	input_line.text = ""
	input_line.placeholder_text = "Password"
	input_line.secret = true
	message_label.text = ""
	focus_input_line.call_deferred()


func show_command_console() -> void:
	open_console()
	is_password_prompt = false
	overlay.visible = true
	title_label.text = "Developer Console"
	input_line.text = ""
	input_line.placeholder_text = "Command"
	input_line.secret = false
	message_label.text = ""
	focus_input_line.call_deferred()


func open_console() -> void:
	if not is_console_open:
		was_paused_before_console = get_tree().paused

	is_console_open = true
	get_tree().paused = true


func hide_console() -> void:
	is_console_open = false
	is_password_prompt = false
	overlay.visible = false
	input_line.release_focus()
	get_tree().paused = was_paused_before_console


func focus_input_line() -> void:
	input_line.grab_focus()
	input_line.caret_column = input_line.text.length()


func refocus_input_line() -> void:
	focus_input_line.call_deferred()


func _on_input_submitted(submitted_text: String) -> void:
	if is_password_prompt:
		submit_password(submitted_text)
	else:
		run_command(submitted_text)


func submit_password(submitted_password: String) -> void:
	if submitted_password == PASSWORD:
		is_authenticated = true
		show_command_console()
		return

	input_line.text = ""
	message_label.text = "Incorrect password"
	refocus_input_line()


func run_command(command_text: String) -> void:
	var command := command_text.strip_edges().to_lower()
	if command.is_empty():
		return

	var parts := command.split(" ", false)
	if parts.size() == 2 and parts[0] == "play":
		play_level(parts[1])
		return

	if parts.size() == 1 and parts[0] == "god":
		toggle_god_mode()
		return

	message_label.text = "Unknown command"
	input_line.text = ""
	refocus_input_line()


func play_level(level_argument: String) -> void:
	if not level_argument.begins_with("level"):
		show_command_error("Use: play level10")
		return

	var level_digits := level_argument.trim_prefix("level")
	if level_digits.is_empty() or not level_digits.is_valid_int():
		show_command_error("Use: play level10")
		return

	var level_number := int(level_digits)
	if level_number < 1 or level_number > MAX_LEVEL:
		show_command_error("Level must be 1-15")
		return

	hide_console()
	get_tree().paused = false
	var level_path := "res://levels/level_%02d.tscn" % level_number
	get_tree().change_scene_to_file(level_path)


func toggle_god_mode() -> void:
	god_mode_enabled = not god_mode_enabled
	apply_god_mode_to_current_player()
	message_label.text = "God mode on" if god_mode_enabled else "God mode off"
	input_line.text = ""
	refocus_input_line()


func apply_god_mode_to_current_player() -> void:
	var player := get_current_player()
	if player == null:
		return

	player.set("god_mode_enabled", god_mode_enabled)
	if god_mode_enabled and "health" in player and "maximum_health" in player:
		player.set("health", int(player.get("maximum_health")))
		if player.has_signal("health_changed"):
			player.health_changed.emit(int(player.get("health")))


func get_current_player() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null

	var player := current_scene.get_node_or_null("Player")
	if player != null:
		return player

	return get_tree().get_first_node_in_group("player")


func show_command_error(error_text: String) -> void:
	message_label.text = error_text
	input_line.text = ""
	refocus_input_line()
