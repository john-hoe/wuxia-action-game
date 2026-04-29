# src/ui/hp_bar.gd
# Wuxia-styled health bar with tween-animated HP transitions.
extends ProgressBar

@export var animation_duration: float = 0.3

var _tween: Tween
var _display_value: float


func _ready() -> void:
	_display_value = value
	update_style()


func set_hp(current: float, maximum: float) -> void:
	max_value = maximum
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "value", current, animation_duration)
	_tween.tween_callback(update_style)


func update_style() -> void:
	var ratio: float = value / max(max_value, 1.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.85)  # ink black bg
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.45, 0.1, 0.8)  # dim gold border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("background", style)

	var fill := StyleBoxFlat.new()
	if ratio > 0.5:
		fill.bg_color = Color(0.82, 0.18, 0.12, 1)  # vermilion
	elif ratio > 0.25:
		fill.bg_color = Color(1.0, 0.55, 0.1, 1)  # orange warning
	else:
		fill.bg_color = Color(0.9, 0.15, 0.1, 1)  # deep red critical
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	add_theme_stylebox_override("fill", fill)
