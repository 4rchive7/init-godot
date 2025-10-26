# GameLayer.gd
# Godot 4.4 / GDScript
# SRP: "오케스트레이션"만 담당
#  - 배경, 스타필드, HUD, 플레이어, 장애물 컨트롤러 생성/연결
#  - 속도 싱크(StarField 속도, Decor 스크롤)
#  - 충돌 후 HP/HUD 업데이트, 속도 리셋, 파편, 게임오버
#  - Decor(레인 가이드/레인마다 장식)는 TrackDecor.gd에 100% 위임
#
# ⬇ z_index 레이어 재정의
#  Godot 4의 z_index는 너무 큰 음수/양수 쓰면 클램프돼서 정렬이 깨질 수 있음.
#  그래서 전체를 "0~300 사이"의 안정적인 값으로 재배치했다.
#
#  Z_BG(0)         : 배경 ColorRect
#  Z_STARS(10)     : StarField
#  Z_DECOR_BASE(20): 레인 데코/가이드(TrackDecor). 레인별로 20~40대 근처에서 내부 조정
#  Z_FG_BASE(100)  : 플레이어/장애물 본체 (lane마다 100,102,104...)
#  Shards(150)     : 충돌 파편
#  HUD(300)        : HUD / GameOver 텍스트 등 UI
#
# TrackDecor.setup()에 center_asset_zindex로 20(Z_DECOR_BASE)을 넘겨주도록 수정함.
# TrackDecor 쪽에서는 lane_idx, spawn 순서에 따라 20~40 근방의 z값을 부여하고,
# 가장 아래 레인이 제일 위에 깔리도록, 그리고 먼저 있던 오브젝트가 더 위로 오도록 한다.

extends Control
signal finished

@export_file("*.gd") var starfield_script_path: String = "res://src/StarField.gd"
@export_file("*.gd") var shard_particles_script_path: String = "res://src/ShardParticles.gd"
@export_file("*.gd") var game_hud_script_path: String = "res://src/GameHUD.gd"
@export_file("*.gd") var player_controller_script_path: String = "res://src/PlayerController.gd"
@export_file("*.gd") var obstacle_controller_script_path: String = "res://src/ObstacleController.gd"
@export_file("*.gd") var track_decor_script_path: String = "res://src/TrackDecor.gd"

@export var bg_color_space: Color = Color(0.02, 0.02, 0.05)
@export var player_color: Color = Color(0.3, 0.8, 1.0)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)
@export var text_color: Color = Color.WHITE
@export var gameover_text_color: Color = Color(1, 0.4, 0.4)
@export var font_size_label: int = 20
@export var font_size_hint: int = 24
@export var font_size_gameover: int = 64

@export var lane_gap: float = 50.0

# 장애물 파라미터(컨트롤러로 전달)
@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_speed_start: float = 260.0
@export var obstacle_accel_per_sec: float = 10.0

@export var obstacle_texture_path: String = "res://assets/car_red.png"
@export var obstacle_tex_scale: float = 0.5
@export var obstacle_tint: Color = Color(1,1,1,1)
@export var collision_inset_px: Vector2 = Vector2(0, 0)

@export var spawn_density_ramp_duration: float = 90.0
@export var min_gap_scale_at_max: float = 0.40
@export var global_spawn_rate_scale: float = 3.0

@export var lane_gap_time_min: float = 0.60
@export var lane_gap_time_max: float = 1.80
@export var lane_gap_time_mul_top: float = 1.00
@export var lane_gap_time_mul_mid: float = 1.00
@export var lane_gap_time_mul_bot: float = 1.00

@export var obstacle_speed_mul_min: float = 0.75
@export var obstacle_speed_mul_max: float = 1.35
@export var no_overtake_min_gap_px: float = 8.0
@export var no_overtake_safety: float = 0.98

# 레인 데코(TrackDecor에 전달할 값)
@export var center_asset_path: String = "res://assets/lane1.png"
@export var center_asset_scale: float = 0.26
@export var center_asset_gap_px: float = 240.0
@export var center_asset_y_offset: float = 23.0
@export var center_asset_zindex: int = -8000   # ← Z_DECOR_BASE와 맞춰서 양수 작은 값으로

# 레인 가이드 라인(TrackDecor로 전달)
@export var lane_guide_thickness: int = 2
@export var lane_guide_color: Color = Color(0.6, 0.6, 0.75, 0.65)

@export var hp_max: int = 3
@export var gameover_wait: float = 3.0

# ---------- Z Index Plan (Godot 4-safe 범위) ----------
const Z_BG: int = 0
const Z_STARS: int = 10
const Z_DECOR_BASE: int = 20      # (TrackDecor 내부에서 lane별/시간별로 20~40대 내에서 가변)
const Z_FG_BASE: int = 100        # 플레이어/장애물 기준
const Z_SHARDS: int = Z_FG_BASE + 50   # 150
const Z_HUD: int = Z_FG_BASE + 200     # 300

# 파편 프리셋(플레이어 사망용)
const _PARTICLE_COUNT_DEATH = 24
const _PARTICLE_SIZE_DEATH = Vector2(5, 5)
const _PARTICLE_LIFETIME_DEATH = 0.9
const _PARTICLE_GRAVITY_DEATH = 680.0

