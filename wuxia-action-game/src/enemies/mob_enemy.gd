# src/enemies/mob_enemy.gd
extends BaseEnemy
class_name MobEnemy

@export var move_speed: float = 150.0
@export var detection_range: float = 500.0
@export var attack_range: float = 60.0
@export var attack_cooldown: float = 1.5

enum State { IDLE, CHASE, ATTACK, STUNNED, DEAD }
var current_state: State = State.IDLE
var attack_timer: float = 0.0
var player_ref: Node2D = null
var facing_dir: float = 1.0
var _attack_windup_timer: SceneTreeTimer = null
var _current_attack_type: int = 0  # 0 = punch (fast/weak), 1 = kick (slow/strong)

@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	health = 80.0
	attack_damage = 10.0
	player_ref = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if health <= 0:
		_die()
		return

	if is_stunned:
		current_state = State.STUNNED
		move_and_slide()
		return

	attack_timer -= delta
	if not player_ref:
		return

	var dist_to_player := global_position.distance_to(player_ref.global_position)

	match current_state:
		State.IDLE:
			if dist_to_player <= detection_range:
				current_state = State.CHASE
		State.CHASE:
			_chase_player(dist_to_player)
		State.ATTACK:
			pass  # animation-driven windup
		State.STUNNED:
			if not is_stunned:
				current_state = State.IDLE

func _chase_player(dist: float) -> void:
	var dir := (player_ref.global_position - global_position).normalized()
	facing_dir = sign(dir.x)
	velocity.x = dir.x * move_speed

	if dist <= attack_range and attack_timer <= 0:
		_start_attack()
	elif dist > detection_range * 1.2:
		current_state = State.IDLE
		velocity.x = 0

	move_and_slide()

func _start_attack() -> void:
	current_state = State.ATTACK
	attack_timer = attack_cooldown
	if _attack_windup_timer and _attack_windup_timer.time_left > 0:
		_attack_windup_timer.timeout.disconnect(_execute_attack)
	_current_attack_type = randi() % 2
	_play_anim("attack_%d" % _current_attack_type)
	var windup: float = 0.4 if _current_attack_type == 1 else 0.2
	_attack_windup_timer = get_tree().create_timer(windup)
	_attack_windup_timer.timeout.connect(_execute_attack)

func _execute_attack() -> void:
	if current_state != State.ATTACK:
		return
	if not player_ref:
		return
	if _current_attack_type == 1:
		_execute_kick()
	else:
		_execute_punch()
	current_state = State.CHASE

func _execute_punch() -> void:
	if global_position.distance_to(player_ref.global_position) <= attack_range * 1.3:
		player_ref.take_damage(8.0, self)

func _execute_kick() -> void:
	if global_position.distance_to(player_ref.global_position) <= attack_range * 1.8:
		player_ref.take_damage(14.0, self)

func _die() -> void:
	current_state = State.DEAD
	_play_anim("death")
	queue_free()


func _play_anim(name: String) -> void:
	if anim and anim.has_animation(name):
		anim.play(name)


func apply_hit(stun_duration: float, knockback_force: float, damage: float, attacker_pos: Vector2, extra_impulse: Vector2 = Vector2.ZERO, reaction: HitReaction = HitReaction.LIGHT_STUN, combo_count: int = 1) -> void:
	super.apply_hit(stun_duration, knockback_force, damage, attacker_pos, extra_impulse, reaction, combo_count)
	if health > 0:
		_play_anim("hurt")
