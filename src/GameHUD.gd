# GameHUD.gd
# Godot 4.4 / GDScript
# HP/힌트/GAME OVER + 속도 + 거리/시간 진행 자동 갱신 + 게임오버 요약 패널
extends Control

@export var text_color: Color = Color.WHITE
@export var gameover_text_color: Color = Color(1, 0.4, 0.4)
@export var font_size_label: int = 20
@export var font_size_hint: int = 24
@export var font_size_gameover: int = 64

# ─ 표시 노드
var _hp_label: Label
var _hint_label: Label
var _game_over_label: Label
var _top_right_box: VBoxContainer
var _distance_label: Label
var _progress_label: Label

# ─ 속도 라벨 이름
const _SPEED_NODE_NAME = "SpeedLabel"

# ─ 내부 상태(환경/적분/타이머)
var _meters_per_pixel: float = 0.02
var _total_time_s: float = 0.0        # 0이면 총시간 미지정
var _elapsed_s: float = 0.0           # 표시 시간
var _distance_m: float = 0.0          # 누적 이동 거리
var _last_speed_pxps: float = 0.0     # 마지막 속도(px/s)

# ─ ‘표시 시간’ 기준 적분용 기준점
var _last_time_for_distance: float = 0.0

# ─ 게임오버 동결 플래그
var _is_frozen: bool = false

# ─ 게임오버 요약 패널
var _result_panel: PanelContainer
var _result_time_label: Label
var _result_dist_label: Label
var _result_title_label: Label

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

	# 우상단: 거리/시간
	_top_right_box = VBoxContainer.new()
	_top_right_box.name = "TopRightBox"
	_top_right_box.anchor_left = 1.0
	_top_right_box.anchor_right = 1.0
	_top_right_box.anchor_top = 0.0
	_top_right_box.anchor_bottom = 0.0
	_top_right_box.offset_left = -240
	_top_right_box.offset_right = -12
	_top_right_box.offset_top = 12
	_top_right_box.offset_bottom = 120
	add_child(_top_right_box)

	_distance_label = Label.new()
	_distance_label.text = "Dist: 0 m"
	_distance_label.add_theme_color_override("font_color", text_color)
	_distance_label.add_theme_font_size_override("font_size", font_size_label)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_distance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_right_box.add_child(_distance_label)

	_progress_label = Label.new()
	_progress_label.text = "Time 0.0s"
	_progress_label.add_theme_color_override("font_color", text_color)
	_progress_label.add_theme_font_size_override("font_size", font_size_label)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_right_box.add_child(_progress_label)

	# 센터: 게임오버 요약 패널 (초기 숨김)
	_create_result_panel()

	set_process(true)


func _process(delta: float) -> void:
	if _is_frozen:
		return

	# 1) 표시 시간 증가
	_elapsed_s += delta
	_update_time_label()

	# 2) 표시 시간 기반 거리 적분
	var dt: float = _elapsed_s - _last_time_for_distance
	if dt > 0.0:
		_distance_m += max(_last_speed_pxps, 0.0) * dt * max(_meters_per_pixel, 0.0)
		_last_time_for_distance = _elapsed_s
		_update_distance_label()


# ── API ──
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

# ▷ 게임오버 시: 중앙 패널에 '그 시점'의 시간/거리 표시 + 동결
func show_game_over() -> void:
	if is_instance_valid(_game_over_label):
		_game_over_label.visible = true

	# 동결(이후 시간/거리 증가 중단)
	_is_frozen = true

	# 패널 텍스트 업데이트 후 표시
	if is_instance_valid(_result_time_label):
		var time_txt = _format_time_text()
		_result_time_label.text = time_txt
	if is_instance_valid(_result_dist_label):
		_result_dist_label.text = "Distance: " + _format_distance(_distance_m)

	if is_instance_valid(_result_panel):
		_result_panel.visible = true


