extends Control

const LEVEL_PATHS := [
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
]

var locked_level_texture: Texture2D = preload("res://assets/visuals/locked_level.png")


func _ready() -> void:
	for index in range(LEVEL_PATHS.size()):
		var level_number := index + 1
		var button := get_node("Level%d" % level_number) as Button
		button.pressed.connect(_on_level_button_pressed.bind(LEVEL_PATHS[index]))
		update_level_button(button, level_number)

	$Back.pressed.connect(_on_back_pressed)


func update_level_button(button: Button, level_number: int) -> void:
	var is_unlocked := GameProgress.is_level_unlocked(level_number)
	button.disabled = not is_unlocked

	var lock_overlay := TextureRect.new()
	lock_overlay.name = "LockedOverlay"
	lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_overlay.texture = locked_level_texture
	lock_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(lock_overlay)
	lock_overlay.visible = not is_unlocked


func _on_level_button_pressed(level_path: String) -> void:
	UISounds.play_button_clicked()
	get_tree().change_scene_to_file(level_path)


func _on_back_pressed() -> void:
	UISounds.play_button_clicked()
	get_tree().change_scene_to_file("res://scenes/start_game.tscn")
