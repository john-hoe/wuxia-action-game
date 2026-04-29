# src/enemies/base_enemy.gd
extends CharacterBody2D
class_name BaseEnemy

var health: float = 100.0
var is_stunned: bool = false
var _stun_timer: SceneTreeTimer = null

func apply_hit(stun_duration: float, knockback_force: float, damage: float, attacker_pos: Vector2) -> void:
    health -= damage
    is_stunned = true
    velocity.x = knockback_force * (-1.0 if global_position.x < attacker_pos.x else 1.0)
    if _stun_timer and _stun_timer.time_left > 0:
        _stun_timer.timeout.disconnect(_unstun)
    _stun_timer = get_tree().create_timer(stun_duration)
    _stun_timer.timeout.connect(_unstun)
    if health <= 0:
        queue_free()

func _unstun() -> void:
    is_stunned = false
