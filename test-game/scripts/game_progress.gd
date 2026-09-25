extends Node

const MAX_LEVEL := 15
const SAVE_PATH := "user://progress.save"

var highest_unlocked_level: int = 1


func _ready() -> void:
	load_progress()


func is_level_unlocked(level_number: int) -> bool:
	return level_number <= highest_unlocked_level


func complete_level(level_path: String) -> void:
	var completed_level := get_level_number_from_path(level_path)
	if completed_level <= 0:
		return

	var new_highest_unlocked_level := maxi(highest_unlocked_level, mini(completed_level + 1, MAX_LEVEL))
	if new_highest_unlocked_level == highest_unlocked_level:
		return

	highest_unlocked_level = new_highest_unlocked_level
	save_progress()


func save_progress() -> void:
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file == null:
		push_warning("Could not save game progress: %s" % FileAccess.get_open_error())
		return

	var save_data := {
		"highest_unlocked_level": highest_unlocked_level,
	}
	save_file.store_string(JSON.stringify(save_data))


func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if save_file == null:
		push_warning("Could not load game progress: %s" % FileAccess.get_open_error())
		return

	var parsed_data = JSON.parse_string(save_file.get_as_text())
	if typeof(parsed_data) != TYPE_DICTIONARY:
		return

	var saved_highest_unlocked_level := int(parsed_data.get("highest_unlocked_level", 1))
	highest_unlocked_level = clampi(saved_highest_unlocked_level, 1, MAX_LEVEL)


func get_level_number_from_path(level_path: String) -> int:
	var digits := ""

	for character in level_path.get_file().get_basename():
		if character.is_valid_int():
			digits += character

	return 0 if digits.is_empty() else int(digits)
