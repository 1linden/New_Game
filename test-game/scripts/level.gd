extends Node2D

const START_LEVEL_ACTIONS := [&"move_left", &"move_right", &"jump", &"sprint", &"block", &"attack"]
const FADE_SECONDS := 0.4
const TUTORIAL_TEXTS: Array[String] = [
	"Press A to Move Left and D to Move Right",
	"Hold Shift while Moving to Sprint",
	"Press W or SPACE\nto Jump",
	"Press Left Mouse Button to Attack",
	"Hold Right Mouse Button to Block",
	"Collect the Keycard\nto Advance",
]

@onready var player = $Player
@onready var enemies: Node2D = get_node_or_null("Enemies") as Node2D
@onready var exit: Area2D = $Exit
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

	if enemies != null:
		for enemy in enemies.get_children():
			if enemy.has_signal("defeated"):
				enemy.defeated.connect(_on_enemy_defeated)

	setup_tutorial()
	update_health_hearts(player.health)
	update_level_label()
	print("NEW LEVEL: ", level_label.text)
	check_enemies()
	fade_in()


func _input(event: InputEvent) -> void:
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
	check_enemies()


func check_enemies() -> void:
	if are_enemies_defeated() and keycard_collected:
		exit.unlock()


func are_enemies_defeated() -> bool:
	return enemies == null or enemies.get_child_count() == 0


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
	pause_panel.offset_top = -100.0
	pause_panel.offset_bottom = 100.0

	sound_toggle_button = Button.new()
	sound_toggle_button.name = "SoundToggleButton"
	sound_toggle_button.custom_minimum_size = Vector2(0, 32)
	sound_toggle_button.add_theme_stylebox_override("normal", main_menu_button.get_theme_stylebox("normal"))
	sound_toggle_button.add_theme_stylebox_override("pressed", main_menu_button.get_theme_stylebox("pressed"))
	sound_toggle_button.add_theme_stylebox_override("hover", main_menu_button.get_theme_stylebox("hover"))
	sound_toggle_button.add_theme_stylebox_override("focus", main_menu_button.get_theme_stylebox("focus"))
	sound_toggle_button.pressed.connect(_on_sound_toggle_button_pressed)
	pause_options.add_child(sound_toggle_button)
	update_sound_toggle_button_text()


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
