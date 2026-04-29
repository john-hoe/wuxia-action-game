# src/vfx/vfx_manager.gd
# CPUParticles2D pool manager — ink-wash style VFX.
extends Node

class_name VFXManager

const POOL_SIZE := 20
const MAX_TOTAL := 200

var _pool: Array[CPUParticles2D] = []
var _active_count: int = 0
var _spark_mat: ParticleProcessMaterial
var _skill_mat: ParticleProcessMaterial


func _ready() -> void:
	_spark_mat = _make_spark_material()
	_skill_mat = _make_skill_material()
	for _i in POOL_SIZE:
		_create_pooled_particle()


func _make_spark_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.spread = 45.0
	m.gravity = Vector3(0, 60, 0)
	m.initial_velocity_min = 80.0
	m.initial_velocity_max = 160.0
	m.angular_velocity_min = -180.0
	m.angular_velocity_max = 180.0
	m.scale_min = 1.0
	m.scale_max = 1.5
	m.damping_min = 4.0
	m.damping_max = 8.0

	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.05, 0.05, 0.05, 0.9), Color(0.35, 0.35, 0.35, 0.6), Color(0.5, 0.5, 0.5, 0.15), Color(0.15, 0.15, 0.15, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	m.color_ramp = tex

	return m


func _make_skill_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.spread = 180.0
	m.gravity = Vector3(0, -10, 0)
	m.initial_velocity_min = 40.0
	m.initial_velocity_max = 100.0
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	m.radial_accel_min = -50.0
	m.radial_accel_max = 50.0
	m.scale_min = 1.5
	m.scale_max = 3.0
	m.damping_min = 6.0
	m.damping_max = 12.0

	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.92, 0.72, 0.18, 0.8), Color(0.25, 0.7, 0.45, 0.5), Color(0.15, 0.15, 0.15, 0.3), Color(0.05, 0.05, 0.05, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	m.color_ramp = tex

	return m


func _create_pooled_particle() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.visible = false
	p.amount = 8
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.speed_scale = 1.0
	p.finished.connect(_recycle.bind(p))
	add_child(p)
	_pool.append(p)
	return p


func spawn(pos: Vector2, type: String = "spark") -> void:
	var p: CPUParticles2D = _acquire()
	if not p:
		return
	p.position = pos
	match type:
		"spark":
			p.amount = 6
			p.lifetime = 0.35
			p.speed_scale = 1.0
			p.process_material = _spark_mat
		"skill":
			p.amount = 16
			p.lifetime = 0.7
			p.speed_scale = 1.3
			p.process_material = _skill_mat
		"heavy":
			p.amount = 12
			p.lifetime = 0.5
			p.speed_scale = 1.5
			p.process_material = _spark_mat
		_:
			p.amount = 6
			p.lifetime = 0.35
			p.speed_scale = 1.0
			p.process_material = _spark_mat
	p.visible = true
	p.restart()
	_active_count += 1


func _acquire() -> CPUParticles2D:
	for p in _pool:
		if not p.emitting:
			return p
	if _active_count < MAX_TOTAL:
		return _create_pooled_particle()
	return null


func _recycle(p: CPUParticles2D) -> void:
	p.visible = false
	_active_count -= 1


func burst(pos: Vector2, count: int, type: String = "spark") -> void:
	for _i in count:
		var offset := Vector2(randf_range(-12, 12), randf_range(-12, 12))
		spawn(pos + offset, type)
