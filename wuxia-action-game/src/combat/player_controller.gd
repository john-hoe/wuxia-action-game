# src/combat/player_controller.gd
extends CharacterBody2D

@export var move_speed: float = 400.0
@export var depth_switch_speed: float = 200.0
var current_depth: int = 1
var target_depth_y: float
var depth_y_positions: Array[float] = [740.0, 540.0, 340.0]
var depth_scales: Array[float] = [0.7, 1.0, 1.3]

const POJUN_DASH_SPEED: float = 1200.0
const POJUN_DASH_DURATION: float = 0.25
const POJUN_STUN_DURATION: float = 0.5
var is_dashing: bool = false
var dash_direction: float = 1.0
var dash_timer: float = 0.0
var _dash_hit_enemies: Array = []

const HUIFENG_RADIUS: float = 200.0
const HUIFENG_PULL_STRENGTH: float = 150.0
const HUIFENG_KNOCKBACK: float = 200.0
const HUIFENG_DAMAGE: float = 30.0
var is_huifeng_animating: bool = false

const NINGSHEN_PARRY_WINDOW: float = 0.8
const NINGSHEN_PERFECT_WINDOW: float = 0.2
const NINGSHEN_BUFF_DURATION: float = 3.0
const NINGSHEN_BUFF_MULTIPLIER: float = 1.2

var is_parrying: bool = false
var parry_timer: float = 0.0
var has_damage_buff: bool = false
var _buff_timer: SceneTreeTimer = null

@onready var combo_engine: Node = $ComboEngine
@onready var skill_system: SkillSystem = $SkillSystem

func _ready() -> void:
	target_depth_y = depth_y_positions[current_depth]
	position.y = target_depth_y
	combo_engine.combo_advanced.connect(_on_combo_advanced)

func _physics_process(delta: float) -> void:
	_handle_depth_input()
	if is_dashing:
		_process_dash(delta)
	else:
		_handle_movement(delta)
	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			_end_parry(false)
	_apply_depth_transition(delta)

func _handle_depth_input() -> void:
	if Input.is_action_just_pressed("depth_forward") and current_depth < 2:
		current_depth += 1
		target_depth_y = depth_y_positions[current_depth]
	if Input.is_action_just_pressed("depth_back") and current_depth > 0:
		current_depth -= 1
		target_depth_y = depth_y_positions[current_depth]

func _handle_movement(_delta: float) -> void:
	var input_dir := Input.get_axis("move_left", "move_right")
	velocity.x = input_dir * move_speed
	move_and_slide()

func _apply_depth_transition(delta: float) -> void:
	position.y = move_toward(position.y, target_depth_y, depth_switch_speed * delta)
	var target_scale := Vector2.ONE * depth_scales[current_depth]
	scale = scale.lerp(target_scale, 10.0 * delta)
	var darkness := float(2 - current_depth) * 0.2
	var target_modulate := Color(1, 1, 1).lerp(Color(0.6, 0.6, 0.6), darkness)
	modulate = modulate.lerp(target_modulate, 10.0 * delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not is_dashing and not is_huifeng_animating:
		combo_engine.try_attack()
	if event.is_action_pressed("skill_1"):
		_try_cast_pojun()
	if event.is_action_pressed("skill_2"):
		_try_cast_huifeng()
	if event.is_action_pressed("skill_3"):
		_try_cast_ningshen()

func _try_cast_pojun() -> void:
	if not skill_system.try_cast("pojun"):
		return
	_start_dash()

func _start_dash() -> void:
	is_dashing = true
	dash_timer = POJUN_DASH_DURATION
	dash_direction = 1.0 if scale.x > 0 else -1.0
	$Sprite.color = Color(1.0, 0.5, 0.0)  # orange flash

func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity.x = dash_direction * POJUN_DASH_SPEED
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var enemy = col.get_collider()
		if enemy is BaseEnemy and enemy not in _dash_hit_enemies:
			_dash_hit_enemies.append(enemy)
			_hit_enemy_with_pojun(enemy)

	if dash_timer <= 0.0:
		_dash_hit_enemies.clear()
		is_dashing = false
		$Sprite.color = Color(0.2, 0.4, 0.8)  # restore blue

func _get_damage_multiplier() -> float:
	return NINGSHEN_BUFF_MULTIPLIER if has_damage_buff else 1.0

func _hit_enemy_with_pojun(enemy: Node) -> void:
	enemy.apply_hit(POJUN_STUN_DURATION, 300.0, 25.0 * _get_damage_multiplier(), global_position)

func _try_cast_huifeng() -> void:
	if not skill_system.try_cast("huifeng"):
		return
	_execute_huifeng()

func _execute_huifeng() -> void:
	is_huifeng_animating = true
	$Sprite.color = Color(0.5, 1.0, 0.5)  # green flash for AOE

	for enemy in _get_enemies_in_range(HUIFENG_RADIUS):
		var pull_dir := (global_position - enemy.global_position).normalized()
		enemy.apply_hit(0.3, HUIFENG_KNOCKBACK, HUIFENG_DAMAGE * _get_damage_multiplier(), global_position, pull_dir * HUIFENG_PULL_STRENGTH)

	await get_tree().create_timer(0.4).timeout
	is_huifeng_animating = false
	$Sprite.color = Color(0.2, 0.4, 0.8)  # restore blue

func _try_cast_ningshen() -> void:
	if not skill_system.try_cast("ningshen"):
		return
	_start_parry()

func _start_parry() -> void:
	is_parrying = true
	parry_timer = NINGSHEN_PARRY_WINDOW
	$Sprite.color = Color(0.3, 0.3, 1.0)  # blue tint for parry

func _end_parry(success: bool) -> void:
	is_parrying = false
	$Sprite.color = Color(0.2, 0.4, 0.8)  # restore blue
	if success:
		_execute_counter()

func _execute_counter() -> void:
	has_damage_buff = true
	var is_perfect: bool = parry_timer > NINGSHEN_PARRY_WINDOW - NINGSHEN_PERFECT_WINDOW
	var dmg := (40.0 * (2.0 if is_perfect else 1.0)) * _get_damage_multiplier()

	var enemies := _get_enemies_in_range(150.0)
	for enemy in enemies:
		enemy.apply_hit(0.6, 400.0, dmg, global_position)

	if _buff_timer and _buff_timer.time_left > 0:
		_buff_timer.timeout.disconnect(_clear_damage_buff)
	_buff_timer = get_tree().create_timer(NINGSHEN_BUFF_DURATION)
	_buff_timer.timeout.connect(_clear_damage_buff)

func _clear_damage_buff() -> void:
	has_damage_buff = false

func _get_enemies_in_range(radius: float) -> Array:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0, global_position)

	var results: Array = space_state.intersect_shape(query)
	var enemies: Array = []
	for result in results:
		var body := result.collider
		if body is BaseEnemy:
			enemies.append(body)
	return enemies

func take_damage(amount: float, source: Node) -> void:
	if is_parrying:
		_end_parry(true)
		return
	# Take damage normally in future iterations

func _on_combo_advanced(segment: int) -> void:
	match segment:
		1: $Sprite.color = Color(0.3, 0.5, 0.9)
		2: $Sprite.color = Color(0.4, 0.3, 0.9)
		3: $Sprite.color = Color(0.9, 0.4, 0.3)
		4: $Sprite.color = Color(0.9, 0.2, 0.2)
