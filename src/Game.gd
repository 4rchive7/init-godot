# Godot 4.4 / GDScript
# 게임 플레이 전용 (AppRoot에서 호출)
extends Control
signal finished  # 게임오버 후 3초 뒤 emit

@export var bg_color_ground: Color = Color(0.15, 0.15, 0.18)
@export var player_color: Color = Color(0.3, 0.8, 1.0)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)
@export var text_color: Color = Color.WHITE
@export var gameover_text_color: Color = Color(1, 0.4, 0.4)
@export var font_size_label: int = 20
@export var font_size_hint: int = 24
@export var font_size_gameover: int = 64

@export var gravity: float = 900.0
@export var jump_force: float = -500.0
@export var player_size: Vector2 = Vector2(44, 44)
@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_speed_start: float = 260.0
@export var obstacle_speed_hit_add: float = 10.0
@export var hp_max: int = 3
@export var gameover_wait: float = 3.0

var _ground_y: float = 420.0
var _player_vel_y: float = 0.0
var _is_jumping: bool = false
var _obstacle_speed: float = 0.0
var _hp: int = 0
var _is_game_over: bool = false

var _ground: ColorRect
var _player: ColorRect
var _obstacle: ColorRect
var _hp_label: Label
var _hint_label: Label
var _game_over_label: Label
var _gameover_delay_timer: Timer

func _ready() -> void:
	_set_full_rect(self)
	_hp = hp_max
	_obstacle_speed = obstacle_speed_start

	var view_size: Vector2 = get_viewport_rect().size
	_ground_y = max(160.0, view_size.y * 0.75)

	# 바닥
	_ground = ColorRect.new()
	_ground.color = bg_color_ground
	_ground.position = Vector2(0, _ground_y)
	_ground.custom_minimum_size = Vector2(view_size.x, 4)
	add_child(_ground)

	# 플레이어
	_player = ColorRect.new()
	_player.color = player_color
	_player.custom_minimum_size = player_size
	_player.position = Vector2(220.0, _ground_y - player_size.y)
	add_child(_player)

	# 장애물
	_obstacle = ColorRect.new()
	_obstacle.color = obstacle_color
	_obstacle.custom_minimum_size = obstacle_size
	add_child(_obstacle)
	_reset_obstacle_position()

	# HP 라벨
	_hp_label = Label.new()
	_hp_label.text = "HP: %d / %d" % [_hp, hp_max]
	_hp_label.add_theme_color_override("font_color", text_color)
	_hp_label.add_theme_font_size_override("font_size", font_size_label)
	_hp_label.position = Vector2(12, 12)
	add_child(_hp_label)

	# 힌트
	_hint_label = Label.new()
	_hint_label.text = "스페이스바로 점프!"
	_hint_label.add_theme_color_override("font_color", text_color)
	_hint_label.add_theme_font_size_override("font_size", font_size_hint)
	_hint_label.position = Vector2(12, 44)
	add_child(_hint_label)

	# GAME OVER
	_game_over_label = Label.new()
	_game_over_label.text = "GAME OVER"
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.add_theme_color_override("font_color", gameover_text_color)
	_game_over_label.add_theme_font_size_override("font_size", font_size_gameover)
	_game_over_label.position = Vector2(view_size.x * 0.5 - 220, view_size.y * 0.35)
	_game_over_label.visible = false
	add_child(_game_over_label)

	# 타이머
	_gameover_delay_timer = Timer.new()
	_gameover_delay_timer.one_shot = true
	_gameover_delay_timer.wait_time = gameover_wait
	_gameover_delay_timer.timeout.connect(_on_gameover_delay_done)
	add_child(_gameover_delay_timer)

	set_process(true)
	set_process_input(true)

func _process(delta: float) -> void:
	if _is_game_over:
		return
	_update_player(delta)
	_update_obstacle(delta)
	_check_collision()

func _input(event: InputEvent) -> void:
	if _is_game_over:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_jump()

# ----- 플레이어 -----
func _jump() -> void:
	if not _is_jumping:
		_player_vel_y = jump_force
		_is_jumping = true

func _update_player(delta: float) -> void:
	_player_vel_y += gravity * delta
	_player.position.y += _player_vel_y * delta
	var floor_y: float = _ground_y - player_size.y
	if _player.position.y >= floor_y:
		_player.position.y = floor_y
		_player_vel_y = 0.0
		_is_jumping = false

# ----- 장애물 -----
func _update_obstacle(delta: float) -> void:
	_obstacle.position.x -= _obstacle_speed * delta
	if _obstacle.position.x + obstacle_size.x < -8.0:
		_reset_obstacle_position()

func _reset_obstacle_position() -> void:
	var view_w: float = get_viewport_rect().size.x
	_obstacle.position = Vector2(view_w + 80.0, _ground_y - obstacle_size.y)

# ----- 충돌/HP -----
func _check_collision() -> void:
	var p_rect = Rect2(_player.position, player_size)
	var o_rect = Rect2(_obstacle.position, obstacle_size)
	if p_rect.intersects(o_rect):
		_on_hit_obstacle()

func _on_hit_obstacle() -> void:
	_reset_obstacle_position()
	_hp -= 1
	if _hp < 0:
		_hp = 0
	_hp_label.text = "HP: %d / %d" % [_hp, hp_max]
	_hp_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_obstacle_speed += obstacle_speed_hit_add

	if _hp <= 0:
		_trigger_game_over()
	else:
		var t = Timer.new()
		t.one_shot = true
		t.wait_time = 0.2
		t.timeout.connect(func():
			if is_instance_valid(_hp_label):
				_hp_label.add_theme_color_override("font_color", text_color)
			t.queue_free()
		)
		add_child(t)
		t.start()

# ----- 게임오버 -----
func _trigger_game_over() -> void:
	_is_game_over = true
	_game_over_label.visible = true
	_hint_label.text = str(int(gameover_wait)) + "초 뒤 메인으로..."
	_gameover_delay_timer.start()

func _on_gameover_delay_done() -> void:
	emit_signal("finished")

# ----- 유틸 -----
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
