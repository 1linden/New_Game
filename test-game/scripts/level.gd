extends Node2D

const START_LEVEL_ACTIONS := [&"move_left", &"move_right", &"jump", &"sprint", &"block", &"attack"]
const FADE_SECONDS := 0.4
const BOSS_MINION_INITIAL_SHOOT_DELAY_SECONDS := 1.5
const BUTTON_SCENE: PackedScene = preload("res://scenes/button.tscn")
const TUTORIAL_TEXTS: Array[String] = [
	"Press A to Move Left and D to Move Right",
	"Hold Shift while Moving to Sprint",
	"Press W or SPACE\nto Jump",
	"Press Left Mouse Button to Attack",
	"Hold Right Mouse Button to Block",
	"Collect the Keycard\nto Advance",
]

@export var completion_scene_path: String = ""
@export var reveal_completion_items_after_enemies_defeated: bool = false
@export_range(0.0, 1.0, 0.01) var boss_minions_spawn_at_health_ratio: float = 0.0
@export var boss_minions_spawn_health_threshold: Array[float] = []

@onready var player = $Player
@onready var enemies: Node2D = get_node_or_null("Enemies") as Node2D
@onready var exit: Area2D = get_node_or_null("Exit") as Area2D
@onready var keycard: Area2D = get_node_or_null("Keycard") as Area2D
@onready var interface: CanvasLayer = $Interface
@onready var level_label: Label = $Interface/LevelLabel
@onready var pause_button: Button = $Interface/PauseButton
@onready var pause_overlay: ColorRect = $Interface/PauseOverlay
@onready var pause_panel: Panel = $Interface/PauseOverlay/PausePanel
@onready var pause_options: VBoxContainer = $Interface/PauseOverlay/PausePanel/Options
@onready var resume_button: Button = $Interface/PauseOverlay/PausePanel/Options/ResumeButton
@onready var restart_button: Button = $Interface/PauseOverlay/PausePanel/Options/RestartButton
@onready var main_menu_button: Button = $Interface/PauseOverlay/PausePanel/Options/MainMenuButton
@onready var boss_health_border: Panel = get_node_or_null("Interface/BossHealthBorder") as Panel
@onready var boss_health_bar: ProgressBar = get_node_or_null("Interface/BossHealthBar") as ProgressBar
@onready var death_overlay: ColorRect = $Interface/DeathOverlay
@onready var death_restart_button: Button = $Interface/DeathOverlay/DeathPanel/Options/RestartButton
@onready var health_hearts: Array[TextureRect] = [
	$Interface/HealthHearts/Heart1,
	$Interface/HealthHearts/Heart2,
	$Interface/HealthHearts/Heart3,
]

var full_heart_texture: Texture2D = preload("res://assets/visuals/heart.png")
var dead_heart_texture: Texture2D = preload("res://assets/visuals/dead_heart.png")
var pickup_sound: AudioStream = preload("res://assets/audio/pickup.wav")
var tutorial_step_sound: AudioStream = preload("res://assets/audio/tutorial_step.wav")
var keycard_collected: bool = false
var keycard_pickup_sound: AudioStreamPlayer
var tutorial_step_sound_player: AudioStreamPlayer
var skip_level_button: Button
var sound_toggle_button: Button
var level_started: bool = false
var fade_rect: ColorRect
var is_transitioning_scene: bool = false
var tutorial_bubble: TextureRect
var tutorial_label: Label
var tutorial_active: bool = false
var tutorial_step_index: int = 0
var tutorial_moved_left: bool = false
var tutorial_moved_right: bool = false
var boss_health_bar_fill_style := StyleBoxFlat.new()
var completion_items_revealed: bool = false
var boss_enemy: Node
var boss_minions: Array[Node] = []
var boss_minion_spawn_data: Array[Dictionary] = []
var boss_minion_spawn_ratios: Array[float] = []
var completed_boss_minion_waves: int = 0
var boss_minions_wave_active: bool = false


