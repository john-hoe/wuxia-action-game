# src/combat/player_controller.gd
extends CharacterBody2D

const MOVE_SPEED: float = 400.0
const DEPTH_SWITCH_SPEED: float = 200.0
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

const DODGE_SPEED: float = 800.0
const DODGE_DURATION: float = 0.2
const DODGE_IFRAMES: float = 0.15
const DODGE_COOLDOWN: float = 1.0

var is_parrying: bool = false
var parry_timer: float = 0.0
var has_damage_buff: bool = false
var _buff_timer: SceneTreeTimer = null
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_remaining: float = 0.0
var is_invulnerable: bool = false
var _iframes_timer: SceneTreeTimer = null
var facing_dir: float = 1.0

const PLAYER_MAX_HEALTH: float = 100.0
var player_health: float = PLAYER_MAX_HEALTH

signal health_changed(current_hp: float, max_hp: float)
signal combo_updated(current_combo: int, max_combo: int)

@onready var combo_engine: Node = $ComboEngine
@onready var skill_system: SkillSystem = $SkillSystem
@onready var hit_feedback: HitFeedback = $HitFeedback
@onready var input_buffer: InputBuffer = $InputBuffer
@onready var anim: Node = $PlayerAnimation
@onready var _vfx_mgr: Node = $"../VFXRoot/VFXManager"

func _ready() -> void:
	add_to_group("player")
	target_depth_y = depth_y_positions[current_depth]
	position.y = target_depth_y
	combo_engine.combo_advanced.connect(_on_combo_advanced)
	combo_engine.combo_ended.connect(_on_combo_ended)
	combo_engine.aerial_state = $AerialState
	combo_engine.load_derivation_table(ComboData.DERIVATIONS)
	combo_engine.derivation_triggered.connect(_on_derivation_triggered)
	$AerialState.aerial_attack.connect(_on_aerial_attack)

func _physics_process(delta: float) -> void:
	_handle_depth_input()
	if is_dashing:
		_process_dash(delta)
	elif is_dodging:
		move_and_slide()
	else:
		_handle_movement(delta)
	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			_end_parry(false)
	if is_dodging:
		dodge_timer -= delta
		if dodge_timer <= 0.0:
			_end_dodge()
	if dodge_cooldown_remaining > 0.0:
		dodge_cooldown_remaining -= delta
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
	if input_dir != 0.0:
		facing_dir = input_dir
		anim.play_walk()
	else:
		anim.play_idle()
	velocity.x = input_dir * MOVE_SPEED
	move_and_slide()

