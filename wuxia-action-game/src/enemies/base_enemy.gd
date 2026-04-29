# src/enemies/base_enemy.gd
extends CharacterBody2D
class_name BaseEnemy

var health: float = 100.0
var is_stunned: bool = false
var _stun_timer: SceneTreeTimer = null

func apply_hit(stun_duration: float, knockback_force: float, damage: float, attacker_pos: Vector2, extra_impulse: Vector2 = Vector2.ZERO) -> void:
    health -= damage
    is_stunned = true
    if _stun_timer and _stun_timer.time_left > 0:
        _stun_timer.timeout.disconnect(_unstun)
    _stun_timer = get_tree().create_timer(stun_duration)
    _stun_timer.timeout.connect(_unstun)
    velocity = extra_impulse
    if knockback_force > 0:
        var kb_dir := -1.0 if global_position.x < attacker_pos.x else 1.0
        velocity.x += kb_dir * knockback_force
    if health <= 0:
        queue_free()

func _unstun() -> void:
    is_stunned = false