func _ready() -> void:
	keycard_collected = keycard == null
	keycard_pickup_sound = AudioStreamPlayer.new()
	keycard_pickup_sound.stream = pickup_sound
	add_child(keycard_pickup_sound)
	tutorial_step_sound_player = AudioStreamPlayer.new()
	tutorial_step_sound_player.stream = tutorial_step_sound
	add_child(tutorial_step_sound_player)
	interface.process_mode = Node.PROCESS_MODE_ALWAYS
	setup_fade_rect()
	setup_sound_toggle_button()
	pause_button.pressed.connect(_on_pause_button_pressed)
	resume_button.pressed.connect(_on_resume_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	player.health_changed.connect(_on_player_health_changed)
	player.player_died.connect(_on_player_died)
	death_restart_button.pressed.connect(_on_restart_button_pressed)
	if keycard != null:
		keycard.body_entered.connect(_on_keycard_body_entered)

	if reveal_completion_items_after_enemies_defeated:
		completion_items_revealed = false
		hide_keycard()
		hide_exit()
	else:
		completion_items_revealed = true

	setup_boss_health_bar()

	if enemies != null:
		for enemy in enemies.get_children():
			if enemy.has_signal("defeated"):
				enemy.defeated.connect(_on_enemy_defeated)
			if enemy.has_signal("health_changed"):
				boss_enemy = enemy
				enemy.health_changed.connect(_on_boss_health_changed)
				if boss_health_bar != null:
					boss_health_bar.visible = true
					_on_boss_health_changed(int(enemy.get("health")), int(enemy.get("maximum_health")))
		setup_boss_minions_phase()

	setup_tutorial()
	update_health_hearts(player.health)
	update_level_label()
	#print("NEW LEVEL: ", level_label.text)
	check_enemies()
	fade_in()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("close_menu") and pause_overlay.visible:
		set_paused(false)
		get_viewport().set_input_as_handled()
		return

	for action in START_LEVEL_ACTIONS:
		if event.is_action_pressed(action):
			level_started = true
			update_tutorial_input(action)
			return


func is_level_started() -> bool:
	return level_started


func setup_tutorial() -> void:
	tutorial_bubble = get_tutorial_bubble()
	tutorial_label = get_tutorial_label()
	tutorial_active = tutorial_bubble != null and tutorial_label != null
	if not tutorial_active:
		return

	tutorial_step_index = 0
	tutorial_moved_left = false
	tutorial_moved_right = false
	hide_keycard()
	show_tutorial_step()


func update_tutorial_input(action: StringName) -> void:
	if not tutorial_active:
		return

	match tutorial_step_index:
		0:
			if action == &"move_left":
				tutorial_moved_left = true
			elif action == &"move_right":
				tutorial_moved_right = true

			if tutorial_moved_left and tutorial_moved_right:
				advance_tutorial_step()
		1:
			if action == &"sprint" and Input.get_axis("move_left", "move_right") != 0.0:
				advance_tutorial_step()
			elif (action == &"move_left" or action == &"move_right") and Input.is_action_pressed("sprint"):
				advance_tutorial_step()
		2:
			if action == &"jump":
				advance_tutorial_step()
		3:
			if action == &"attack":
				advance_tutorial_step()
		4:
			if action == &"block":
				advance_tutorial_step()


func advance_tutorial_step() -> void:
	tutorial_step_sound_player.play()
	tutorial_step_index += 1
	show_tutorial_step()


func show_tutorial_step() -> void:
	if not tutorial_active:
		return

	if tutorial_step_index >= TUTORIAL_TEXTS.size():
		hide_tutorial()
		return

	tutorial_bubble.visible = true
	tutorial_label.text = TUTORIAL_TEXTS[tutorial_step_index]

	if tutorial_step_index == TUTORIAL_TEXTS.size() - 1:
		show_keycard()


func hide_tutorial() -> void:
	tutorial_active = false
	if tutorial_bubble != null:
		tutorial_bubble.visible = false


func get_tutorial_bubble() -> TextureRect:
	return get_node_or_null("Interface/TutorialBubble") as TextureRect


func get_tutorial_label() -> Label:
	return get_node_or_null("Interface/TutorialBubble/TutorialLabel") as Label


func hide_keycard() -> void:
	if keycard == null:
		return

	keycard.visible = false
	keycard.monitoring = false
	set_keycard_collision_disabled(true)


func show_keycard() -> void:
	if keycard == null:
		return

	keycard.visible = true
	keycard.monitoring = true
	set_keycard_collision_disabled(false)


func set_keycard_collision_disabled(is_disabled: bool) -> void:
	var keycard_collision := keycard.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if keycard_collision != null:
		keycard_collision.disabled = is_disabled


func hide_exit() -> void:
	if exit == null:
		return

	exit.visible = false
	exit.monitoring = false
	set_exit_collision_disabled(true)


func show_exit() -> void:
	if exit == null:
		return

	exit.visible = true
	exit.monitoring = true
	set_exit_collision_disabled(false)


func set_exit_collision_disabled(is_disabled: bool) -> void:
	var exit_collision := exit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if exit_collision != null:
		exit_collision.disabled = is_disabled


func setup_boss_health_bar() -> void:
	if boss_health_bar == null:
		return

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(0, 0, 0, 0.55)

	boss_health_bar_fill_style.bg_color = Color.RED
	boss_health_bar.add_theme_stylebox_override("background", background_style)
	boss_health_bar.add_theme_stylebox_override("fill", boss_health_bar_fill_style)
	boss_health_bar.visible = false
	if boss_health_border != null:
		boss_health_border.visible = false
	boss_health_bar.value = boss_health_bar.max_value


func _on_boss_health_changed(current_health: int, maximum_health: int) -> void:
	if boss_health_bar == null:
		return

	var health_ratio := 0.0 if maximum_health <= 0 else float(current_health) / float(maximum_health)
	boss_health_bar.value = health_ratio * boss_health_bar.max_value
	boss_health_bar_fill_style.bg_color = Color.RED
	if boss_health_border != null:
		boss_health_border.visible = boss_health_bar.visible
	maybe_start_boss_minions_phase(current_health, maximum_health)


func get_health_bar_color(health_ratio: float) -> Color:
	var red := Color.RED
	var yellow := Color.YELLOW
	var green := Color.GREEN

	if health_ratio <= 0.1:
		return red

	if health_ratio <= 0.5:
		return red.lerp(yellow, inverse_lerp(0.1, 0.5, health_ratio))

	return yellow.lerp(green, inverse_lerp(0.5, 1.0, health_ratio))


func setup_fade_rect() -> void:
	fade_rect = ColorRect.new()
	fade_rect.name = "FadeRect"
	fade_rect.color = Color.BLACK
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.z_index = 100
	interface.add_child(fade_rect)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.offset_left = 0.0
	fade_rect.offset_top = 0.0
	fade_rect.offset_right = 0.0
	fade_rect.offset_bottom = 0.0


func fade_in() -> void:
	set_fade_alpha(1.0)
	fade_rect.visible = true

	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 0.0, FADE_SECONDS)
	await tween.finished
	fade_rect.visible = false


