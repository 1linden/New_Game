extends CharacterBody2D

signal defeated
signal health_changed(current_health: int, maximum_health: int)

const GUN_OVERHEAT_WARNING_SOUND_MARKS: Array[float] = [3.0, 3.33, 3.66, 4.0, 4.25, 4.5, 4.75]

@export var maximum_health: int = 1500
@export var bullet_scene: PackedScene
@export var sniper_bullet_scene: PackedScene = preload("res://scenes/bullet_heavy.tscn")
@export var pistol_shoot_range: float = 1000
@export var pistol_shoot_cooldown_seconds: float = 1
@export var smg_shoot_range: float = 1000
@export var smg_shoot_cooldown_seconds: float = 1
@export var smg_shots_per_burst: int = 3
@export var smg_burst_shot_interval_seconds: float = 0.1
@export var sniper_shoot_range: float = 1000
@export var sniper_shoot_cooldown_seconds: float = 2.5
@export var initial_shoot_delay_seconds: float = 1
@export var gun_rotation_offset: float = PI
@export var starts_facing_left: bool = true
@export var gun_overheat_warning_seconds: float = 2.5
@export var gun_overheat_seconds: float = 7.5
@export var gun_overheat_cooldown_seconds: float = 5.0
@export var gun_overheat_recovery_fade_seconds: float = 2.5

var health: int
var pistol_shoot_cooldown_remaining: float = 0.0
var smg_shoot_cooldown_remaining: float = 0.0
var smg_burst_shots_remaining: int = 0
var smg_burst_shot_interval_remaining: float = 0.0
var sniper_shoot_cooldown_remaining: float = 0.0
var facing_right: bool = false
var damage_flash_tween: Tween
var is_dead: bool = false
var gun_heat_seconds: float = 0.0
var gun_overheat_cooldown_remaining: float = 0.0
var gun_heat_increasing: bool = false
var shooting_disabled: bool = false
var damage_disabled: bool = false
var has_acquired_player_line_of_sight: bool = false
var gun_overheat_bar_fill_style := StyleBoxFlat.new()
var gun_overheat_warning_sound_marks_played: Array[bool] = []

@onready var robot_left: Sprite2D = find_optional_node("RobotLeft", "Sprite2DLeft") as Sprite2D
@onready var robot_right: Sprite2D = find_optional_node("RobotRight", "Sprite2DRight") as Sprite2D
@onready var collision_left: CollisionPolygon2D = get_node_or_null("CollisionLeft") as CollisionPolygon2D
@onready var collision_right: CollisionPolygon2D = get_node_or_null("CollisionRight") as CollisionPolygon2D
@onready var gun_pivot_left: Node2D = $GunPivotLeft
@onready var gun_pivot_right: Node2D = $GunPivotRight
@onready var bullet_spawn_pistol_left: Marker2D = $GunPivotLeft/BulletSpawnLeftPistol
@onready var bullet_spawn_pistol_right: Marker2D = $GunPivotRight/BulletSpawnRightPistol
@onready var bullet_spawn_smg_left: Marker2D = $GunPivotLeft/BulletSpawnLeftSmg
@onready var bullet_spawn_smg_right: Marker2D = $GunPivotRight/BulletSpawnRightSmg
@onready var bullet_spawn_sniper_left: Marker2D = $GunPivotLeft/BulletSpawnLeftSniper
@onready var bullet_spawn_sniper_right: Marker2D = $GunPivotRight/BulletSpawnRightSniper
@onready var gun_left: Sprite2D = $GunPivotLeft/GunLeft
@onready var gun_right: Sprite2D = $GunPivotRight/GunRight
@onready var gun_hitbox_left: Area2D = $GunPivotLeft/GunHitboxLeft
@onready var gun_hitbox_right: Area2D = $GunPivotRight/GunHitboxRight
@onready var gun_overheat_steam_particles_left: GPUParticles2D = $GunPivotLeft/SteamParticlesLeft
@onready var gun_overheat_steam_particles_right: GPUParticles2D = $GunPivotRight/SteamParticlesRight
@onready var light_gunshot_sound: AudioStreamPlayer = $LightGunshotSound
@onready var heavy_gunshot_sound: AudioStreamPlayer = $HeavyGunshotSound
@onready var enemy_take_damage_sound: AudioStreamPlayer = $EnemyTakeDamageSound
@onready var explosion_sound: AudioStreamPlayer = $ExplosionSound
@onready var gun_overheat_steam_sound: AudioStreamPlayer = $GunOverheatSteamSound
@onready var gun_overheat_warning_sound: AudioStreamPlayer = $GunOverheatWarningSound
@onready var gun_overheat_bar: ProgressBar = get_node_or_null("GunOverheatBar") as ProgressBar


