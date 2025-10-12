# AppRoot.gd
# Godot 4.4 / GDScript
# 1) 3초 로딩 → 2) 메인(시작/옵션) → 3) 점프해서 장애물 피하기
#    - 스페이스로 점프
#    - 오른쪽→왼쪽으로 이동하는 타겟(장애물)
#    - 피하지 못하면 HP 감소, 0이 되면 "GAME OVER" 표시 후 3초 뒤 메인으로 복귀

extends Control

# ---------- 공통 설정 ----------
@export var bg_color: Color = Color(0.08, 0.10, 0.12, 1.0)
@export var text_color: Color = Color.WHITE
@export var title_text: String = "MY GAME"
@export var font_size_title: int = 56
@export var font_size_button: int = 28
@export var font_size_label: int = 20

# ---------- 상태 ----------
const STATE_LOADING := 0
const STATE_MAIN := 1
const STATE_GAME := 2

var _state: int = STATE_LOADING

# ---------- 로딩 ----------
var _timer: Timer
var _tick: int = 0
var _ticks_target: int = 3
var _bg_rect: ColorRect
var _center: CenterContainer
var _loading_box: VBoxContainer
var _loading_label: Label
var _progress: ProgressBar

# ---------- 메인 ----------
var _menu_box: VBoxContainer
var _btn_start: Button
var _btn_options: Button

# ---------- 게임 ----------
var _game_layer: Control
var _ground: ColorRect
var _player: ColorRect
var _obstacle: ColorRect
var _hp_label: Label
var _hint_label: Label
var _game_over_label: Label

var _ground_y: float = 420.0
var _gravity: float = 900.0
var _jump_force: float = -500.0
var _player_size: Vector2 = Vector2(44, 44)
var _player_vel_y: float = 0.0
var _is_jumping: bool = false

var _obstacle_size: Vector2 = Vector2(36, 36)
var _obstacle_speed: float = 260.0

var _hp_max: int = 3
var _hp: int = 3
var _is_game_over: bool = false
var _gameover_delay_timer: Timer

# ==========================
# 초기화
# ==========================
func _ready() -> void:
	anchor_left = 0
	anchor_top = 0
	anchor_right = 1
	anchor_bottom = 1
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0

	_build_background()
	_build_loading_ui()
	_build_timer()

# ---------------- 로딩 ----------------
func _build_background() -> void:
	_bg_rect = ColorRect.new()
	_bg_rect.color = bg_color
	_bg_rect.anchor_left = 0
	_bg_rect.anchor_top = 0
	_bg_rect.anchor_right = 1
	_bg_rect.anchor_bottom = 1
	add_child(_bg_rect)

	_center = CenterContainer.new()
	_center.anchor_left = 0
	_center.anchor_top = 0
	_center.anchor_right = 1
	_center.anchor_bottom = 1
	add_child(_center)

func _build_loading_ui() -> void:
	_loading_box = VBoxContainer.new()
	_loading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_box.add_theme_constant_override("separation", 18)
	_center.add_child(_loading_box)

	var title: Label = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", text_color)
	title.add_theme_font_size_override("font_size", font_size_title)
	_loading_box.add_child(title)

	_loading_label = Label.new()
	_loading_label.text = "Loading..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override("font_color", text_color)
	_loading_label.add_theme_font_size_override("font_size", font_size_label)
	_loading_box.add_child(_loading_label)

	_progress = ProgressBar.new()
	_progress.max_value = 100
	_progress.value = 0
	_progress.custom_minimum_size = Vector2(360, 24)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_box.add_child(_progress)

func _build_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()

func _on_tick() -> void:
	if _state != STATE_LOADING:
		return
	_tick += 1
	var pct: float = float(_tick) / float(_ticks_target) * 100.0
	if pct > 100.0:
		pct = 100.0
	_progress.value = pct
	_loading_label.text = "Loading... %d%%" % int(pct)
	if _tick >= _ticks_target:
		_timer.stop()
		_switch_to_main()

# ---------------- 메인 ----------------
func _switch_to_main() -> void:
	_state = STATE_MAIN

	# 남아있는 게임 레이어 정리
	if is_instance_valid(_game_layer):
		_game_layer.queue_free()

	if is_instance_valid(_loading_box):
		_loading_box.queue_free()

	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 16)
	_center.add_child(_menu_box)

	var title: Label = Label.new()
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

	_btn_start.grab_focus()

func _on_start_pressed() -> void:
	if is_instance_valid(_menu_box):
		_menu_box.queue_free()
	_switch_to_game()

func _on_options_pressed() -> void:
	print("옵션 버튼 눌림")

