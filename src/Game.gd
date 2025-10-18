# GameLayer.gd
# Godot 4.4 / GDScript
# ▶ 중앙 레일(가운데 라인)에 "에셋(텍스처)"을 코드로 배치할 수 있게 추가
#    - 에셋은 장식용으로만 사용(충돌 없음)
#    - 장애물과 같은 속도로 왼쪽으로 흘러가며, 화면 밖으로 나가면 자동 제거
#    - 간격(px), 스케일, Y오프셋 조절 가능
#    - 원근 스케일(가운데 라인은 1.0)과 무관하게 center_asset_scale만 적용
# ▶ 기존 기능 유지: 3개 라인/점프/충돌(플레이어 라인만)/난이도 가속/히트 시 속도 최저치로 리셋 등

extends Control
signal finished

@export_file("*.gd") var starfield_script_path: String = "res://src/StarField.gd"
@export_file("*.gd") var shard_particles_script_path: String = "res://src/ShardParticles.gd"
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

@export var lane_gap: float = 10.0

# 장애물(내부 관리)
@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_speed_start: float = 260.0         # 최저/시작 속도
@export var obstacle_accel_per_sec: float = 10.0        # 초당 자연 가속(난이도 상승)

# 스폰 간격/개수
@export var min_column_gap_px: float = 380.0
@export var min_column_gap_time: float = 0.90
@export var max_columns_on_screen: int = 3

# ▶ 중앙 레일 에셋(장식) 설정
@export var center_asset_path: String = "res://assets/lane.png"  # 비우면 스폰 안 함
@export var center_asset_scale: float = 1.0         # 가운데 라인의 기본 원근은 1.0, 여기에 추가 스케일
@export var center_asset_gap_px: float = 480.0      # 에셋 간 최소 수평 간격(px)
@export var center_asset_y_offset: float = 0.0      # 라인 위에서의 y 오프셋(+아래, -위)
@export var center_asset_zindex: int = 50           # 플레이어(4096)보다 아래로 보이게

@export var hp_max: int = 3
@export var gameover_wait: float = 3.0

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
var _base_obstacle_speed: float = 0.0
var _hp: int = 0
var _is_game_over: bool = false

# 노드
var _starfield: Node
var _shards: Node
var _hud: Node
var _player_ctrl: Node
var _ground: ColorRect

# 라인/스케일
var _lanes_y: Array = []                  # [top, center, bottom]
var _lane_scales: Array = [0.9, 1.0, 1.1] # 원근 스케일

# 장애물 컬럼: { "rects":[ColorRect], "x":float }
var _columns: Array = []
var _last_spawn_time: float = -9999.0

# ▶ 중앙 레일 에셋 관리
var _center_asset_tex: Texture2D
var _center_props: Array = []             # Sprite2D 배열
var _last_center_spawn_x: float = -1e9

# 타이머
var _gameover_delay_timer: Timer

# RNG
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_set_full_rect(self)
	_rng.randomize()

	_hp = hp_max
	_base_obstacle_speed = obstacle_speed_start

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

	# Ground guide
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
		if "text_color" in _hud: _hud.text_color = text_color
		if "gameover_text_color" in _hud: _hud.gameover_text_color = gameover_text_color
		if "font_size_label" in _hud: _hud.font_size_label = font_size_label
		if "font_size_hint" in _hud: _hud.font_size_hint = font_size_hint
		if "font_size_gameover" in _hud: _hud.font_size_gameover = font_size_gameover
		add_child(_hud)
		move_child(_hud, 4)
		if "set_hp" in _hud: _hud.set_hp(_hp, hp_max)
		if "set_hint" in _hud: _hud.set_hint("↑/↓ 라인 변경, Space 점프")

	# Lanes + Player settings
	_make_lanes()
	if _player_ctrl:
		if "set_lanes" in _player_ctrl:
			_player_ctrl.set_lanes(_lanes_y, 1)
		if "set_lane_scales" in _player_ctrl:
			_player_ctrl.set_lane_scales(_lane_scales)

	# ▶ 중앙 레일 에셋 텍스처 로드(있으면)
	_center_asset_tex = null
	if center_asset_path.strip_edges() != "":
		var res = load(center_asset_path)
		if res is Texture2D:
			_center_asset_tex = res

	# Timers
	_gameover_delay_timer = Timer.new()
	_gameover_delay_timer.one_shot = true
	_gameover_delay_timer.wait_time = gameover_wait
	_gameover_delay_timer.timeout.connect(_on_gameover_delay_done)
	add_child(_gameover_delay_timer)

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
	_lanes_y.append(top_y)
	_lanes_y.append(center_y)
	_lanes_y.append(bottom_y)