func _ready() -> void:
	health = maximum_health
	reset_gun_overheat_warning_sound_marks()
	setup_gun_hitboxes()
	setup_gun_overheat_bar()
	setup_gun_overheat_steam_particles()
	reset_to_starting_facing()
	health_changed.emit(health, maximum_health)


func setup_gun_hitboxes() -> void:
	for gun_hitbox in [gun_hitbox_left, gun_hitbox_right]:
		gun_hitbox.collision_layer = 4
		gun_hitbox.collision_mask = 0
		gun_hitbox.monitorable = true


func setup_gun_overheat_steam_particles() -> void:
	for particles in [gun_overheat_steam_particles_left, gun_overheat_steam_particles_right]:
		particles.one_shot = true
		particles.emitting = false


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
	face_player()
	update_shooting(delta)


func face_player() -> void:
	if damage_disabled:
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return

	if is_player_in_any_shoot_range(player):
		if not has_acquired_player_line_of_sight:
			if has_line_of_sight_to(player, global_position):
				has_acquired_player_line_of_sight = true
				apply_initial_shoot_delay()
			else:
				reset_to_starting_facing()
				reset_active_gun_rotations()
				return

		facing_right = player.global_position.x > global_position.x
		update_facing(facing_right)
		aim_all_guns_at(player.global_position)
	else:
		reset_to_starting_facing()
		reset_active_gun_rotations()


func update_facing(use_right_side: bool) -> void:
	set_node_visible(robot_left, not use_right_side)
	set_node_visible(robot_right, use_right_side)
	set_node_visible(gun_pivot_left, not use_right_side)
	set_node_visible(gun_pivot_right, use_right_side)

	if collision_left != null:
		collision_left.disabled = use_right_side
	if collision_right != null:
		collision_right.disabled = not use_right_side


func reset_to_starting_facing() -> void:
	facing_right = not starts_facing_left
	update_facing(facing_right)


func aim_all_guns_at(target_position: Vector2) -> void:
	aim_gun_at(get_active_gun_pivot(), target_position)


func aim_gun_at(gun_pivot: Node2D, target_position: Vector2) -> void:
	if gun_pivot == null:
		return

	var aim_direction := gun_pivot.global_position.direction_to(target_position)
	if aim_direction == Vector2.ZERO:
		return

	gun_pivot.global_rotation = aim_direction.angle() if facing_right else aim_direction.angle() + gun_rotation_offset


func update_shooting(delta: float) -> void:
	if not is_level_started():
		return

	if shooting_disabled:
		cool_gun(delta)
		return

	pistol_shoot_cooldown_remaining = maxf(pistol_shoot_cooldown_remaining - delta, 0.0)
	smg_shoot_cooldown_remaining = maxf(smg_shoot_cooldown_remaining - delta, 0.0)
	smg_burst_shot_interval_remaining = maxf(smg_burst_shot_interval_remaining - delta, 0.0)
	sniper_shoot_cooldown_remaining = maxf(sniper_shoot_cooldown_remaining - delta, 0.0)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		cool_gun(delta)
		return

	update_gun_overheat(delta, player)
	if is_gun_overheated():
		return

	update_pistol_shooting(player)
	update_smg_shooting(player)
	update_sniper_shooting(player)


