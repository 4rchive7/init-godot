# GameLayer.gd
# Godot 4.4 / GDScript
# SRP: "오케스트레이션"만 담당
#  - 배경, 스타필드, HUD, 플레이어, 장애물 컨트롤러 생성/연결
#  - 속도 싱크(StarField 속도, Decor 스크롤)
#  - 충돌 후 HP/HUD 업데이트, 속도 리셋/감속/가속, 파편, 게임오버
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
@export var center_asset_zindex: int = -8000

# 레인 가이드 라인(TrackDecor로 전달)
@export var lane_guide_thickness: int = 2
@export var lane_guide_color: Color = Color(0.6, 0.6, 0.75, 0.65)

@export var hp_max: int = 10
@export var gameover_wait: float = 3.0

# ---------- Z Index Plan ----------
const Z_BG: int = 0
const Z_STARS: int = 10
const Z_DECOR_BASE: int = 20
const Z_FG_BASE: int = 100
const Z_SHARDS: int = Z_FG_BASE + 50
const Z_HUD: int = Z_FG_BASE + 200

# 파편 프리셋(플레이어 사망용)
const _PARTICLE_COUNT_DEATH = 24
const _PARTICLE_SIZE_DEATH = Vector2(5, 5)
const _PARTICLE_LIFETIME_DEATH = 0.9
const _PARTICLE_GRAVITY_DEATH = 680.0

# 충돌 시 속도 유지 비율(= 0.7 이면 30% 감소)
const HIT_SPEED_KEEP_RATIO: float = 0.7

# ── Near-Miss(근접 스쳐지나감) 보너스 ──
@export var near_miss_margin_px: float = 100.0          # 이 거리 안에서 스치면 보너스
@export var near_miss_speed_boost_ratio: float = 1.15   # 15% 가속
@export var near_miss_cooldown: float = 0.6             # 반복 방지 쿨다운(초)

var _near_miss_armed: bool = false
var _near_miss_arm_deadline: float = 0.0
@export var near_miss_arm_window: float = 0.35 

# 변속(쉭!) 느낌 파티클(보라색) 프리셋
@export var boost_particle_color: Color = Color(0.75, 0.4, 1.0, 1.0)
const _PARTICLE_COUNT_SHIFT = 12
const _PARTICLE_SIZE_SHIFT = Vector2(3, 3)
const _PARTICLE_LIFETIME_SHIFT = 0.28
const _PARTICLE_GRAVITY_SHIFT = 140.0
const _PARTICLE_SPEED_MIN_SHIFT = 240.0
const _PARTICLE_SPEED_MAX_SHIFT = 440.0
const _PARTICLE_SPREAD_DEG_SHIFT = 22.0

# 내부 상태
var _view_size: Vector2
var _ground_y: float = 420.0
var _hp: int = 0
var _is_game_over: bool = false
var _last_player_lane: int = -1
var _near_miss_cd_left: float = 0.0

# 노드 참조
var _bg_space: ColorRect
var _starfield: Node
var _shards: Node
var _hud: Node
var _player_ctrl: Node
var _obstacles_ctrl: Node
var _decor: Node

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
					_view_size, _lanes_y, lane_gap,
					lane_guide_thickness, lane_guide_color,
					center_asset_path, center_asset_scale,
					center_asset_gap_px, center_asset_y_offset,
					center_asset_zindex
				)

	# ─ Player 레인 정보/스케일 정보 전달
	if _player_ctrl:
		if "set_lanes" in _player_ctrl:
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

	# Near-miss 쿨다운 감소
	if _near_miss_cd_left > 0.0:
		_near_miss_cd_left -= delta
		if _near_miss_cd_left < 0.0:
			_near_miss_cd_left = 0.0

	# 장애물 업데이트
	if _obstacles_ctrl and "update" in _obstacles_ctrl:
		_obstacles_ctrl.update(delta)

	# 현재 기본 속도
	var v: float = 0.0
	if _obstacles_ctrl and "get_base_speed" in _obstacles_ctrl:
		v = _obstacles_ctrl.get_base_speed()
		_set_starfield_speed(v)
		
	if _hud and "set_speed" in _hud:
		_hud.set_speed(v)



	# 데코 스크롤
	if _decor and "update_decor" in _decor:
		_decor.update_decor(delta, v)

	# 플레이어 업데이트
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)
		_check_player_lane_and_update_z()

	# ★ 니어미스 ‘장전’ 스캔: 회피 전, 근접 후보만 기록
	_arm_near_miss_if_close()

	# 충돌/근접 스침 체크
	_check_collision()

func _input(event: InputEvent) -> void:
	if _is_game_over:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(-1)
				_check_player_lane_and_update_z()
				_try_fire_near_miss_on_evade()
		elif event.keycode == KEY_DOWN:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(1)
				_check_player_lane_and_update_z()
				_try_fire_near_miss_on_evade()
		elif event.keycode == KEY_SPACE:
			if _player_ctrl and "jump" in _player_ctrl:
				_player_ctrl.jump()
				_try_fire_near_miss_on_evade()



# ── z-index 규칙: 장애물은 lane*2, 플레이어는 lane*2+1 ──
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


# ── 충돌 및 근접 스쳐지나감 처리 ──
func _check_collision() -> void:
	if _player_ctrl == null or _obstacles_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return
	if not ("get_collision_index" in _obstacles_ctrl):
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()

	# 1) 실제 충돌 체크
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

		# 속도: 30% 감소(현재 속도의 0.7배로)
		_apply_speed_ratio(HIT_SPEED_KEEP_RATIO)

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
		return

	# 2) 근접 스쳐지나감(near-miss) 체크: 실제 충돌은 아니지만 margin 안으로 접근 시
	# _try_near_miss_boost(p_rect, p_lane)