func _process(delta: float) -> void:
	if _is_game_over:
		return

	# 자연 가속으로 난이도 점진 상승
	_base_obstacle_speed += obstacle_accel_per_sec * delta

	# Player
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)

	# 장애물 업데이트
	_move_and_cleanup_columns(delta)
	_try_spawn_column()

	# ▶ 중앙 레일 에셋 업데이트
	_move_and_cleanup_center_props(delta)
	_try_spawn_center_prop()

	# 충돌
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

# ───────────── 장애물(내부) ─────────────

func _current_obstacle_speed() -> float:
	return _base_obstacle_speed

func _move_and_cleanup_columns(delta: float) -> void:
	var speed = _current_obstacle_speed()
	var i: int = _columns.size() - 1
	while i >= 0:
		var col = _columns[i]
		var rects: Array = col["rects"]
		var j: int = rects.size() - 1
		while j >= 0:
			var r: ColorRect = rects[j]
			if is_instance_valid(r):
				r.position.x -= speed * delta
				if r.position.x + (obstacle_size.x * r.scale.x) < -8.0:
					r.queue_free()
					rects.remove_at(j)
			else:
				rects.remove_at(j)
			j -= 1
		col["rects"] = rects
		_columns[i] = col
		if rects.size() == 0:
			_columns.remove_at(i)
		i -= 1

func _try_spawn_column() -> void:
	if _columns.size() >= max_columns_on_screen:
		return

	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_spawn_time < min_column_gap_time:
		return

	var rightmost_x: float = -1e9
	for c in _columns:
		if c["rects"].size() > 0:
			var r0: ColorRect = c["rects"][0]
			if is_instance_valid(r0):
				rightmost_x = max(rightmost_x, r0.position.x)
	if rightmost_x > -1e8:
		var spawn_edge = _view_size.x + 80.0
		if spawn_edge - rightmost_x < min_column_gap_px:
			return

	# 패턴(세 줄 동시 포함)
	var patterns = [
		[true, false, false],
		[false, true, false],
		[false, false, true],
		[true, true, false],
		[true, false, true],
		[false, true, true],
		[true, true, true],
	]
	var pat = patterns[_rng.randi_range(0, patterns.size() - 1)]

	var spawn_x: float = _view_size.x + 80.0
	var rects: Array = []
	var i: int = 0
	while i < 3:
		if pat[i]:
			var r = ColorRect.new()
			r.color = obstacle_color
			r.custom_minimum_size = obstacle_size
			r.position = Vector2(spawn_x, float(_lanes_y[i]))
			# 라인 스케일 적용
			var s: float = _lane_scales[i]
			r.scale = Vector2(s, s)
			add_child(r)
			rects.append(r)
		i += 1

	if rects.size() > 0:
		_columns.append({ "rects": rects, "x": spawn_x })
		_last_spawn_time = now

# ───────────── 중앙 레일 에셋(장식) ─────────────

func _move_and_cleanup_center_props(delta: float) -> void:
	if _center_props.size() == 0:
		return
	var speed = _current_obstacle_speed()
	var i: int = _center_props.size() - 1
	while i >= 0:
		var s: Sprite2D = _center_props[i]
		if is_instance_valid(s):
			s.position.x -= speed * delta
			if s.position.x + s.get_rect().size.x * s.scale.x < -8.0:
				s.queue_free()
				_center_props.remove_at(i)
		else:
			_center_props.remove_at(i)
		i -= 1

