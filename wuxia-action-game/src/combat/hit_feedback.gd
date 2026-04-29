# src/combat/hit_feedback.gd
extends Node

class_name HitFeedback

const DEFAULT_HITSTOP_DURATION: float = 0.04
const SHAKE_DECAY: float = 0.9
const SHAKE_DURATION: float = 0.1

var _hitstop_timer: SceneTreeTimer = null
var _camera_ref: Camera2D = null
var _original_camera_offset: Vector2 = Vector2.ZERO
var _is_shaking: bool = false
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0


func _ready() -> void:
	_camera_ref = get_viewport().get_camera_2d()
	if _camera_ref:
		_original_camera_offset = _camera_ref.offset


func trigger_hitstop(duration: float = DEFAULT_HITSTOP_DURATION, pos: Vector2 = Vector2.ZERO) -> void:
	if _hitstop_timer and _hitstop_timer.time_left > 0:
		if _hitstop_timer.timeout.is_connected(_end_hitstop):
			_hitstop_timer.timeout.disconnect(_end_hitstop)

	Engine.time_scale = 0.05
	_hitstop_timer = get_tree().create_timer(duration, true, false, true)
	_hitstop_timer.timeout.connect(_end_hitstop)
	if pos != Vector2.ZERO:
		spawn_vfx(pos, "spark")


func _end_hitstop() -> void:
	Engine.time_scale = 1.0
	_hitstop_timer = null


func trigger_shake(intensity: float = 3.0) -> void:
	if not _camera_ref:
		return

	if _is_shaking:
		_shake_intensity = max(_shake_intensity, intensity)
		_shake_timer = SHAKE_DURATION
		return

	_is_shaking = true
	_shake_intensity = intensity
	_shake_timer = SHAKE_DURATION
	_start_shake_coroutine()


func _start_shake_coroutine() -> void:
	while _shake_timer > 0:
		if not _camera_ref:
			break

		var shake_offset := Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
		_camera_ref.offset = _original_camera_offset + shake_offset

		_shake_intensity *= SHAKE_DECAY
		_shake_timer -= get_process_delta_time()

		await get_tree().process_frame

	if _camera_ref:
		_camera_ref.offset = _original_camera_offset
	_is_shaking = false


func trigger_hitstop_with_shake(hs_dur: float = DEFAULT_HITSTOP_DURATION, shake_intensity: float = 3.0) -> void:
	trigger_hitstop(hs_dur)
	trigger_shake(shake_intensity)

func trigger_hitstop_with_shake_and_vfx(hs_dur: float, shake_intensity: float, pos: Vector2, vfx_type: String = "spark") -> void:
	trigger_hitstop(hs_dur, pos)
	trigger_shake(shake_intensity)

func spawn_vfx(pos: Vector2, type: String = "spark") -> void:
	var vfx_root: Node = get_node_or_null("../../VFXRoot")
	if not vfx_root:
		return
	var mgr: Node = vfx_root.get_node_or_null("VFXManager")
	if mgr and mgr.has_method("spawn"):
		mgr.spawn(pos, type)
