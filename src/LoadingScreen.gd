# LoadingScreen.gd
# Godot 4.4 / GDScript
# 3초 동안 1초마다 프로그레스가 차오르고 완료되면 finished 신호를 내보냅니다.
# 빈 Control 노드에 붙여도 되고, 다른 씬에서 인스턴스해 사용해도 됩니다.

extends Control

signal finished

@export var title_text: String = "MY GAME"
@export var loading_text: String = "Loading..."
@export var bg_color: Color = Color(0.08, 0.10, 0.12, 1.0)
@export var text_color: Color = Color.WHITE
@export var font_size_title: int = 56
@export var font_size_label: int = 20
@export var total_ticks: int = 3  # 3초

var _bg_rect: ColorRect
var _center: CenterContainer
var _box: VBoxContainer
var _label_loading: Label
var _progress: ProgressBar
var _timer: Timer
var _tick: int = 0

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
	_bg_rect.anchor_left = 0
	_bg_rect.anchor_top = 0
	_bg_rect.anchor_right = 1
	_bg_rect.anchor_bottom = 1
	add_child(_bg_rect)

	# 중앙 컨테이너
	_center = CenterContainer.new()
	_center.anchor_left = 0
	_center.anchor_top = 0
	_center.anchor_right = 1
	_center.anchor_bottom = 1
	add_child(_center)

	# UI 박스
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 18)
	_center.add_child(_box)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", text_color)
	title.add_theme_font_size_override("font_size", font_size_title)
	_box.add_child(title)

	_label_loading = Label.new()
	_label_loading.text = loading_text
	_label_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_loading.add_theme_color_override("font_color", text_color)
	_label_loading.add_theme_font_size_override("font_size", font_size_label)
	_box.add_child(_label_loading)

	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 0
	_progress.custom_minimum_size = Vector2(360, 24)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(_progress)

	# 타이머
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()

func _on_tick() -> void:
	_tick += 1
	var pct_step: float = 100.0 / float(max(1, total_ticks))
	var new_pct: float = _progress.value + pct_step
	if new_pct > 100.0:
		new_pct = 100.0
	_progress.value = new_pct
	_label_loading.text = loading_text + " " + str(int(_progress.value)) + "%"

	if _tick >= total_ticks:
		_timer.stop()
		_progress.value = 100.0
		emit_signal("finished")