# 내부 상태
var _view_size: Vector2
var _ground_y: float = 420.0
var _hp: int = 0
var _is_game_over: bool = false
var _last_player_lane: int = -1

# 노드 참조
var _bg_space: ColorRect
var _starfield: Node
var _shards: Node
var _hud: Node
var _player_ctrl: Node
var _obstacles_ctrl: Node
var _decor: Node   # TrackDecor

# 레인 / 스케일
var _lanes_y: Array = []
var _lane_scales: Array = [0.9, 1.0, 1.1]

# 타이머
var _gameover_delay_timer: Timer


func _ready() -> void:
	_set_full_rect(self)

	_hp = hp_max
	_view_size = get_viewport_rect().size
	_ground_y = max(160.0, _view_size.y * 0.75)

	# ─ 배경 Space ColorRect
	_bg_space = ColorRect.new()
	_bg_space.color = bg_color_space
	_set_full_rect(_bg_space)
	_bg_space.z_as_relative = false
	_bg_space.z_index = Z_BG
	add_child(_bg_space)

	# ─ StarField
	if starfield_script_path.strip_edges() != "":
		var SF = load(starfield_script_path)
		if SF != null:
			_starfield = (SF as Script).new()
			if _starfield is CanvasItem:
				var ci_sf = _starfield as CanvasItem
				ci_sf.z_as_relative = false
				ci_sf.z_index = Z_STARS
			add_child(_starfield)

	# ─ ShardParticles
	if shard_particles_script_path.strip_edges() != "":
		var SP = load(shard_particles_script_path)
		if SP != null:
			_shards = (SP as Script).new()
			if _shards is CanvasItem:
				var ci_sh = _shards as CanvasItem
				ci_sh.z_as_relative = false
				ci_sh.z_index = Z_SHARDS
			add_child(_shards)
			if "set_ground_y" in _shards:
				_shards.set_ground_y(_ground_y)

	# ─ PlayerController
	if player_controller_script_path.strip_edges() != "":
		var PC = load(player_controller_script_path)
		if PC != null:
			_player_ctrl = (PC as Script).new()
			add_child(_player_ctrl)
			if "setup" in _player_ctrl:
				# setup(ground_y, size, color, move_speed)
				_player_ctrl.setup(_ground_y, Vector2(44, 44), player_color, 220.0)
			_apply_player_zindex()

	# ─ HUD
	if game_hud_script_path.strip_edges() != "":
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
			if _hud is CanvasItem:
				var ci_hud = _hud as CanvasItem
				ci_hud.z_as_relative = false
				ci_hud.z_index = Z_HUD
			add_child(_hud)
			if "set_hp" in _hud:
				_hud.set_hp(_hp, hp_max)
			if "set_hint" in _hud:
				_hud.set_hint("↑/↓ 레인 이동, Space 점프")

	# ─ 레인 계산
	_make_lanes()

	# ─ TrackDecor (레인 가이드 + 모든 레인 장식)
	if track_decor_script_path.strip_edges() != "":
		var TD = load(track_decor_script_path)
		if TD != null:
			_decor = (TD as Script).new()
			add_child(_decor)
			if "setup" in _decor:
				_decor.setup(
					_view_size,
					_lanes_y,
					lane_gap,
					lane_guide_thickness,
					lane_guide_color,
					center_asset_path,
					center_asset_scale,
					center_asset_gap_px,
					center_asset_y_offset,
					center_asset_zindex  # 이제 -10000 같은 큰 음수 대신 20 같은 작은 양수 전달
				)

	# ─ Player 레인 정보/스케일 정보 전달
	if _player_ctrl:
		if "set_lanes" in _player_ctrl:
			# set_lanes(lanes_y, start_lane_idx)
			_player_ctrl.set_lanes(_lanes_y, 1)
		if "set_lane_scales" in _player_ctrl:
			_player_ctrl.set_lane_scales(_lane_scales)
		_apply_player_zindex()

	# ─ ObstacleController
	if obstacle_controller_script_path.strip_edges() != "":
		var OC = load(obstacle_controller_script_path)
		if OC != null:
			_obstacles_ctrl = (OC as Script).new()
			add_child(_obstacles_ctrl)

			if "set_environment" in _obstacles_ctrl:
				# set_environment(view_size, lanes_y, lane_scales, base_zindex)
				# base_zindex에 Z_FG_BASE(100)을 넘겨서,
				# 장애물/플레이어가 100대 z_index에서 정렬되도록.
				_obstacles_ctrl.set_environment(_view_size, _lanes_y, _lane_scales, Z_FG_BASE)

			if "set_spawn_config" in _obstacles_ctrl:
				_obstacles_ctrl.set_spawn_config(
					lane_gap_time_min, lane_gap_time_max,
					lane_gap_time_mul_top, lane_gap_time_mul_mid, lane_gap_time_mul_bot,
					spawn_density_ramp_duration, min_gap_scale_at_max, global_spawn_rate_scale
				)

			if "set_speed_config" in _obstacles_ctrl:
				_obstacles_ctrl.set_speed_config(
					obstacle_speed_start, obstacle_accel_per_sec,
					obstacle_speed_mul_min, obstacle_speed_mul_max,
					no_overtake_min_gap_px, no_overtake_safety
				)

			if "set_visual_config" in _obstacles_ctrl:
				_obstacles_ctrl.set_visual_config(
					obstacle_size, obstacle_texture_path, obstacle_tex_scale, obstacle_tint, collision_inset_px
				)

			if "start" in _obstacles_ctrl:
				_obstacles_ctrl.start()

	# ─ 게임오버 타이머
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

	# 장애물 업데이트
	if _obstacles_ctrl and "update" in _obstacles_ctrl:
		_obstacles_ctrl.update(delta)

	# 현재 기본 속도
	var v: float = 0.0
	if _obstacles_ctrl and "get_base_speed" in _obstacles_ctrl:
		v = _obstacles_ctrl.get_base_speed()
		_set_starfield_speed(v)

	# 데코(레인 가이드/레일) 스크롤 업데이트
	if _decor and "update_decor" in _decor:
		_decor.update_decor(delta, v)

	# 플레이어 업데이트
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)
		_check_player_lane_and_update_z()

	# 충돌 체크
	_check_collision()


