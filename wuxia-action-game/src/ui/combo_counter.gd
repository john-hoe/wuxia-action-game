# src/ui/combo_counter.gd
# Wuxia combo counter with scale-bounce animation and color gradient.
extends RichTextLabel

var _current_combo: int = 0
var _max_combo: int = 12
var _tween: Tween


func _ready() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	_display_combo(0)


func set_combo(current: int, maximum: int = 12) -> void:
	_max_combo = maximum
	var prev := _current_combo
	_current_combo = current
	_display_combo(current)
	if current > 0 and current != prev:
		_bounce_animate(current == maximum)


func _display_combo(count: int) -> void:
	var color: String
	if count >= 12:
		color = "gold"
	elif count >= 8:
		color = "orange"
	elif count >= 4:
		color = "coral"
	else:
		color = "white"

	text = "[center][color=%s]%d/%d[/color][/center]" % [color, count, _max_combo]
	set_text(text)


func _bounce_animate(is_max: bool) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	pivot_offset = size / 2.0
	scale = Vector2(1.3 if is_max else 1.15, 1.3 if is_max else 1.15)
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.25)