func _try_spawn_center_prop() -> void:
	if _center_asset_tex == null:
		return

	# 오른쪽에 있는 가장 마지막 에셋의 x(없으면 스폰)
	var rightmost_x: float = -1e9
	for s in _center_props:
		if is_instance_valid(s):
			rightmost_x = max(rightmost_x, s.position.x)
	var spawn_edge: float = _view_size.x + 80.0
	if rightmost_x > -1e8 and (spawn_edge - rightmost_x) < center_asset_gap_px:
		return

	_spawn_center_prop(spawn_edge)

func _spawn_center_prop(spawn_x: float) -> void:
	# 가운데 라인의 y
	if _lanes_y.size() < 2:
		return
	var y: float = float(_lanes_y[1]) + center_asset_y_offset

	var sp := Sprite2D.new()
	sp.texture = _center_asset_tex
	sp.centered = false
	sp.position = Vector2(spawn_x, y)
	sp.scale = Vector2(center_asset_scale, center_asset_scale)
	sp.z_as_relative = false
	sp.z_index = center_asset_zindex
	add_child(sp)
	_center_props.append(sp)

# ───────────── 충돌: 플레이어 라인의 장애물만(스케일 반영) ─────────────
func _check_collision() -> void:
	if _player_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()

	var i: int = 0
	while i < _columns.size():
		var rects: Array = _columns[i]["rects"]
		var j: int = 0
		while j < rects.size():
			var r: ColorRect = rects[j]
			if is_instance_valid(r) and _lane_of_rect(r) == p_lane:
				var o_size: Vector2 = obstacle_size * r.scale.x
				var o_rect = Rect2(r.position, o_size)
				if p_rect.intersects(o_rect):
					_on_hit_obstacle(r, i, j)
					return
			j += 1
		i += 1

func _lane_of_rect(r: ColorRect) -> int:
	var best_i = 0
	var best_d = 1e9
	var i: int = 0
	while i < _lanes_y.size():
		var d = abs(r.position.y - float(_lanes_y[i]))
		if d < best_d:
			best_d = d
			best_i = i
		i += 1
	return best_i

func _on_hit_obstacle(r: ColorRect, col_index: int, rect_index: int) -> void:
	# 파편
	if _shards and "spawn_directional_shards" in _shards:
		var center = r.position + (obstacle_size * r.scale.x) * 0.5
		_shards.spawn_directional_shards(
			center, Vector2(-1, 0),
			_PARTICLE_COUNT_HIT, _PARTICLE_SIZE_HIT, _PARTICLE_LIFETIME_HIT, _PARTICLE_GRAVITY_HIT,
			obstacle_color, 260.0, 380.0, 18.0
		)

	# 해당 장애물 제거
	if is_instance_valid(r):
		r.queue_free()
	var col = _columns[col_index]
	col["rects"].remove_at(rect_index)
	_columns[col_index] = col
	if col["rects"].size() == 0:
		_columns.remove_at(col_index)

	# HP/UI
	_hp -= 1
	if _hp < 0: _hp = 0
	if _hud and "set_hp" in _hud: _hud.set_hp(_hp, hp_max)
	if _hud and "tint_hp_hit" in _hud: _hud.tint_hp_hit()

	# 충돌 시 속도 최저치로 리셋
	_base_obstacle_speed = obstacle_speed_start

	if _hp <= 0:
		_trigger_game_over()
	else:
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 0.2
		t.timeout.connect(func() -> void:
			if _hud and "tint_hp_normal" in _hud:
				_hud.tint_hp_normal()
			t.queue_free()
		)
		add_child(t)
		t.start()

# ───────────── 게임오버 ─────────────
func _trigger_game_over() -> void:
	_is_game_over = true

	# 사망 파편
	if _player_ctrl and "get_player_center" in _player_ctrl and _shards and "spawn_radial_shards" in _shards:
		var pc = _player_ctrl.get_player_center()
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

# ───────────── 유틸 ─────────────
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