func update_gun_overheat(delta: float, player: Node2D) -> void:
	if gun_overheat_cooldown_remaining > 0.0:
		gun_heat_increasing = false
		gun_overheat_cooldown_remaining = maxf(gun_overheat_cooldown_remaining - delta, 0.0)
		if gun_overheat_cooldown_remaining == 0.0:
			finish_gun_overheat_cooldown()
		update_gun_overheat_color()
		return

	if can_gun_build_heat(player):
		gun_heat_increasing = true
		gun_heat_seconds = minf(gun_heat_seconds + delta, gun_overheat_seconds)
		if gun_heat_seconds >= gun_overheat_seconds:
			gun_overheat_cooldown_remaining = gun_overheat_cooldown_seconds
			gun_overheat_steam_sound.play()
			emit_gun_overheat_steam()
	else:
		cool_gun(delta)

	update_gun_overheat_color()


func can_gun_build_heat(player: Node2D) -> bool:
	var gun_pivot := get_active_gun_pivot()
	if gun_pivot == null:
		return false
	if gun_pivot.global_position.distance_to(player.global_position) > maxf(sniper_shoot_range, maxf(pistol_shoot_range, smg_shoot_range)):
		return false

	return has_line_of_sight_to(player, gun_pivot.global_position)


func cool_gun(delta: float) -> void:
	gun_heat_increasing = false
	if gun_overheat_cooldown_remaining > 0.0:
		gun_overheat_cooldown_remaining = maxf(gun_overheat_cooldown_remaining - delta, 0.0)
		if gun_overheat_cooldown_remaining == 0.0:
			finish_gun_overheat_cooldown()
		update_gun_overheat_color()
		return

	gun_heat_seconds = maxf(gun_heat_seconds - delta, 0.0)
	update_gun_overheat_color()


func finish_gun_overheat_cooldown() -> void:
	gun_heat_seconds = 0.0
	apply_initial_shoot_delay()


func apply_initial_shoot_delay() -> void:
	pistol_shoot_cooldown_remaining = initial_shoot_delay_seconds
	smg_shoot_cooldown_remaining = initial_shoot_delay_seconds
	smg_burst_shots_remaining = 0
	smg_burst_shot_interval_remaining = 0.0
	sniper_shoot_cooldown_remaining = initial_shoot_delay_seconds


func emit_gun_overheat_steam() -> void:
	var template_particles := gun_overheat_steam_particles_right if facing_right else gun_overheat_steam_particles_left
	var steam_transform := template_particles.global_transform
	var steam_particles := template_particles.duplicate() as GPUParticles2D
	get_tree().current_scene.add_child(steam_particles)
	steam_particles.global_transform = steam_transform
	steam_particles.one_shot = true
	steam_particles.emitting = false
	steam_particles.finished.connect(steam_particles.queue_free)
	steam_particles.restart()
	steam_particles.emitting = true


func is_gun_overheated() -> bool:
	return gun_overheat_cooldown_remaining > 0.0


func set_shooting_disabled(is_disabled: bool) -> void:
	var was_shooting_disabled := shooting_disabled
	shooting_disabled = is_disabled
	if shooting_disabled:
		smg_burst_shots_remaining = 0
		smg_burst_shot_interval_remaining = 0.0
	elif was_shooting_disabled:
		apply_initial_shoot_delay()


func set_damage_disabled(is_disabled: bool) -> void:
	damage_disabled = is_disabled
	var boss_modulate := modulate
	boss_modulate.a = 0.3 if damage_disabled else 1.0
	modulate = boss_modulate


func keep_alive_during_add_wave() -> void:
	if health > 0:
		return

	health = 1
	health_changed.emit(health, maximum_health)