func _try_near_miss_boost(p_rect: Rect2, p_lane: int) -> void:
	if _near_miss_cd_left > 0.0:
		return
	if not ("get_collision_index" in _obstacles_ctrl):
		return

	# 플레이어 rect를 margin만큼 확장해 근접 판정
	var m: float = max(0.0, near_miss_margin_px)
	var expanded: Rect2 = Rect2(p_rect.position - Vector2(m, m), p_rect.size + Vector2(m * 2.0, m * 2.0))

	var near_idx: int = _obstacles_ctrl.get_collision_index(expanded, p_lane)
	if near_idx >= 0:
		# 실제 충돌은 아니었으므로 보너스 가속
		_apply_speed_ratio(near_miss_speed_boost_ratio)
		_near_miss_cd_left = near_miss_cooldown

		# ★ 여기 추가: 플레이어 뒤 파티클 분출
		if _player_ctrl and "play_boost_trail" in _player_ctrl:
			_player_ctrl.play_boost_trail(near_miss_speed_boost_ratio)

		# 연출(선택)
		if _hud and "tint_hp_normal" in _hud:
			_hud.tint_hp_normal()

		# ── 변속 느낌 보라색 파티클: 플레이어 "뒤쪽"으로 분사 ──
		if _shards and "spawn_directional_shards" in _shards:
			var emit_pos = expanded.get_center()
			if _player_ctrl and "get_player_center" in _player_ctrl:
				emit_pos = _player_ctrl.get_player_center() + Vector2(-8.0, 0.0)  # 살짝 뒤로

			# 방향은 좌측(-X)으로, 좁은 확산각으로 분사하여 '배기'처럼 보이게
			_shards.spawn_directional_shards(
				emit_pos,
				Vector2(-1, 0),                      # 뒤쪽(좌측)으로
				_PARTICLE_COUNT_SHIFT,
				_PARTICLE_SIZE_SHIFT,
				_PARTICLE_LIFETIME_SHIFT,
				_PARTICLE_GRAVITY_SHIFT,
				boost_particle_color,                 # 보라색
				_PARTICLE_SPEED_MIN_SHIFT,
				_PARTICLE_SPEED_MAX_SHIFT,
				_PARTICLE_SPREAD_DEG_SHIFT
			)

		# 연출(선택): HUD 톤 정상화로 가속 타이밍 가시화
		if _hud and "tint_hp_normal" in _hud:
			_hud.tint_hp_normal()


func _apply_speed_ratio(ratio: float) -> void:
	if not ("get_base_speed" in _obstacles_ctrl):
		return
	var cur_v = _obstacles_ctrl.get_base_speed()
	var new_v = cur_v * ratio

	# (선택) 정상 상한을 알아와서, '부스트 결과가 상한을 넘기는지'도 함께 체크
	var cap = 0.0
	if "get_normal_cap_pxps" in _obstacles_ctrl:
		cap = _obstacles_ctrl.get_normal_cap_pxps()

	# 먼저 속도 반영
	_obstacles_ctrl.set_base_speed(new_v)

	# 🔹 조건부 오버캡: ① 지금이 이미 정상 상한이었거나, ② 부스트 결과 상한을 넘어섰을 때만
	var need_overcap: bool = false
	if "is_at_normal_cap" in _obstacles_ctrl and _obstacles_ctrl.is_at_normal_cap():
		need_overcap = true
	elif cap > 0.0 and new_v > cap:
		need_overcap = true

	if need_overcap and "start_overcap" in _obstacles_ctrl:
		_obstacles_ctrl.start_overcap(1.2)   # 0.5초만 +10km/h 허용


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

func _arm_near_miss_if_close() -> void:
	if _player_ctrl == null or _obstacles_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return
	if not ("get_collision_index" in _obstacles_ctrl):
		return

	# 플레이어 기준 박스 확장으로 "근접"만 감지 (충돌은 아님)
	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()

	var m: float = max(0.0, near_miss_margin_px)
	var expanded: Rect2 = Rect2(p_rect.position - Vector2(m, m), p_rect.size + Vector2(m * 2.0, m * 2.0))

	var near_idx: int = _obstacles_ctrl.get_collision_index(expanded, p_lane)

	# 근접 상태면 ‘장전’하고 유효시간 창을 연다.
	if near_idx >= 0:
		_near_miss_armed = true
		_near_miss_arm_deadline = Time.get_ticks_msec() + int(near_miss_arm_window * 1000.0)
	else:
		# 너무 멀어지면 장전 해제(선택사항)
		if Time.get_ticks_msec() > _near_miss_arm_deadline:
			_near_miss_armed = false


func _try_fire_near_miss_on_evade() -> void:
	# 장전돼 있지 않으면 무시
	if not _near_miss_armed:
		return
	# 유효시간 창 확인
	if Time.get_ticks_msec() > _near_miss_arm_deadline:
		_near_miss_armed = false
		return
	# 실제 충돌 중이면 니어미스 발동 금지
	if _player_ctrl == null or _obstacles_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return
	if not ("get_collision_index" in _obstacles_ctrl):
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()
	var hit_now: int = _obstacles_ctrl.get_collision_index(p_rect, p_lane)
	if hit_now >= 0:
		_near_miss_armed = false
		return

	# ➜ 여기서 ‘니어미스 보상’ 실행 (기존 _try_near_miss_boost 에서 하던 것)
	_apply_speed_ratio(near_miss_speed_boost_ratio)
	_near_miss_cd_left = near_miss_cooldown

	# 플레이어 뒤 파티클
	if _player_ctrl and "play_boost_trail" in _player_ctrl:
		_player_ctrl.play_boost_trail(near_miss_speed_boost_ratio)

	# 1회 발동 후 해제
	_near_miss_armed = false
