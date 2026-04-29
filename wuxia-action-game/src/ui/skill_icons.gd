# src/ui/skill_icons.gd
# Three skill cooldown icons with ready/cooldown visual states.
extends HBoxContainer

const SKILL_NAMES := {
	"pojun": {label = "破军", order = 0},
	"huifeng": {label = "回风", order = 1},
	"ningshen": {label = "凝神", order = 2},
}

var _icons: Dictionary = {}


func _ready() -> void:
	_build_icons()


func _build_icons() -> void:
	for skill_id in SKILL_NAMES:
		var info: Dictionary = SKILL_NAMES[skill_id]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(52, 52)
		panel.name = skill_id

		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.05, 0.05, 0.85)
		bg.border_width_left = 2
		bg.border_width_right = 2
		bg.border_width_top = 2
		bg.border_width_bottom = 2
		bg.border_color = Color(0.6, 0.45, 0.1, 0.6)
		bg.corner_radius_top_left = 6
		bg.corner_radius_top_right = 6
		bg.corner_radius_bottom_left = 6
		bg.corner_radius_bottom_right = 6
		panel.add_theme_stylebox_override("panel", bg)

		var vbox := VBoxContainer.new()
		panel.add_child(vbox)

		var label := Label.new()
		label.text = info.label
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.18, 1))
		label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(label)

		var cd_bar := ProgressBar.new()
		cd_bar.max_value = 1.0
		cd_bar.value = 0.0
		cd_bar.name = "CooldownBar"
		cd_bar.custom_minimum_size = Vector2(44, 6)
		cd_bar.show_percentage = false
		var cd_bg := StyleBoxFlat.new()
		cd_bg.bg_color = Color(0.02, 0.02, 0.02, 0.9)
		cd_bg.corner_radius_top_left = 3
		cd_bg.corner_radius_top_right = 3
		cd_bg.corner_radius_bottom_left = 3
		cd_bg.corner_radius_bottom_right = 3
		cd_bar.add_theme_stylebox_override("background", cd_bg)
		var cd_fill := StyleBoxFlat.new()
		cd_fill.bg_color = Color(0.5, 0.7, 0.9, 0.8)
		cd_fill.corner_radius_top_left = 3
		cd_fill.corner_radius_top_right = 3
		cd_fill.corner_radius_bottom_left = 3
		cd_fill.corner_radius_bottom_right = 3
		cd_bar.add_theme_stylebox_override("fill", cd_fill)
		vbox.add_child(cd_bar)

		add_child(panel)
		_icons[skill_id] = {panel = panel, cd_bar = cd_bar, label = label}


func update_cooldown(skill_id: String, remaining: float) -> void:
	if not _icons.has(skill_id):
		return
	var info: Dictionary = _icons[skill_id]
	var max_cd: float = _get_max_cooldown(skill_id)
	var ratio: float = remaining / max(max_cd, 0.01)
	info.cd_bar.max_value = max_cd
	info.cd_bar.value = remaining

	var is_ready := remaining <= 0.0
	var label: Label = info.label
	label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.18, 1) if is_ready else Color(0.4, 0.4, 0.4, 1))

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_width_top = 2
	bg.border_width_bottom = 2
	bg.border_color = Color(0.92, 0.72, 0.18, 0.9) if is_ready else Color(0.4, 0.4, 0.4, 0.6)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	info.panel.add_theme_stylebox_override("panel", bg)


func _get_max_cooldown(skill_id: String) -> float:
	match skill_id:
		"pojun": return 3.0
		"huifeng": return 5.0
		"ningshen": return 6.0
	return 5.0