func _apply_depth_transition(delta: float) -> void:
	position.y = move_toward(position.y, target_depth_y, DEPTH_SWITCH_SPEED * delta)
	var target_scale := Vector2.ONE * depth_scales[current_depth]
	scale = scale.lerp(target_scale, 10.0 * delta)
	var darkness := float(2 - current_depth) * 0.2
	var target_modulate := Color(1, 1, 1).lerp(Color(0.6, 0.6, 0.6), darkness)
	modulate = modulate.lerp(target_modulate, 10.0 * delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		input_buffer.push("attack")
	if event.is_action_pressed("skill_1"):
		input_buffer.push("skill_1")
	if event.is_action_pressed("skill_2"):
		input_buffer.push("skill_2")
	if event.is_action_pressed("skill_3"):
		input_buffer.push("skill_3")
	if event.is_action_pressed("dodge"):
		input_buffer.push("dodge")

func _process(_delta: float) -> void:
	if input_buffer.consume("attack") and not is_dashing and not is_huifeng_animating and not is_dodging:
		combo_engine.try_attack()
	elif input_buffer.consume("skill_1") and not is_dodging:
		_try_cast_pojun()
	elif input_buffer.consume("skill_2") and not is_dodging:
		_try_cast_huifeng()
	elif input_buffer.consume("skill_3") and not is_dodging:
		_try_cast_ningshen()
	elif input_buffer.consume("dodge") and not is_dodging and dodge_cooldown_remaining <= 0 and not is_dashing and not is_parrying:
		_start_dodge()

func _try_cast_pojun() -> void:
	if combo_engine.try_skill_derivation("pojun"):
		return
	if not skill_system.try_cast("pojun"):
		return
	_start_dash()

func _start_dash() -> void:
	is_dashing = true
	dash_timer = POJUN_DASH_DURATION
	dash_direction = facing_dir
	anim.play_dash()
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
	hit_feedback.trigger_hitstop(0.05)
	enemy.apply_hit(POJUN_STUN_DURATION, 300.0, 25.0 * _get_damage_multiplier(), global_position, Vector2.ZERO, BaseEnemy.HitReaction.HEAVY_STAGGER, combo_engine.total_hits)
	if _vfx_mgr:
		_vfx_mgr.spawn(enemy.global_position, "spark")

func _hit_enemies_in_melee(segment: int) -> void:
	var base_damage: float = 7.0 + segment * 3.0
	var knockback: float = 80.0 + segment * 30.0
	var stun: float = 0.15 + segment * 0.05
	var reaction := BaseEnemy.HitReaction.HEAVY_STAGGER if segment >= 3 else BaseEnemy.HitReaction.LIGHT_STUN
	hit_feedback.trigger_hitstop(0.04)
	for enemy in _get_enemies_in_range(75.0):
		enemy.apply_hit(stun, knockback, base_damage * _get_damage_multiplier(), global_position, Vector2.ZERO, reaction, combo_engine.total_hits)
		if _vfx_mgr:
			_vfx_mgr.spawn(enemy.global_position, "spark")
		break

func _try_cast_huifeng() -> void:
	if combo_engine.try_skill_derivation("huifeng"):
		return
	if not skill_system.try_cast("huifeng"):
		return
	_execute_huifeng()

func _execute_huifeng() -> void:
	is_huifeng_animating = true
	anim.play_skill("huifeng")
	$Sprite.color = Color(0.5, 1.0, 0.5)  # green flash for AOE
	hit_feedback.trigger_hitstop_with_shake(0.04, 3.0)

	if _vfx_mgr:
		_vfx_mgr.burst(global_position, 5, "skill")

	for enemy in _get_enemies_in_range(HUIFENG_RADIUS):
		var pull_dir: Vector2 = (global_position - enemy.global_position).normalized()
		enemy.apply_hit(0.3, HUIFENG_KNOCKBACK, HUIFENG_DAMAGE * _get_damage_multiplier(), global_position, pull_dir * HUIFENG_PULL_STRENGTH, BaseEnemy.HitReaction.LAUNCH, combo_engine.total_hits)

	await get_tree().create_timer(0.4).timeout
	is_huifeng_animating = false
	$Sprite.color = Color(0.2, 0.4, 0.8)  # restore blue

func _try_cast_ningshen() -> void:
	if combo_engine.try_skill_derivation("ningshen"):
		return
	if not skill_system.try_cast("ningshen"):
		return
	_start_parry()

func _start_parry() -> void:
	is_parrying = true
	parry_timer = NINGSHEN_PARRY_WINDOW
	anim.play_parry()
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
	hit_feedback.trigger_hitstop_with_shake(0.05, 4.0 if is_perfect else 2.0)

	if _vfx_mgr:
		_vfx_mgr.burst(global_position, 6, "heavy")

	var enemies := _get_enemies_in_range(150.0)
	for enemy in enemies:
		enemy.apply_hit(0.6, 400.0, dmg, global_position, Vector2.ZERO, BaseEnemy.HitReaction.KNOCKDOWN, combo_engine.total_hits)
		if _vfx_mgr:
			_vfx_mgr.spawn(enemy.global_position, "heavy")

	if _buff_timer and _buff_timer.time_left > 0:
		_buff_timer.timeout.disconnect(_clear_damage_buff)
	_buff_timer = get_tree().create_timer(NINGSHEN_BUFF_DURATION)
	_buff_timer.timeout.connect(_clear_damage_buff)

func _clear_damage_buff() -> void:
	has_damage_buff = false

func _start_dodge() -> void:
	is_dodging = true
	is_invulnerable = true
	dodge_timer = DODGE_DURATION
	dodge_cooldown_remaining = DODGE_COOLDOWN
	anim.play_dodge()

	var direction := Input.get_axis("move_left", "move_right")
	if direction == 0.0:
		direction = facing_dir
	velocity.x = direction * DODGE_SPEED

	$Sprite.color = Color(1.0, 1.0, 1.0, 0.5)  # semi-transparent white for dodge

	if _iframes_timer and _iframes_timer.time_left > 0:
		_iframes_timer.timeout.disconnect(_end_dodge_iframes)
	_iframes_timer = get_tree().create_timer(DODGE_IFRAMES)
	_iframes_timer.timeout.connect(_end_dodge_iframes)

func _end_dodge() -> void:
	is_dodging = false
	$Sprite.color = Color(0.2, 0.4, 0.8)  # restore blue

func _end_dodge_iframes() -> void:
	is_invulnerable = false

func _get_enemies_in_range(radius: float) -> Array[BaseEnemy]:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0, global_position)

	var results: Array[Dictionary] = space_state.intersect_shape(query)
	var enemies: Array[BaseEnemy] = []
	for result in results:
		var body: Node = result.collider
		if body is BaseEnemy:
			enemies.append(body)
	return enemies

func take_damage(amount: float, source: Node) -> void:
	if is_invulnerable:
		return
	if is_parrying:
		_end_parry(true)
		return
	anim.play_hurt()
	player_health -= amount
	if player_health <= 0:
		player_health = 0
	_update_debug_label()

func _update_debug_label() -> void:
	health_changed.emit(player_health, PLAYER_MAX_HEALTH)
	combo_updated.emit(combo_engine.total_hits, 12)