func update_gun_overheat_color() -> void:
	var heat_ratio := 0.0
	if gun_overheat_cooldown_remaining > 0.0:
		heat_ratio = 1.0 if gun_overheat_cooldown_remaining >= gun_overheat_recovery_fade_seconds else gun_overheat_cooldown_remaining / gun_overheat_recovery_fade_seconds
	elif gun_heat_seconds > gun_overheat_warning_seconds:
		heat_ratio = inverse_lerp(gun_overheat_warning_seconds, gun_overheat_seconds, gun_heat_seconds)

	var gun_color := Color.WHITE.lerp(Color.RED, clampf(heat_ratio, 0.0, 1.0))
	gun_left.modulate = gun_color
	gun_right.modulate = gun_color
	update_gun_overheat_bar()


func setup_gun_overheat_bar() -> void:
	if gun_overheat_bar == null:
		return

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(0, 0, 0, 0.65)
	gun_overheat_bar_fill_style.bg_color = Color.GRAY
	gun_overheat_bar.add_theme_stylebox_override("background", background_style)
	gun_overheat_bar.add_theme_stylebox_override("fill", gun_overheat_bar_fill_style)
	gun_overheat_bar.min_value = 0.0
	gun_overheat_bar.max_value = 100.0
	gun_overheat_bar.show_percentage = false
	update_gun_overheat_bar()


func update_gun_overheat_bar() -> void:
	if gun_overheat_bar == null:
		return
	if is_dead:
		gun_overheat_bar.visible = false
		reset_gun_overheat_warning_sound_marks()
		return

	var bar_ratio := get_gun_overheat_bar_ratio()
	if bar_ratio <= 0.0:
		reset_gun_overheat_warning_sound_marks()
	else:
		play_scheduled_gun_overheat_warning_sounds()

	gun_overheat_bar.visible = bar_ratio > 0.0 and is_gun_overheat_bar_flash_visible()
	gun_overheat_bar.value = bar_ratio * gun_overheat_bar.max_value
	gun_overheat_bar_fill_style.bg_color = get_gun_overheat_bar_color(bar_ratio)


func get_gun_overheat_bar_ratio() -> float:
	if gun_overheat_cooldown_remaining > gun_overheat_recovery_fade_seconds:
		return 1.0
	if gun_overheat_cooldown_remaining > 0.0:
		return clampf(gun_overheat_cooldown_remaining / gun_overheat_recovery_fade_seconds, 0.0, 1.0)
	if gun_overheat_seconds <= gun_overheat_warning_seconds:
		return 0.0

	return clampf(inverse_lerp(gun_overheat_warning_seconds, gun_overheat_seconds, gun_heat_seconds), 0.0, 1.0)


func get_gun_overheat_bar_color(bar_ratio: float) -> Color:
	return Color.GRAY.lerp(Color.RED, bar_ratio)


func play_scheduled_gun_overheat_warning_sounds() -> void:
	if gun_overheat_cooldown_remaining > 0.0 or not gun_heat_increasing:
		return

	var warning_elapsed := gun_heat_seconds - gun_overheat_warning_seconds
	for index in range(GUN_OVERHEAT_WARNING_SOUND_MARKS.size()):
		if gun_overheat_warning_sound_marks_played[index]:
			continue
		if warning_elapsed >= GUN_OVERHEAT_WARNING_SOUND_MARKS[index]:
			gun_overheat_warning_sound_marks_played[index] = true
			play_gun_overheat_warning_sound()


func reset_gun_overheat_warning_sound_marks() -> void:
	gun_overheat_warning_sound_marks_played.clear()
	for _index in range(GUN_OVERHEAT_WARNING_SOUND_MARKS.size()):
		gun_overheat_warning_sound_marks_played.append(false)


func play_gun_overheat_warning_sound() -> void:
	if gun_overheat_warning_sound != null:
		gun_overheat_warning_sound.play()


func is_gun_overheat_bar_flash_visible() -> bool:
	if gun_overheat_cooldown_remaining > 0.0:
		return true
	if not gun_heat_increasing:
		return true

	var warning_elapsed := gun_heat_seconds - gun_overheat_warning_seconds
	if warning_elapsed < 3.0:
		return true

	var flash_seconds := 0.33
	if warning_elapsed >= 4.0:
		flash_seconds = 0.25

	return fmod(warning_elapsed - 3.0, flash_seconds) < flash_seconds * 0.5


