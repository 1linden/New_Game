extends Area2D

@export_file("*.tscn") var next_level_path: String

var is_locked: bool = true
var is_changing_scene: bool = false

@onready var sprite_locked: Sprite2D = $SpriteLocked
@onready var sprite_unlocked: Sprite2D = $SpriteUnlocked


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	update_sprites()


func unlock() -> void:
	if not is_locked:
		return

	is_locked = false
	update_sprites()


func update_sprites() -> void:
	sprite_locked.visible = is_locked
	sprite_unlocked.visible = not is_locked


func _on_body_entered(body: Node2D) -> void:
	if is_locked or is_changing_scene:
		return

	if not body.is_in_group("player"):
		return

	is_changing_scene = true
	GameProgress.complete_level(get_tree().current_scene.scene_file_path)

	if next_level_path.is_empty():
		call_deferred("change_scene", "res://scenes/game_complete.tscn")
		return

	call_deferred("change_scene", next_level_path)


func change_scene(scene_path: String) -> void:
	var current_level := get_tree().current_scene
	if current_level != null and current_level.has_method("change_scene_with_fade"):
		current_level.change_scene_with_fade(scene_path)
		return

	get_tree().change_scene_to_file(scene_path)
