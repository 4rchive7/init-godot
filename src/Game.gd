# GameLayer.gd
# Godot 4.4 / GDScript
# StarField(배경) + ShardParticles(파편) + ObstacleController(장애물) + GameHUD(HUD) + PlayerController(플레이어)
# 타임 어택: 빨간 박스에 맞으면 HP 감소 + "잠시 전체 속도 슬로우"(time_scale) 적용
# - 슬로우는 실제 시간 기준으로 자동 복구(타이머 ignore_time_scale=true)

extends Control
signal finished  # 게임오버 후 3초 뒤 emit

@export_file("*.gd") var starfield_script_path: String = "res://src/StarField.gd"
@export_file("*.gd") var shard_particles_script_path: String = "res://src/ShardParticles.gd"
@export_file("*.gd") var obstacle_controller_script_path: String = "res://src/ObstacleController.gd"
@export_file("*.gd") var game_hud_script_path: String = "res://src/GameHUD.gd"
@export_file("*.gd") var player_controller_script_path: String = "res://src/PlayerController.gd"

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

# --- 히트 슬로우(타임 어택 연출) ---
@export var hit_slow_factor: float = 0.6      # 0.0~1.0 (작을수록 더 느리게)
@export var hit_slow_duration: float = 0.6     # 초 단위 (실시간 기준)

# 파편(ShardParticles)에 넘길 기본값
const _PARTICLE_COUNT_HIT: int = 3
const _PARTICLE_SIZE_HIT: Vector2 = Vector2(6, 6)
const _PARTICLE_LIFETIME_HIT: float = 0.45
const _PARTICLE_GRAVITY_HIT: float = 520.0

const _PARTICLE_COUNT_DEATH: int = 24
const _PARTICLE_SIZE_DEATH: Vector2 = Vector2(5, 5)
const _PARTICLE_LIFETIME_DEATH: float = 0.9
const _PARTICLE_GRAVITY_DEATH: float = 680.0

var _view_size: Vector2
var _ground_y: float = 420.0
var _obstacle_speed: float = 0.0
var _hp: int = 0
var _is_game_over: bool = false

var _starfield: Node
var _shards: Node
var _obstacle_ctrl: Node
var _hud: Node
var _player_ctrl: Node

var _ground: ColorRect
var _gameover_delay_timer: Timer

# 슬로우 관리
var _slow_timer: Timer
var _is_slowed: bool = false

func _ready() -> void:
	_set_full_rect(self)
	_hp = hp_max
	_obstacle_speed = obstacle_speed_start

	_view_size = get_viewport_rect().size
	_ground_y = max(160.0, _view_size.y * 0.75)

	# --- StarField 배경 ---
	var SF = load(starfield_script_path)
	if SF != null:
		_starfield = (SF as Script).new()
		add_child(_starfield)
		move_child(_starfield, 0)

	# --- ShardParticles(파편) ---
	var SP = load(shard_particles_script_path)
	if SP != null:
		_shards = (SP as Script).new()
		add_child(_shards)
		move_child(_shards, 1)
		if "set_ground_y" in _shards:
			_shards.set_ground_y(_ground_y)

	# --- 장애물 컨트롤러 ---
	var OC = load(obstacle_controller_script_path)
	if OC != null:
		_obstacle_ctrl = (OC as Script).new()
		if "obstacle_color" in _obstacle_ctrl:
			_obstacle_ctrl.obstacle_color = obstacle_color
		if "obstacle_size" in _obstacle_ctrl:
			_obstacle_ctrl.obstacle_size = obstacle_size
		add_child(_obstacle_ctrl)
		if "setup" in _obstacle_ctrl:
			_obstacle_ctrl.setup(_ground_y, _view_size.x, _obstacle_speed)
		move_child(_obstacle_ctrl, 2)

	# --- 지면 ---
	_ground = ColorRect.new()
	_ground.color = bg_color_ground
	_ground.position = Vector2(0, _ground_y)
	_ground.custom_minimum_size = Vector2(_view_size.x, 4)
	add_child(_ground)

	# --- 플레이어 컨트롤러 ---
	var PC = load(player_controller_script_path)
	if PC != null:
		_player_ctrl = (PC as Script).new()
		add_child(_player_ctrl)
		if "set_gravity" in _player_ctrl:
			_player_ctrl.set_gravity(gravity)
		if "set_jump_force" in _player_ctrl:
			_player_ctrl.set_jump_force(jump_force)
		if "setup" in _player_ctrl:
			_player_ctrl.setup(_ground_y, player_size, player_color, 220.0)
		move_child(_player_ctrl, 3)

	# --- HUD ---
	var GH = load(game_hud_script_path)
	if GH != null:
		_hud = (GH as Script).new()
		if "text_color" in _hud:
			_hud.text_color = text_color
		if "gameover_text_color" in _hud:
			_hud.gameover_text_color = gameover_text_color
		if "font_size_label" in _hud:
			_hud.font_size_label = font_size_label
		if "font_size_hint" in _hud:
			_hud.font_size_hint = font_size_hint
		if "font_size_gameover" in _hud:
			_hud.font_size_gameover = font_size_gameover
		add_child(_hud)
		move_child(_hud, 4)
		if "set_hp" in _hud:
			_hud.set_hp(_hp, hp_max)
		if "set_hint" in _hud:
			_hud.set_hint("스페이스바로 점프!")

	# --- 게임오버 타이머 ---
	_gameover_delay_timer = Timer.new()
	_gameover_delay_timer.one_shot = true
	_gameover_delay_timer.wait_time = gameover_wait
	_gameover_delay_timer.timeout.connect(_on_gameover_delay_done)
	add_child(_gameover_delay_timer)

	# --- 슬로우(실시간 복구) 타이머 ---
	_slow_timer = Timer.new()
	_slow_timer.one_shot = true
	_slow_timer.wait_time = hit_slow_duration
	_slow_timer.ignore_time_scale = true   # 전체 time_scale이 느려져도 지정된 실제 시간으로 복구
	_slow_timer.timeout.connect(_on_slowdown_over)
	add_child(_slow_timer)

	set_process(true)
	set_process_input(true)