func change_scene_with_fade(scene_path: String) -> void:
	if is_transitioning_scene:
		return

	is_transitioning_scene = true
	fade_rect.visible = true
	set_fade_alpha(0.0)

	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, FADE_SECONDS)
	await tween.finished
	get_tree().change_scene_to_file(scene_path)


func set_fade_alpha(alpha: float) -> void:
	var fade_color := fade_rect.color
	fade_color.a = alpha
	fade_rect.color = fade_color


func _on_enemy_defeated() -> void:
	# The enemy uses queue_free(), so wait until it has been removed.
	await get_tree().process_frame
	if boss_minions_wave_active and are_boss_minions_defeated():
		boss_minions_wave_active = false
		completed_boss_minion_waves += 1
		set_boss_shooting_disabled(false)
		set_boss_damage_disabled(false)
	if are_enemies_defeated():
		hide_boss_health_ui()
	check_enemies()


func hide_boss_health_ui() -> void:
	if boss_health_bar != null:
		boss_health_bar.visible = false
	if boss_health_border != null:
		boss_health_border.visible = false


func check_enemies() -> void:
	if not are_enemies_defeated():
		return

	if reveal_completion_items_after_enemies_defeated and not completion_items_revealed:
		completion_items_revealed = true
		show_keycard()
		show_exit()

	if not keycard_collected:
		return

	if exit != null:
		exit.unlock()
	elif not completion_scene_path.is_empty():
		change_scene_with_fade(completion_scene_path)


