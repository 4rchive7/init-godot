# GameLayer.gd
# Godot 4.4 / GDScript
# ─────────────────────────────────────────────────────────
# ✔ 라인별 장애물 '분리' 운용: 위/중앙/아래 각 1개 인스턴스
# ✔ 충돌은 항상 "플레이어가 점프 중이든 아니든, 자신의 라인 장애물"하고만 검사
# ─────────────────────────────────────────────────────────
extends Control
signal finished

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

# 라인 구성
@export var lane_gap: float = 120.0

# 장애물/속도
@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_speed_start: float = 260.0
@export var obstacle_speed_hit_add: float = 10.0

# HP/게임오버
@export var hp_max: int = 3
@export var gameover_wait: float = 3.0

# 히트 슬로우
@export var hit_slow_factor: float = 0.6
@export var hit_slow_duration: float = 0.6

# 파편 프리셋
const _PARTICLE_COUNT_HIT: int = 3
const _PARTICLE_SIZE_HIT: Vector2 = Vector2(6, 6)
const _PARTICLE_LIFETIME_HIT: float = 0.45
const _PARTICLE_GRAVITY_HIT: float = 520.0

const _PARTICLE_COUNT_DEATH: int = 24
const _PARTICLE_SIZE_DEATH: Vector2 = Vector2(5, 5)
const _PARTICLE_LIFETIME_DEATH: float = 0.9
const _PARTICLE_GRAVITY_DEATH: float = 680.0

# 내부 상태
var _view_size: Vector2
var _ground_y: float = 420.0
var _obstacle_speed: float = 0.0
var _hp: int = 0
var _is_game_over: bool = false

# 노드
var _starfield: Node
var _shards: Node
var _hud: Node
var _player_ctrl: Node
var _ground: ColorRect

# 라인 Y 들(플레이어/장애물 공용, position.y 값 = 각 라인의 상단)
var _lanes_y: Array = []   # [top, center, bottom]

# 라인별 장애물 인스턴스(0:위, 1:중앙, 2:아래)
var _obstacles: Array = []   # ObstacleController들

# 타이머/상태
var _gameover_delay_timer: Timer
var _slow_timer: Timer
var _is_slowed: bool = false

func _ready() -> void:
	_set_full_rect(self)
	_hp = hp_max
	_obstacle_speed = obstacle_speed_start

	_view_size = get_viewport_rect().size
	_ground_y = max(160.0, _view_size.y * 0.75)

	# StarField
	var SF = load(starfield_script_path)
	if SF != null:
		_starfield = (SF as Script).new()
		add_child(_starfield)
		move_child(_starfield, 0)

	# ShardParticles
	var SP = load(shard_particles_script_path)
	if SP != null:
		_shards = (SP as Script).new()
		add_child(_shards)
		move_child(_shards, 1)
		if "set_ground_y" in _shards:
			_shards.set_ground_y(_ground_y)

	# Ground(가이드)
	_ground = ColorRect.new()
	_ground.color = bg_color_ground
	_ground.position = Vector2(0, _ground_y)
	_ground.custom_minimum_size = Vector2(_view_size.x, 4)
	add_child(_ground)

	# Player
	var PC = load(player_controller_script_path)
	if PC != null:
		_player_ctrl = (PC as Script).new()
		add_child(_player_ctrl)
		if "setup" in _player_ctrl:
			_player_ctrl.setup(_ground_y, Vector2(44, 44), player_color, 220.0)
		move_child(_player_ctrl, 3)

	# HUD
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
			_hud.set_hint("↑/↓ 라인 변경, Space 점프")

	# 라인 계산
	_make_lanes()

	# 플레이어에 라인 전달(가운데부터 시작)
	if _player_ctrl and "set_lanes" in _player_ctrl:
		_player_ctrl.set_lanes(_lanes_y, 1)

	# ── 핵심: 라인별로 장애물 3개 생성(위/중앙/아래)
	_spawn_lane_obstacles()

	# 타이머
	_gameover_delay_timer = Timer.new()
	_gameover_delay_timer.one_shot = true
	_gameover_delay_timer.wait_time = gameover_wait
	_gameover_delay_timer.timeout.connect(_on_gameover_delay_done)
	add_child(_gameover_delay_timer)

	_slow_timer = Timer.new()
	_slow_timer.one_shot = true
	_slow_timer.wait_time = hit_slow_duration
	_slow_timer.ignore_time_scale = true
	_slow_timer.timeout.connect(_on_slowdown_over)
	add_child(_slow_timer)

	set_process(true)
	set_process_input(true)

func _make_lanes() -> void:
	_lanes_y.clear()
	var player_h: float = 44.0
	var center_y: float = _ground_y - player_h
	var top_y: float = center_y - lane_gap
	var bottom_y: float = center_y + lane_gap
	top_y = clamp(top_y, 32.0, _view_size.y - 48.0)
	bottom_y = clamp(bottom_y, 32.0, _view_size.y - 48.0)
	_lanes_y.append(top_y)      # 0: 위
	_lanes_y.append(center_y)   # 1: 가운데
	_lanes_y.append(bottom_y)   # 2: 아래

