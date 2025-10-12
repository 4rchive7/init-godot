# Godot 4.4 / GDScript
# AppRoot: 로딩 → 메인 → 게임 전환 관리
extends Control

@export var bg_color: Color = Color(0.08, 0.10, 0.12, 1.0)
@export var text_color: Color = Color.WHITE
@export var title_text: String = "MY GAME"
@export var font_size_title: int = 56
@export var font_size_button: int = 28

@export_file("*.gd") var loading_screen_script_path: String = "res://src/LoadingScreen.gd"
@export_file("*.gd") var game_layer_script_path: String = "res://src/Game.gd"

const STATE_MAIN = 1
const STATE_GAME = 2
var _state: int = 0

var _bg_rect: ColorRect
var _center_layer: Control

var _menu_box: VBoxContainer
var _btn_start: Button
var _btn_options: Button
var _game_layer: Node

func _ready() -> void:
	# 전체 앵커
	anchor_left = 0
	anchor_top = 0
	anchor_right = 1
	anchor_bottom = 1
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0

	# 배경
	_bg_rect = ColorRect.new()
	_bg_rect.color = bg_color
	_set_full_rect(_bg_rect)
	add_child(_bg_rect)

	# 중앙 레이어 (UI 및 로딩용)
	_center_layer = Control.new()
	_set_full_rect(_center_layer)
	add_child(_center_layer)

	_show_loading_then_main()

# ================= 로딩 화면 =================
func _show_loading_then_main() -> void:
	_clear_center_layer()
	var LS = load(loading_screen_script_path)
	if LS == null:
		push_error("LoadingScreen.gd 를 찾을 수 없습니다.")
		_switch_to_main()
		return

	var loading = (LS as Script).new()
	if loading is Control:
		_center_layer.add_child(loading)
		loading.finished.connect(func():
			if is_instance_valid(loading):
				loading.queue_free()
			_switch_to_main()
		)
	else:
		push_error("LoadingScreen이 Control을 상속하지 않습니다.")
		_switch_to_main()

# ================= 메인 화면 =================
func _switch_to_main() -> void:
	_state = STATE_MAIN
	_clear_center_layer()
	if is_instance_valid(_game_layer):
		_game_layer.queue_free()

	var center = CenterContainer.new()
	_set_full_rect(center)
	_center_layer.add_child(center)

	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 16)
	center.add_child(_menu_box)

	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", text_color)
	title.add_theme_font_size_override("font_size", font_size_title)
	_menu_box.add_child(title)

	_btn_start = Button.new()
	_btn_start.text = "시작"
	_btn_start.custom_minimum_size = Vector2(240, 48)
	_btn_start.add_theme_font_size_override("font_size", font_size_button)
	_btn_start.pressed.connect(_on_start_pressed)
	_menu_box.add_child(_btn_start)

	_btn_options = Button.new()
	_btn_options.text = "옵션"
	_btn_options.custom_minimum_size = Vector2(240, 48)
	_btn_options.add_theme_font_size_override("font_size", font_size_button)
	_btn_options.pressed.connect(_on_options_pressed)
	_menu_box.add_child(_btn_options)

func _on_start_pressed() -> void:
	if is_instance_valid(_menu_box):
		_menu_box.queue_free()
	_switch_to_game()

func _on_options_pressed() -> void:
	print("옵션 버튼 눌림")

# ================= 게임 화면 =================
func _switch_to_game() -> void:
	_state = STATE_GAME
	_clear_center_layer()

	var game_script = load(game_layer_script_path)
	if game_script == null:
		push_error("GameLayer.gd 를 찾을 수 없습니다.")
		return

	_game_layer = (game_script as Script).new()
	add_child(_game_layer)

	# 게임오버 후 finished 시그널을 받아 메인으로 복귀
	if _game_layer.has_signal("finished"):
		_game_layer.finished.connect(func():
			if is_instance_valid(_game_layer):
				_game_layer.queue_free()
			_switch_to_main()
		)

# ================= 유틸 =================
func _clear_center_layer() -> void:
	if is_instance_valid(_center_layer):
		for c in _center_layer.get_children():
			c.queue_free()

func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
