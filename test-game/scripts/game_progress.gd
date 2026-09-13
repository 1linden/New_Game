extends Node

const MAX_LEVEL := 10

var highest_unlocked_level: int = 1


func is_level_unlocked(level_number: int) -> bool:
	return level_number <= highest_unlocked_level


func complete_level(level_path: String) -> void:
	var completed_level := get_level_number_from_path(level_path)
	if completed_level <= 0:
		return

	highest_unlocked_level = maxi(highest_unlocked_level, mini(completed_level + 1, MAX_LEVEL))


func get_level_number_from_path(level_path: String) -> int:
	var digits := ""

	for character in level_path.get_file().get_basename():
		if character.is_valid_int():
			digits += character

	return 0 if digits.is_empty() else int(digits)