func _spawn_lane_obstacles() -> void:
	_obstacles.clear()
	var OC = load(obstacle_controller_script_path)
	var i: int = 0
	while i < 3:
		if OC != null:
			var ob = (OC as Script).new()
			# 공통 설정
			if "obstacle_color" in ob:
				ob.obstacle_color = obstacle_color
			if "obstacle_size" in ob:
				ob.obstacle_size = obstacle_size
			add_child(ob)
			# 라인 고정
			if "set_lanes_y" in ob:
				ob.set_lanes_y(_lanes_y)
			if "set_lane_index" in ob:
				ob.set_lane_index(i)  # 0/1/2 중 하나에 '고정'
			# 속도/위치 초기화
			if "setup" in ob:
				ob.setup(_ground_y, _view_size.x, _obstacle_speed)
			_obstacles.append(ob)
		i += 1

func _process(delta: float) -> void:
	if _is_game_over:
		return
	# 플레이어 업데이트
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)
	# 라인별 장애물 모두 업데이트
	var i: int = 0
	while i < _obstacles.size():
		var ob = _obstacles[i]
		if ob and "update_obstacle" in ob:
			ob.update_obstacle(delta, _view_size.x)
		i += 1
	# 라인별 충돌 검사
	_check_collision()

func _input(event: InputEvent) -> void:
	if _is_game_over:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(-1)
		elif event.keycode == KEY_DOWN:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(1)
		elif event.keycode == KEY_SPACE:
			if _player_ctrl and "jump" in _player_ctrl:
				_player_ctrl.jump()

# ───────────────── 충돌: "현재 플레이어 라인의 장애물"하고만 판정 ─────────────────
func _check_collision() -> void:
	if _player_ctrl == null:
		return
	if not "get_lane_index" in _player_ctrl:
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	if p_lane < 0 or p_lane >= _obstacles.size():
		return

	var ob = _obstacles[p_lane]
	if ob == null:
		return
	if not ("get_obstacle_rect" in ob and "get_obstacle_center" in ob):
		return

	if not "get_player_rect" in _player_ctrl:
		return

	var p_rect: Rect2 = _player_ctrl.get_player_rect()
	var o_rect: Rect2 = ob.get_obstacle_rect()
	if p_rect.intersects(o_rect):
		_on_hit_obstacle(ob)

func _on_hit_obstacle(ob) -> void:
	# 파편
	if ob and "get_obstacle_center" in ob and _shards and "spawn_directional_shards" in _shards:
		var impact_center: Vector2 = ob.get_obstacle_center()
		_shards.spawn_directional_shards(
			impact_center, Vector2(-1, 0),
			_PARTICLE_COUNT_HIT, _PARTICLE_SIZE_HIT, _PARTICLE_LIFETIME_HIT, _PARTICLE_GRAVITY_HIT,
			obstacle_color, 260.0, 380.0, 18.0
		)
	# 장애물 리셋(해당 라인 것만)
	if ob and "reset_position" in ob:
		ob.reset_position(_view_size.x)

	# HP/UI/속도
	_hp -= 1
	if _hp < 0:
		_hp = 0
	if _hud and "set_hp" in _hud:
		_hud.set_hp(_hp, hp_max)
	if _hud and "tint_hp_hit" in _hud:
		_hud.tint_hp_hit()

	_obstacle_speed += obstacle_speed_hit_add
	# 모든 라인 장애물에 동일 속도 적용(난이도 상승 공유)
	var i: int = 0
	while i < _obstacles.size():
		var o = _obstacles[i]
		if o and "set_speed" in o:
			o.set_speed(_obstacle_speed)
		i += 1

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

# ───────────────── 히트 슬로우 ─────────────────
func _apply_hit_slowdown() -> void:
	var f: float = hit_slow_factor
	if f <= 0.0:
		f = 0.1
	if f > 1.0:
		f = 1.0
	Engine.time_scale = f
	_is_slowed = true
	_slow_timer.stop()
	_slow_timer.wait_time = hit_slow_duration
	_slow_timer.start()

func _on_slowdown_over() -> void:
	_reset_time_scale()

func _reset_time_scale() -> void:
	if _is_slowed:
		Engine.time_scale = 1.0
	_is_slowed = false

# ───────────────── 게임오버 ─────────────────
func _trigger_game_over() -> void:
	_is_game_over = true
	_reset_time_scale()

	# 사망 파편
	if _player_ctrl and "get_player_center" in _player_ctrl and _shards and "spawn_radial_shards" in _shards:
		var pc: Vector2 = _player_ctrl.get_player_center()
		_shards.spawn_radial_shards(
			pc, _PARTICLE_COUNT_DEATH, _PARTICLE_SIZE_DEATH,
			_PARTICLE_LIFETIME_DEATH, _PARTICLE_GRAVITY_DEATH,
			player_color, 420.0, 620.0
		)
	if _player_ctrl:
		_player_ctrl.queue_free()

	if _hud and "show_game_over" in _hud:
		_hud.show_game_over()
	if _hud and "set_hint" in _hud:
		_hud.set_hint(str(int(gameover_wait)) + "초 뒤 메인으로...")

	_gameover_delay_timer.start()

func _on_gameover_delay_done() -> void:
	emit_signal("finished")

# ───────────────── 유틸 ─────────────────
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
