# Godot 4.4 / GDScript
# 로딩 UI를 화면 정중앙에 정확히 배치
extends Control
signal finished

@export var bg_color: Color = Color(0.08, 0.10, 0.12, 1.0)
@export var center_color: Color = Color(1, 0, 0, 0.25) # 중앙 영역 확인용(투명 빨강)
@export var total_ticks: int = 3

var _bg_rect: ColorRect
var _center: CenterContainer
var _center_bg: ColorRect
var _progress: ProgressBar
var _timer: Timer
var _tick: int = 0

func _ready() -> void:
	# 루트: 전체 화면 꽉 채우기
	_set_full_rect(self)

	# 배경(풀스크린)
	_bg_rect = ColorRect.new()
	_bg_rect.color = bg_color
	_set_full_rect(_bg_rect)
	add_child(_bg_rect)

	# 가운데 정렬용 컨테이너 (부모는 더 이상 컨테이너가 아님)
	_center = CenterContainer.new()
	_set_full_rect(_center)
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_center)

	# # 중앙 영역 확인용 반투명 레이어(원하면 끄세요)
	# # vbox의 시각적 중앙과 동일한 영역을 보기 원하면, vbox를 감싸는 래퍼를 쓰는 방식도 가능
	# _center_bg = ColorRect.new()
	# _center_bg.color = center_color
	# # CenterContainer는 자식을 '최소크기'로 취급하므로, 배경을 vbox와 같은 래퍼에 붙이는게 가장 정확함.
	# # 간단화를 위해 여기서는 vbox 뒤에 같은 노드로 두되, 최소크기를 지정합니다.
	# _center_bg.custom_minimum_size = Vector2(400, 120)
	# _center.add_child(_center_bg)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(400, 120) # 중앙 표시 영역과 동일 크기
	_center.add_child(vbox)

	var label = Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(360, 24)
	vbox.add_child(_progress)

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()

func _on_tick() -> void:
	_tick += 1
	_progress.value = float(_tick) / float(total_ticks) * 100.0
	if _tick >= total_ticks:
		_timer.stop()
		emit_signal("finished")

# ---- 유틸: 주어진 Control을 FULL_RECT로 고정 ----
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