func _input(event: InputEvent) -> void:
	if _is_game_over:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(-1)
				_check_player_lane_and_update_z()
		elif event.keycode == KEY_DOWN:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(1)
				_check_player_lane_and_update_z()
		elif event.keycode == KEY_SPACE:
			if _player_ctrl and "jump" in _player_ctrl:
				_player_ctrl.jump()


# ── z-index 규칙: 장애물은 lane*2, 플레이어는 lane*2+1 ──
# Z_FG_BASE(100)을 기준으로 lane별로 2씩 증가시켜서
# lane_idx가 클수록(아래 레인일수록) z_index가 커진다 = 더 앞에 옴.
func _z_for_lane(lane_idx: int, is_player: bool) -> int:
	var base = Z_FG_BASE + lane_idx * 2
	if is_player:
		return base + 1
	return base


func _apply_player_zindex() -> void:
	if _player_ctrl is CanvasItem:
		var li: int = 1
		if "get_lane_index" in _player_ctrl:
			li = int(_player_ctrl.get_lane_index())
		var ci = _player_ctrl as CanvasItem
		ci.z_as_relative = false
		ci.z_index = _z_for_lane(li, true)
		_last_player_lane = li


func _check_player_lane_and_update_z() -> void:
	if _player_ctrl and "get_lane_index" in _player_ctrl:
		var li: int = int(_player_ctrl.get_lane_index())
		if li != _last_player_lane:
			_apply_player_zindex()


# ── 충돌 및 후처리 ──
func _check_collision() -> void:
	if _player_ctrl == null or _obstacles_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return
	if not ("get_collision_index" in _obstacles_ctrl):
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()

	var hit_idx: int = _obstacles_ctrl.get_collision_index(p_rect, p_lane)
	if hit_idx >= 0:
		var center = Vector2.ZERO
		if "consume_hit" in _obstacles_ctrl:
			center = _obstacles_ctrl.consume_hit(hit_idx)

		# 파편 튀기기 (측면)
		if _shards and "spawn_directional_shards" in _shards:
			_shards.spawn_directional_shards(
				center, Vector2(-1, 0),
				3, Vector2(6, 6), 0.45, 520.0,
				obstacle_color, 260.0, 380.0, 18.0
			)

		_hp -= 1
		if _hp < 0:
			_hp = 0

		if _hud and "set_hp" in _hud:
			_hud.set_hp(_hp, hp_max)
		if _hud and "tint_hp_hit" in _hud:
			_hud.tint_hp_hit()

		# 속도 리셋
		if "reset_speed_to_start" in _obstacles_ctrl:
			_obstacles_ctrl.reset_speed_to_start()
		if "get_base_speed" in _obstacles_ctrl:
			_set_starfield_speed(_obstacles_ctrl.get_base_speed())

		# 사망 판정
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


# ── 게임오버 처리 ──
func _trigger_game_over() -> void:
	_is_game_over = true
	_set_starfield_speed(0.0)

	# 플레이어 폭발 파편
	if _player_ctrl and "get_player_center" in _player_ctrl and _shards and "spawn_radial_shards" in _shards:
		var pc = _player_ctrl.get_player_center()
		_shards.spawn_radial_shards(
			pc,
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

	# HUD 게임오버 텍스트
	if _hud and "show_game_over" in _hud:
		_hud.show_game_over()
	if _hud and "set_hint" in _hud:
		_hud.set_hint(str(int(gameover_wait)) + "초 뒤 메인으로...")

	# 타이머 시작
	_gameover_delay_timer.start()


func _on_gameover_delay_done() -> void:
	emit_signal("finished")


# ── StarField 연동 ──
func _set_starfield_speed(v: float) -> void:
	if _starfield and "set_speed_px" in _starfield:
		_starfield.set_speed_px(v)


# ── 유틸 ──
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
