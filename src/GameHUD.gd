# GameHUD.gd
# Godot 4.4 / GDScript
# HP/힌트/GAME OVER 라벨만 전담하는 HUD 모듈
# - GameLayer에서 색상/폰트 사이즈를 주입하고 add_child()만 하면 바로 사용 가능
extends Control

@export var text_color: Color = Color.WHITE
@export var gameover_text_color: Color = Color(1, 0.4, 0.4)
@export var font_size_label: int = 20
@export var font_size_hint: int = 24
@export var font_size_gameover: int = 64

var _hp_label: Label
var _hint_label: Label
var _game_over_label: Label

func _ready() -> void:
	_set_full_rect(self)
	var view_size: Vector2 = get_viewport_rect().size

	_hp_label = Label.new()
	_hp_label.text = "HP: 0 / 0"
	_hp_label.add_theme_color_override("font_color", text_color)
	_hp_label.add_theme_font_size_override("font_size", font_size_label)
	_hp_label.position = Vector2(12, 12)
	add_child(_hp_label)

	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.add_theme_color_override("font_color", text_color)
	_hint_label.add_theme_font_size_override("font_size", font_size_hint)
	_hint_label.position = Vector2(12, 44)
	add_child(_hint_label)

	_game_over_label = Label.new()
	_game_over_label.text = "GAME OVER"
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.add_theme_color_override("font_color", gameover_text_color)
	_game_over_label.add_theme_font_size_override("font_size", font_size_gameover)
	_game_over_label.position = Vector2(view_size.x * 0.5 - 220, view_size.y * 0.35)
	_game_over_label.visible = false
	add_child(_game_over_label)

# --- API ---
func set_hp(current_hp: int, max_hp: int) -> void:
	if is_instance_valid(_hp_label):
		_hp_label.text = "HP: %d / %d" % [current_hp, max_hp]

func tint_hp_hit() -> void:
	if is_instance_valid(_hp_label):
		_hp_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))

func tint_hp_normal() -> void:
	if is_instance_valid(_hp_label):
		_hp_label.add_theme_color_override("font_color", text_color)

func set_hint(text: String) -> void:
	if is_instance_valid(_hint_label):
		_hint_label.text = text

func show_game_over() -> void:
	if is_instance_valid(_game_over_label):
		_game_over_label.visible = true

# ---- 유틸 ----
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