func _process(delta: float) -> void:
	if _is_game_over:
		return

	# 플레이어/장애물 업데이트
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)
	if _obstacle_ctrl and "update_obstacle" in _obstacle_ctrl:
		_obstacle_ctrl.update_obstacle(delta, _view_size.x)

	_check_collision()

func _input(event: InputEvent) -> void:
	if _is_game_over:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if _player_ctrl and "jump" in _player_ctrl:
			_player_ctrl.jump()

# ----- 충돌/HP -----
func _check_collision() -> void:
	if _player_ctrl == null or _obstacle_ctrl == null:
		return
	var p_rect: Rect2 = Rect2()
	var o_rect: Rect2 = Rect2()
	if "get_player_rect" in _player_ctrl:
		p_rect = _player_ctrl.get_player_rect()
	if "get_obstacle_rect" in _obstacle_ctrl:
		o_rect = _obstacle_ctrl.get_obstacle_rect()
	if p_rect.intersects(o_rect):
		_on_hit_obstacle()

func _on_hit_obstacle() -> void:
	# 진행방향(왼쪽) 파편 3개
	if _obstacle_ctrl and "get_obstacle_center" in _obstacle_ctrl and _shards and "spawn_directional_shards" in _shards:
		var impact_center: Vector2 = _obstacle_ctrl.get_obstacle_center()
		_shards.spawn_directional_shards(
			impact_center,
			Vector2(-1, 0),
			_PARTICLE_COUNT_HIT,
			_PARTICLE_SIZE_HIT,
			_PARTICLE_LIFETIME_HIT,
			_PARTICLE_GRAVITY_HIT,
			obstacle_color,
			260.0,
			380.0,
			18.0
		)

	# 장애물 리셋
	if _obstacle_ctrl and "reset_position" in _obstacle_ctrl:
		_obstacle_ctrl.reset_position(_view_size.x)

	# HP/UI/속도 처리
	_hp -= 1
	if _hp < 0:
		_hp = 0
	if _hud and "set_hp" in _hud:
		_hud.set_hp(_hp, hp_max)
	if _hud and "tint_hp_hit" in _hud:
		_hud.tint_hp_hit()

	# 난이도 증가(기존)
	_obstacle_speed += obstacle_speed_hit_add
	if _obstacle_ctrl and "set_speed" in _obstacle_ctrl:
		_obstacle_ctrl.set_speed(_obstacle_speed)

	# --- 히트 슬로우 적용 ---
	_apply_hit_slowdown()

	if _hp <= 0:
		_trigger_game_over()
	else:
		var t = Timer.new()
		t.one_shot = true
		t.wait_time = 0.2
		t.timeout.connect(func() -> void:
			if _hud and "tint_hp_normal" in _hud:
				_hud.tint_hp_normal()
			t.queue_free()
		)
		add_child(t)
		t.start()

# ----- 히트 슬로우 -----
func _apply_hit_slowdown() -> void:
	if hit_slow_factor <= 0.0:
		hit_slow_factor = 0.1
	if hit_slow_factor > 1.0:
		hit_slow_factor = 1.0
	# 전체 트리 슬로우
	Engine.time_scale = hit_slow_factor
	_is_slowed = true
	# 남은 시간이 있어도 갱신해서 마지막 히트 시점 기준으로 유지
	_slow_timer.stop()
	_slow_timer.wait_time = hit_slow_duration
	_slow_timer.start()

func _on_slowdown_over() -> void:
	_reset_time_scale()

func _reset_time_scale() -> void:
	if _is_slowed:
		Engine.time_scale = 1.0
	_is_slowed = false

# ----- 게임오버 -----
func _trigger_game_over() -> void:
	_is_game_over = true
	_reset_time_scale()

	# 플레이어 폭발 파편(사방향)
	if _player_ctrl and _shards and "get_player_center" in _player_ctrl and "spawn_radial_shards" in _shards:
		var player_center: Vector2 = _player_ctrl.get_player_center()
		_shards.spawn_radial_shards(
			player_center,
			_PARTICLE_COUNT_DEATH,
			_PARTICLE_SIZE_DEATH,
			_PARTICLE_LIFETIME_DEATH,
			_PARTICLE_GRAVITY_DEATH,
			player_color,
			420.0,
			620.0
		)

	# 플레이어 제거
	if _player_ctrl:
		_player_ctrl.queue_free()

	# HUD 갱신
	if _hud and "show_game_over" in _hud:
		_hud.show_game_over()
	if _hud and "set_hint" in _hud:
		_hud.set_hint(str(int(gameover_wait)) + "초 뒤 메인으로...")

	_gameover_delay_timer.start()

func _on_gameover_delay_done() -> void:
	emit_signal("finished")

func _exit_tree() -> void:
	# 어떤 경로로든 씬을 벗어날 때 원복 보장
	_reset_time_scale()

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