func are_enemies_defeated() -> bool:
	return enemies == null or enemies.get_child_count() == 0


func setup_boss_minions_phase() -> void:
	boss_minion_spawn_ratios = get_boss_minion_spawn_ratios()
	if boss_minion_spawn_ratios.is_empty() or boss_enemy == null or enemies == null:
		return

	boss_minions.clear()
	boss_minion_spawn_data.clear()
	for enemy in enemies.get_children():
		if enemy == boss_enemy:
			continue
		boss_minions.append(enemy)
		boss_minion_spawn_data.append(get_boss_minion_spawn_data(enemy))
		set_enemy_active(enemy, false)


func maybe_start_boss_minions_phase(current_health: int, maximum_health: int) -> void:
	if boss_minion_spawn_ratios.is_empty() or boss_minions_wave_active or maximum_health <= 0:
		return
	if completed_boss_minion_waves >= boss_minion_spawn_ratios.size():
		return

	var health_ratio := float(current_health) / float(maximum_health)
	if health_ratio > boss_minion_spawn_ratios[completed_boss_minion_waves]:
		return

	boss_minions_wave_active = true
	set_boss_shooting_disabled(true)
	set_boss_damage_disabled(true)
	keep_boss_alive_during_add_wave()
	spawn_boss_minion_wave()


func are_boss_minions_defeated() -> bool:
	for boss_minion in boss_minions:
		if is_instance_valid(boss_minion) and boss_minion.is_inside_tree():
			return false
	return true


func get_boss_minion_spawn_ratios() -> Array[float]:
	var spawn_ratios: Array[float] = boss_minions_spawn_health_threshold.duplicate()
	if spawn_ratios.is_empty() and boss_minions_spawn_at_health_ratio > 0.0:
		spawn_ratios.append(boss_minions_spawn_at_health_ratio)

	spawn_ratios.sort()
	spawn_ratios.reverse()
	return spawn_ratios


func get_boss_minion_spawn_data(enemy: Node) -> Dictionary:
	return {
		"scene_path": enemy.scene_file_path,
		"name": enemy.name,
		"position": enemy.position,
		"rotation": enemy.rotation,
		"scale": enemy.scale,
	}


func spawn_boss_minion_wave() -> void:
	var spawned_boss_minions: Array[Node] = []
	for index in boss_minion_spawn_data.size():
		var boss_minion := get_boss_minion_for_wave(index)
		if boss_minion == null:
			continue

		spawned_boss_minions.append(boss_minion)
		connect_boss_minion_signals(boss_minion)
		set_enemy_active(boss_minion, true)
		delay_boss_minion_shooting(boss_minion)

	boss_minions = spawned_boss_minions


func get_boss_minion_for_wave(index: int) -> Node:
	var existing_boss_minion := boss_minions[index] if index < boss_minions.size() else null
	if is_instance_valid(existing_boss_minion) and existing_boss_minion.is_inside_tree():
		return existing_boss_minion

	return create_boss_minion_from_spawn_data(boss_minion_spawn_data[index])