func _on_combo_advanced(segment: int) -> void:
	match segment:
		1: $Sprite.color = Color(0.3, 0.5, 0.9)
		2: $Sprite.color = Color(0.4, 0.3, 0.9)
		3: $Sprite.color = Color(0.9, 0.4, 0.3)
		4: $Sprite.color = Color(0.9, 0.2, 0.2)
	anim.play_attack(segment)
	_hit_enemies_in_melee(segment)
	_update_debug_label()

func _on_combo_ended(_final_segment: int) -> void:
	_update_debug_label()

func _on_aerial_attack(attack_num: int) -> void:
	combo_engine.register_hit()
	$Sprite.color = Color(0.9, 0.7, 0.2)  # gold for aerial hits
	hit_feedback.trigger_hitstop(0.03)
	for enemy in _get_enemies_in_range(90.0):
		enemy.apply_hit(0.25, 120.0, 15.0 * _get_damage_multiplier(), global_position, Vector2(0, -80), BaseEnemy.HitReaction.LAUNCH, combo_engine.total_hits)
		if _vfx_mgr:
			_vfx_mgr.spawn(enemy.global_position, "spark")
		break

func _on_derivation_triggered(segment: int, skill_id: String) -> void:
	var deriv_data: Dictionary = ComboData.DERIVATIONS.get(segment, {}).get(skill_id, {})
	if deriv_data.is_empty():
		return
	var damage_mult: float = deriv_data.get("damage_mult", 1.0)
	var effect: String = deriv_data.get("effect", "")
	var base_damage: float
	match skill_id:
		"pojun": base_damage = 25.0
		"huifeng": base_damage = 30.0
		"ningshen": base_damage = 40.0
		_: base_damage = 20.0
	var dmg := base_damage * damage_mult * _get_damage_multiplier()

	match effect:
		"gap_close", "pierce", "armor_break":
			$Sprite.color = Color(1.0, 0.5, 0.0)
			hit_feedback.trigger_hitstop(0.05)
			for enemy in _get_enemies_in_range(150.0):
				enemy.apply_hit(0.35, 300.0, dmg, global_position, Vector2.ZERO, BaseEnemy.HitReaction.HEAVY_STAGGER, combo_engine.total_hits)
				break
		"knockback", "finisher":
			hit_feedback.trigger_hitstop_with_shake(0.06, 5.0)
			for enemy in _get_enemies_in_range(200.0):
				var kb_dir: Vector2 = (enemy.global_position - global_position).normalized()
				enemy.apply_hit(0.4, 350.0, dmg, global_position, kb_dir * 150.0, BaseEnemy.HitReaction.KNOCKDOWN, combo_engine.total_hits)
		"launch":
			hit_feedback.trigger_hitstop(0.04)
			for enemy in _get_enemies_in_range(120.0):
				enemy.apply_hit(0.35, 250.0, dmg, global_position, Vector2(0, -200), BaseEnemy.HitReaction.LAUNCH, combo_engine.total_hits)
				break
		"pull_strong", "tornado":
			hit_feedback.trigger_hitstop_with_shake(0.05, 3.0)
			for enemy in _get_enemies_in_range(180.0):
				var pull_dir: Vector2 = (global_position - enemy.global_position).normalized()
				enemy.apply_hit(0.3, 200.0, dmg, global_position, pull_dir * 200.0, BaseEnemy.HitReaction.LAUNCH, combo_engine.total_hits)
		"extended_parry":
			_start_parry()
		"advance_combo":
			hit_feedback.trigger_hitstop(0.03)
			for enemy in _get_enemies_in_range(100.0):
				enemy.apply_hit(0.2, 100.0, dmg, global_position, Vector2.ZERO, BaseEnemy.HitReaction.LIGHT_STUN, combo_engine.total_hits)
				break
		"buff_extend":
			if has_damage_buff:
				if _buff_timer and _buff_timer.time_left > 0:
					_buff_timer.timeout.disconnect(_clear_damage_buff)
				_buff_timer = get_tree().create_timer(NINGSHEN_BUFF_DURATION)
				_buff_timer.timeout.connect(_clear_damage_buff)
			hit_feedback.trigger_hitstop(0.03)
			for enemy in _get_enemies_in_range(120.0):
				enemy.apply_hit(0.2, 100.0, dmg, global_position, Vector2.ZERO, BaseEnemy.HitReaction.LIGHT_STUN, combo_engine.total_hits)
				break
		"perfect_counter":
			hit_feedback.trigger_hitstop_with_shake(0.08, 6.0)
			for enemy in _get_enemies_in_range(180.0):
				enemy.apply_hit(0.6, 500.0, dmg, global_position, Vector2.ZERO, BaseEnemy.HitReaction.KNOCKDOWN, combo_engine.total_hits)
		_:
			hit_feedback.trigger_hitstop(0.03)
			for enemy in _get_enemies_in_range(100.0):
				enemy.apply_hit(0.2, 100.0, dmg, global_position, Vector2.ZERO, BaseEnemy.HitReaction.LIGHT_STUN, combo_engine.total_hits)
				break