func update_pistol_shooting(player: Node2D) -> void:
	if pistol_shoot_cooldown_remaining > 0.0 or bullet_scene == null:
		return
	if not can_weapon_shoot(player, get_active_gun_pivot(), pistol_shoot_range):
		return

	shoot_weapon(player.global_position, bullet_scene, get_active_gun_pivot(), get_active_pistol_spawn(), 1, light_gunshot_sound)
	pistol_shoot_cooldown_remaining = pistol_shoot_cooldown_seconds


func update_smg_shooting(player: Node2D) -> void:
	if bullet_scene == null:
		return
	if smg_burst_shots_remaining == 0 and smg_shoot_cooldown_remaining > 0.0:
		return
	if not can_weapon_shoot(player, get_active_gun_pivot(), smg_shoot_range):
		return

	if smg_burst_shots_remaining == 0:
		smg_burst_shots_remaining = smg_shots_per_burst
		smg_burst_shot_interval_remaining = 0.0

	if smg_burst_shot_interval_remaining > 0.0:
		return

	shoot_weapon(player.global_position, bullet_scene, get_active_gun_pivot(), get_active_smg_spawn(), 1, light_gunshot_sound)
	smg_burst_shots_remaining -= 1

	if smg_burst_shots_remaining > 0:
		smg_burst_shot_interval_remaining = smg_burst_shot_interval_seconds
	else:
		smg_shoot_cooldown_remaining = smg_shoot_cooldown_seconds


func update_sniper_shooting(player: Node2D) -> void:
	if sniper_shoot_cooldown_remaining > 0.0 or sniper_bullet_scene == null:
		return
	if not can_weapon_shoot(player, get_active_gun_pivot(), sniper_shoot_range):
		return

	shoot_weapon(player.global_position, sniper_bullet_scene, get_active_gun_pivot(), get_active_sniper_spawn(), 3, heavy_gunshot_sound)
	sniper_shoot_cooldown_remaining = sniper_shoot_cooldown_seconds


func can_weapon_shoot(player: Node2D, gun_pivot: Node2D, weapon_range: float) -> bool:
	if gun_pivot == null:
		return false
	if gun_pivot.global_position.distance_to(player.global_position) > weapon_range:
		return false

	return has_line_of_sight_to(player, gun_pivot.global_position)