func create_boss_minion_from_spawn_data(spawn_data: Dictionary) -> Node:
	var scene_path := String(spawn_data["scene_path"])
	if scene_path.is_empty():
		return null

	var boss_minion_scene := load(scene_path) as PackedScene
	if boss_minion_scene == null:
		return null

	var boss_minion := boss_minion_scene.instantiate()
	boss_minion.name = String(spawn_data["name"])
	boss_minion.position = spawn_data["position"] as Vector2
	boss_minion.rotation = float(spawn_data["rotation"])
	boss_minion.scale = spawn_data["scale"] as Vector2
	enemies.add_child(boss_minion)
	return boss_minion


func connect_boss_minion_signals(boss_minion: Node) -> void:
	if boss_minion.has_signal("defeated") and not boss_minion.defeated.is_connected(_on_enemy_defeated):
		boss_minion.defeated.connect(_on_enemy_defeated)


func delay_boss_minion_shooting(boss_minion: Node) -> void:
	boss_minion.set("shoot_cooldown_remaining", BOSS_MINION_INITIAL_SHOOT_DELAY_SECONDS)
	boss_minion.set("burst_shots_remaining", 0)
	boss_minion.set("burst_shot_interval_remaining", 0.0)


func set_boss_shooting_disabled(is_disabled: bool) -> void:
	if boss_enemy != null and is_instance_valid(boss_enemy) and boss_enemy.has_method("set_shooting_disabled"):
		boss_enemy.set_shooting_disabled(is_disabled)


func set_boss_damage_disabled(is_disabled: bool) -> void:
	if boss_enemy != null and is_instance_valid(boss_enemy) and boss_enemy.has_method("set_damage_disabled"):
		boss_enemy.set_damage_disabled(is_disabled)


func keep_boss_alive_during_add_wave() -> void:
	if boss_enemy != null and is_instance_valid(boss_enemy) and boss_enemy.has_method("keep_alive_during_add_wave"):
		boss_enemy.keep_alive_during_add_wave()


func set_enemy_active(enemy: Node, is_active: bool) -> void:
	if not is_instance_valid(enemy):
		return

	enemy.visible = is_active
	enemy.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	set_collision_objects_active(enemy, is_active)


func set_collision_objects_active(node: Node, is_active: bool) -> void:
	var collision_object := node as CollisionObject2D
	if collision_object != null:
		set_collision_object_active(collision_object, is_active)

	for child in node.get_children():
		set_collision_objects_active(child, is_active)


func set_collision_object_active(collision_object: CollisionObject2D, is_active: bool) -> void:
	if is_active:
		if collision_object.has_meta("disabled_boss_minion_collision_layer"):
			collision_object.collision_layer = int(collision_object.get_meta("disabled_boss_minion_collision_layer"))
		if collision_object.has_meta("disabled_boss_minion_collision_mask"):
			collision_object.collision_mask = int(collision_object.get_meta("disabled_boss_minion_collision_mask"))
		return

	if not collision_object.has_meta("disabled_boss_minion_collision_layer"):
		collision_object.set_meta("disabled_boss_minion_collision_layer", collision_object.collision_layer)
		collision_object.set_meta("disabled_boss_minion_collision_mask", collision_object.collision_mask)

	collision_object.collision_layer = 0
	collision_object.collision_mask = 0


func _on_keycard_body_entered(body: Node2D) -> void:
	if body != player:
		return

	keycard_collected = true
	keycard_pickup_sound.play()
	hide_tutorial()
	keycard.visible = false
	keycard.set_deferred("monitoring", false)
	var keycard_collision := keycard.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if keycard_collision != null:
		keycard_collision.set_deferred("disabled", true)
	check_enemies()


func _on_player_health_changed(new_health: int) -> void:
	update_health_hearts(new_health)


func _on_player_died() -> void:
	pause_overlay.visible = false
	death_overlay.visible = true
	pause_button.text = "Pause"
	pause_button.disabled = true
	get_tree().paused = true


