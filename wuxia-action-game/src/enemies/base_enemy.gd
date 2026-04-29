# src/enemies/base_enemy.gd
extends CharacterBody2D
class_name BaseEnemy

var health: float = 100.0
var is_stunned: bool = false

func apply_hit(stun_duration: float, knockback_force: float, damage: float) -> void:
    health -= damage
    is_stunned = true
    velocity.x = knockback_force * (1.0 if global_position.x < get_parent().global_position.x else -1.0)
    get_tree().create_timer(stun_duration).timeout.connect(func(): is_stunned = false)
    if health <= 0:
        queue_free()