func has_line_of_sight_to(target: Node2D, origin: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(origin, target.global_position, 1)
	query.exclude = [self]

	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func shoot_weapon(target_position: Vector2, weapon_bullet_scene: PackedScene, gun_pivot: Node2D, bullet_spawn: Marker2D, damage: int, sound: AudioStreamPlayer) -> void:
	if weapon_bullet_scene == null or gun_pivot == null:
		return

	var bullet := weapon_bullet_scene.instantiate() as Area2D
	get_tree().current_scene.add_child(bullet)
	bullet.scale = Vector2(2.0, 2.0)

	var shoot_direction := gun_pivot.global_position.direction_to(target_position)
	var spawn_position := bullet_spawn.global_position if bullet_spawn != null else gun_pivot.global_position
	bullet.collision_layer = 16
	bullet.collision_mask = 3
	bullet.damage = damage
	bullet.launch(spawn_position, shoot_direction.angle())
	sound.play()


func get_active_gun_pivot() -> Node2D:
	return gun_pivot_right if facing_right else gun_pivot_left


func get_active_pistol_spawn() -> Marker2D:
	return bullet_spawn_pistol_right if facing_right else bullet_spawn_pistol_left


func get_active_smg_spawn() -> Marker2D:
	return bullet_spawn_smg_right if facing_right else bullet_spawn_smg_left


func get_active_sniper_spawn() -> Marker2D:
	return bullet_spawn_sniper_right if facing_right else bullet_spawn_sniper_left


func reset_active_gun_rotations() -> void:
	var gun_pivot := get_active_gun_pivot()
	if gun_pivot != null:
		gun_pivot.rotation = 0.0


func set_node_visible(node: CanvasItem, should_be_visible: bool) -> void:
	if node != null:
		node.visible = should_be_visible


func find_optional_node(primary_path: NodePath, fallback_path: NodePath) -> Node:
	var node := get_node_or_null(primary_path)
	if node != null:
		return node

	return get_node_or_null(fallback_path)


func is_player_in_any_shoot_range(player: Node2D) -> bool:
	return global_position.distance_to(player.global_position) <= maxf(sniper_shoot_range, maxf(pistol_shoot_range, smg_shoot_range))


func is_level_started() -> bool:
	var current_level := get_tree().current_scene
	if current_level == null or current_level == self:
		return true

	if not current_level.has_method("is_level_started"):
		return true

	return current_level.is_level_started()


func take_damage(amount: int) -> void:
	if damage_disabled:
		return

	var previous_health := health
	health = max(health - amount, 0)
	health_changed.emit(health, maximum_health)

	if health < previous_health:
		flash_damage()
		if health == 0:
			play_detached_take_damage_sound()
		else:
			enemy_take_damage_sound.play()

	if health == 0:
		die()


func play_detached_take_damage_sound() -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = enemy_take_damage_sound.stream
	sound.bus = enemy_take_damage_sound.bus
	get_tree().current_scene.add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func flash_damage() -> void:
	if damage_flash_tween != null:
		damage_flash_tween.kill()

	set_robot_modulate(Color(1, 0.2, 0.2))
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_method(set_robot_modulate, Color(1, 0.2, 0.2), Color.WHITE, 0.2)


func set_robot_modulate(color: Color) -> void:
	if robot_left != null:
		robot_left.modulate = color
	if robot_right != null:
		robot_right.modulate = color


func freeze_for_death_explosion() -> void:
	velocity = Vector2.ZERO
	shooting_disabled = true
	smg_burst_shots_remaining = 0
	smg_burst_shot_interval_remaining = 0.0
	gun_heat_seconds = 0.0
	gun_overheat_cooldown_remaining = 0.0
	gun_heat_increasing = false
	if gun_overheat_steam_sound != null:
		gun_overheat_steam_sound.stop()
	if gun_left != null:
		gun_left.modulate = Color.WHITE
	if gun_right != null:
		gun_right.modulate = Color.WHITE
	if gun_overheat_bar != null:
		gun_overheat_bar.visible = false


func boss_explosion_sequence() -> void:
	# Several smaller explosions
	for i in range(10):
		var offset := Vector2(
			randf_range(-120, 120),
			randf_range(-100, 100)
		)

		Spark.burst(global_position + offset, "explode")
		play_detached_explosion_sound()

		await get_tree().create_timer(0.3).timeout

	await get_tree().create_timer(0.7).timeout

	# Large final explosion
	Spark.burst(global_position, {
		"amount": 90,
		"color": Color(1.0, 0.85, 0.25),
		"color2": Color(1.0, 0.05, 0.0, 0),
		"speed": 650.0,
		"lifetime": 1.0,
		"size": 10.0,
		"gravity": 180.0,
		"spread": TAU,
		"damping": 2.0,
	})
	play_detached_explosion_sound()


func play_detached_explosion_sound() -> void:
	if explosion_sound == null or explosion_sound.stream == null:
		return

	var sound := AudioStreamPlayer.new()
	sound.stream = explosion_sound.stream
	sound.volume_db = explosion_sound.volume_db
	sound.pitch_scale = explosion_sound.pitch_scale
	sound.bus = explosion_sound.bus
	get_tree().current_scene.add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func force_kill_for_debug() -> void:
	if is_dead:
		return

	health = 0
	health_changed.emit(health, maximum_health)
	die()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	freeze_for_death_explosion()
	await boss_explosion_sequence()
	defeated.emit()
	call_deferred("queue_free")