func update_health_hearts(current_health: int) -> void:
	for index in health_hearts.size():
		health_hearts[index].texture = full_heart_texture if index < current_health else dead_heart_texture


func update_level_label() -> void:
	var digits := ""

	for character in scene_file_path.get_file().get_basename():
		if character.is_valid_int():
			digits += character

	if digits.is_empty():
		level_label.text = name
		return

	level_label.text = "Level %d" % int(digits)


func _on_pause_button_pressed() -> void:
	UISounds.play_button_clicked()
	set_paused(true)


func _on_resume_button_pressed() -> void:
	UISounds.play_button_clicked()
	set_paused(false)


func _on_restart_button_pressed() -> void:
	UISounds.play_button_clicked()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_button_pressed() -> void:
	UISounds.play_button_clicked()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/start_game.tscn")


func setup_sound_toggle_button() -> void:
	pause_panel.offset_top = -136.0
	pause_panel.offset_bottom = 136.0

	skip_level_button = BUTTON_SCENE.instantiate() as Button
	skip_level_button.name = "SkipLevelButton"
	skip_level_button.custom_minimum_size = Vector2(0, 32)
	skip_level_button.add_theme_font_size_override("font_size", main_menu_button.get_theme_font_size("font_size"))
	skip_level_button.text = "Skip Level"
	skip_level_button.pressed.connect(_on_skip_level_button_pressed)
	pause_options.add_child(skip_level_button)
	pause_options.move_child(skip_level_button, main_menu_button.get_index())

	sound_toggle_button = BUTTON_SCENE.instantiate() as Button
	sound_toggle_button.name = "SoundToggleButton"
	sound_toggle_button.custom_minimum_size = Vector2(0, 32)
	sound_toggle_button.add_theme_font_size_override("font_size", main_menu_button.get_theme_font_size("font_size"))
	sound_toggle_button.pressed.connect(_on_sound_toggle_button_pressed)
	pause_options.add_child(sound_toggle_button)
	pause_options.move_child(sound_toggle_button, main_menu_button.get_index())
	update_sound_toggle_button_text()


func _on_skip_level_button_pressed() -> void:
	UISounds.play_button_clicked()

	var next_level_path := get_skip_level_path()
	if next_level_path.is_empty():
		return

	GameProgress.complete_level(get_tree().current_scene.scene_file_path)
	get_tree().paused = false
	change_scene_with_fade(next_level_path)


func get_skip_level_path() -> String:
	if exit != null and not exit.next_level_path.is_empty():
		return exit.next_level_path

	var current_level_number := GameProgress.get_level_number_from_path(get_tree().current_scene.scene_file_path)
	if current_level_number <= 0:
		return ""

	if current_level_number >= GameProgress.MAX_LEVEL:
		return completion_scene_path if not completion_scene_path.is_empty() else "res://scenes/finish_game.tscn"

	return "res://levels/level_%02d.tscn" % (current_level_number + 1)


func _on_sound_toggle_button_pressed() -> void:
	var master_bus_index := AudioServer.get_bus_index("Master")
	var should_mute := not AudioServer.is_bus_mute(master_bus_index)

	if should_mute:
		UISounds.play_button_clicked()
		AudioServer.set_bus_mute(master_bus_index, true)
	else:
		AudioServer.set_bus_mute(master_bus_index, false)
		UISounds.play_button_clicked()

	update_sound_toggle_button_text()


func update_sound_toggle_button_text() -> void:
	var master_bus_index := AudioServer.get_bus_index("Master")
	sound_toggle_button.text = "Sound Off" if AudioServer.is_bus_mute(master_bus_index) else "Sound On"


func set_paused(is_paused: bool) -> void:
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused
	pause_button.text = "Pause"
	pause_button.disabled = is_paused


func is_pause_menu_open() -> bool:
	return pause_overlay.visible


func close_pause_menu() -> void:
	if not pause_overlay.visible:
		return

	set_paused(false)
