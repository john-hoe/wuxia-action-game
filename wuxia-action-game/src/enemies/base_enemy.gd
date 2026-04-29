# src/enemies/base_enemy.gd
extends CharacterBody2D
class_name BaseEnemy

enum HitReaction { LIGHT_STUN, HEAVY_STAGGER, LAUNCH, KNOCKDOWN }

var health: float = 100.0
var is_stunned: bool = false
var _stun_timer: SceneTreeTimer = null
var attack_damage: float = 10.0
const MAX_KNOCKBACK: float = 500.0

func apply_hit(stun_duration: float, knockback_force: float, damage: float, attacker_pos: Vector2, extra_impulse: Vector2 = Vector2.ZERO, reaction: HitReaction = HitReaction.LIGHT_STUN, combo_count: int = 1) -> void:
    health -= damage
    is_stunned = true
    var stun = stun_duration
    var knockback = knockback_force
    match reaction:
        HitReaction.LIGHT_STUN:
            stun = min(stun, 0.3)
            knockback *= 0.5
        HitReaction.HEAVY_STAGGER:
            stun = max(stun, 0.4)
        HitReaction.LAUNCH:
            extra_impulse.y -= 300
            stun = 1.0
        HitReaction.KNOCKDOWN:
            extra_impulse.x *= 1.5
            extra_impulse.y -= 100
            stun = 0.8
    # Scale knockback with combo count (linear: 1x at hit 1, 3x at hit 12)
    knockback *= lerpf(1.0, 3.0, float(combo_count) / 12.0)
    knockback = clampf(knockback, 0.0, MAX_KNOCKBACK)
    if _stun_timer and _stun_timer.time_left > 0:
        _stun_timer.timeout.disconnect(_unstun)
    _stun_timer = get_tree().create_timer(stun)
    _stun_timer.timeout.connect(_unstun)
    velocity = extra_impulse
    if knockback > 0:
        var kb_dir := -1.0 if global_position.x < attacker_pos.x else 1.0
        velocity.x += kb_dir * knockback
    if health <= 0:
        queue_free()

func _on_attack_hitbox_body_entered(body: Node) -> void:
    if body.has_method("take_damage"):
        body.take_damage(attack_damage, self)

func _unstun() -> void:
    is_stunned = false