# ─ 속도 표시 + 내부 상태 갱신(거리 적분용)
func set_speed(v_pxps: float) -> void:
	_last_speed_pxps = v_pxps
	if not has_node(_SPEED_NODE_NAME):
		var lbl = Label.new()
		lbl.name = _SPEED_NODE_NAME

		# 화면 아래 중앙 정렬
		lbl.anchor_left = 0.5
		lbl.anchor_right = 0.5
		lbl.anchor_top = 1.0
		lbl.anchor_bottom = 1.0

		# 기준점은 화면 하단 중앙, 살짝 위로 올림
		lbl.offset_left = -60
		lbl.offset_top = -40
		lbl.offset_right = 60
		lbl.offset_bottom = -10

		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		lbl.modulate = Color(0.8, 0.9, 1.0)
		lbl.add_theme_font_size_override("font_size", 24)
		add_child(lbl)

	get_node(_SPEED_NODE_NAME).text = "Speed: " + str(round(v_pxps * 0.1)) + " km/h"

# ─ 환경 설정(한 번만 세팅)
func set_distance_config(meters_per_pixel: float) -> void:
	_meters_per_pixel = max(meters_per_pixel, 0.0)

func set_total_time(total_seconds: float) -> void:
	_total_time_s = max(total_seconds, 0.0)
	_update_time_label()

# ─ 재시작/초기화용
func reset_stats() -> void:
	_elapsed_s = 0.0
	_last_time_for_distance = 0.0
	_distance_m = 0.0
	_is_frozen = false
	_update_time_label()
	_update_distance_label()
	if is_instance_valid(_result_panel):
		_result_panel.visible = false


# ── 내부 유틸 ──
func _update_time_label() -> void:
	if not is_instance_valid(_progress_label):
		return

	if _total_time_s <= 0.0:
		_progress_label.text = "Time %.1fs" % _elapsed_s
		return

	var ratio: float = clamp(_elapsed_s / _total_time_s, 0.0, 1.0)
	var pct: int = int(round(ratio * 100.0))
	_progress_label.text = "Time %.1fs / %.1fs (%d%%)" % [_elapsed_s, _total_time_s, pct]

func _update_distance_label() -> void:
	if is_instance_valid(_distance_label):
		_distance_label.text = "Dist: " + _format_distance(_distance_m)

func _format_time_text() -> String:
	# 총시간이 있으면 퍼센트 포함, 없으면 경과시간만
	if _total_time_s > 0.0:
		var ratio: float = clamp(_elapsed_s / _total_time_s, 0.0, 1.0)
		var pct: int = int(round(ratio * 100.0))
		return "Time: %.1fs / %.1fs (%d%%)" % [_elapsed_s, _total_time_s, pct]
	return "Time: %.1fs" % _elapsed_s

func _format_distance(meters: float) -> String:
	if meters >= 1000.0:
		return "%.1f km" % (meters / 1000.0)
	return "%d m" % int(round(meters))

func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0

func _create_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.name = "ResultPanel"

	# 화면 정가운데 고정 (360x160)
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -180
	_result_panel.offset_right = 180
	_result_panel.offset_top = -80
	_result_panel.offset_bottom = 80

	# 패널 안쪽 여백 컨테이너
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0
	vbox.anchor_right = 1
	vbox.anchor_top = 0
	vbox.anchor_bottom = 1
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_panel.add_child(vbox)

	_result_title_label = Label.new()
	_result_title_label.text = "RESULT"
	_result_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_result_title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_result_title_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	_result_time_label = Label.new()
	_result_time_label.text = "Time: 0.0s"
	_result_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_time_label.add_theme_color_override("font_color", text_color)
	_result_time_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_result_time_label)

	_result_dist_label = Label.new()
	_result_dist_label.text = "Distance: 0 m"
	_result_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_dist_label.add_theme_color_override("font_color", text_color)
	_result_dist_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_result_dist_label)

	_result_panel.visible = false
	add_child(_result_panel)