# ---------------- 게임 ----------------
func _switch_to_game() -> void:
	_state = STATE_GAME
	set_process(true)
	set_process_input(true)

	_is_game_over = false
	_hp = _hp_max
	_player_vel_y = 0.0
	_is_jumping = false

	_game_layer = Control.new()
	_game_layer.anchor_left = 0
	_game_layer.anchor_top = 0
	_game_layer.anchor_right = 1
	_game_layer.anchor_bottom = 1
	add_child(_game_layer)

	# 뷰포트 크기
	var view_size: Vector2 = get_viewport_rect().size
	_ground_y = max(160.0, view_size.y * 0.75)

	# 바닥
	_ground = ColorRect.new()
	_ground.color = Color(0.15, 0.15, 0.18)
	_ground.position = Vector2(0, _ground_y)
	_ground.custom_minimum_size = Vector2(view_size.x, 4)
	_game_layer.add_child(_ground)

	# 플레이어
	_player = ColorRect.new()
	_player.color = Color(0.3, 0.8, 1.0)
	_player.custom_minimum_size = _player_size
	_player.position = Vector2(220.0, _ground_y - _player_size.y)
	_game_layer.add_child(_player)

	# 장애물(타겟)
	_obstacle = ColorRect.new()
	_obstacle.color = Color(1.0, 0.35, 0.35)
	_obstacle.custom_minimum_size = _obstacle_size
	_reset_obstacle_position()
	_game_layer.add_child(_obstacle)

	# HP / 안내
	_hp_label = Label.new()
	_hp_label.text = "HP: %d / %d" % [_hp, _hp_max]
	_hp_label.add_theme_color_override("font_color", text_color)
	_hp_label.add_theme_font_size_override("font_size", font_size_label)
	_hp_label.position = Vector2(12, 12)
	_game_layer.add_child(_hp_label)

	_hint_label = Label.new()
	_hint_label.text = "스페이스바로 점프!"
	_hint_label.add_theme_color_override("font_color", text_color)
	_hint_label.add_theme_font_size_override("font_size", 24)
	_hint_label.position = Vector2(12, 44)
	_game_layer.add_child(_hint_label)

	# GAME OVER 라벨 (처음엔 숨김)
	_game_over_label = Label.new()
	_game_over_label.text = "GAME OVER"
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	_game_over_label.add_theme_font_size_override("font_size", 64)
	# 화면 중앙에 보이도록 CenterContainer 쓰지 않고 대략적 중앙 위치
	_game_over_label.position = Vector2(view_size.x * 0.5 - 220, view_size.y * 0.35)
	_game_over_label.visible = false
	_game_layer.add_child(_game_over_label)

	# 게임오버 대기 타이머
	_gameover_delay_timer = Timer.new()
	_gameover_delay_timer.one_shot = true
	_gameover_delay_timer.wait_time = 3.0
	_gameover_delay_timer.timeout.connect(_return_to_main_after_game_over)
	_game_layer.add_child(_gameover_delay_timer)

func _process(delta: float) -> void:
	if _state != STATE_GAME:
		return

	if not _is_game_over:
		_update_player(delta)
		_update_obstacle(delta)
		_check_collision()

func _input(event: InputEvent) -> void:
	if _state != STATE_GAME or _is_game_over:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_jump()

# ----- 플레이어 로직 -----
func _jump() -> void:
	if not _is_jumping:
		_player_vel_y = _jump_force
		_is_jumping = true

func _update_player(delta: float) -> void:
	_player_vel_y += _gravity * delta
	_player.position.y += _player_vel_y * delta

	var floor_y: float = _ground_y - _player_size.y
	if _player.position.y >= floor_y:
		_player.position.y = floor_y
		_player_vel_y = 0.0
		_is_jumping = false

# ----- 장애물 로직 -----
func _update_obstacle(delta: float) -> void:
	_obstacle.position.x -= _obstacle_speed * delta

	# 화면 왼쪽 밖으로 나가면 재배치
	if _obstacle.position.x + _obstacle_size.x < -8.0:
		_reset_obstacle_position()

func _reset_obstacle_position() -> void:
	var view_w: float = get_viewport_rect().size.x
	_obstacle.position = Vector2(view_w + 80.0, _ground_y - _obstacle_size.y)

# ----- 충돌 & HP -----
func _check_collision() -> void:
	# 간단 AABB 충돌
	var p_rect: Rect2 = Rect2(_player.position, _player_size)
	var o_rect: Rect2 = Rect2(_obstacle.position, _obstacle_size)

	if p_rect.intersects(o_rect):
		_on_hit_obstacle()

func _on_hit_obstacle() -> void:
	# 동일 프레임에서 중복 감소 방지용: 충돌 시 즉시 장애물 재배치
	_reset_obstacle_position()

	_hp -= 1
	if _hp < 0:
		_hp = 0
	_hp_label.text = "HP: %d / %d" % [_hp, _hp_max]

	# 피격 피드백(라벨 번쩍)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))

	# 약간의 속도 증가로 난이도 상승
	_obstacle_speed += 10.0

	if _hp <= 0:
		_trigger_game_over()
	else:
		# 0.2초 뒤 라벨 색상 복원
		var t: Timer = Timer.new()
		t.one_shot = true
		t.wait_time = 0.2
		t.timeout.connect(func() -> void:
			if is_instance_valid(_hp_label):
				_hp_label.add_theme_color_override("font_color", text_color)
			t.queue_free()
		)
		_game_layer.add_child(t)
		t.start()

# ----- 게임오버 -----
func _trigger_game_over() -> void:
	_is_game_over = true
	_game_over_label.visible = true
	_hint_label.text = "3초 뒤 메인으로..."
	_gameover_delay_timer.start()

func _return_to_main_after_game_over() -> void:
	_switch_to_main()
