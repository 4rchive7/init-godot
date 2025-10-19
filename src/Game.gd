# GameLayer.gd
# Godot 4.4 / GDScript
# ▶ 변경점: Z-Index 체계 정리 (요구 순서)
#    검은 배경(Z_BG) → 별 파티클(Z_STARS) → 중앙 레인 에셋(Z_CENTER) → 장애물/플레이어(Z_FG_*)
#    - 전역으로는 플레이어와 장애물이 같은 "전경 레이어"에 있으되,
#      같은 라인에서는 플레이어가 항상 장애물 위에 보이도록 lane별 미세 z 정렬 적용
#    - 중앙 레인(_center_asset_res)보다 장애물이 아래로 깔리는 문제 해결
# ▶ 유지: 추월 방지, 레인·점프, 레인별 독립 스폰/무작위 속도, 시간 경과 밀도 증가 스케일,
#         히트 시 속도 리셋, 스타필드 동기화, 중앙 레일 장식

extends Control
signal finished

@export_file("*.gd") var starfield_script_path: String = "res://src/StarField.gd"
@export_file("*.gd") var shard_particles_script_path: String = "res://src/ShardParticles.gd"
@export_file("*.gd") var game_hud_script_path: String = "res://src/GameHUD.gd"
@export_file("*.gd") var player_controller_script_path: String = "res://src/PlayerController.gd"

@export var bg_color_space: Color = Color(0.02, 0.02, 0.05) # ★ 우주 배경(검은색 계열)
@export var bg_color_ground: Color = Color(0.15, 0.15, 0.18)
@export var player_color: Color = Color(0.3, 0.8, 1.0)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)
@export var text_color: Color = Color.WHITE
@export var gameover_text_color: Color = Color(1, 0.4, 0.4)
@export var font_size_label: int = 20
@export var font_size_hint: int = 24
@export var font_size_gameover: int = 64

@export var lane_gap: float = 50.0

# 장애물 크기/속도
@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_speed_start: float = 260.0
@export var obstacle_accel_per_sec: float = 10.0

# 스폰 밀도 난이도(시간 경과에 따라 간격 축소)
@export var spawn_density_ramp_duration: float = 90.0
@export var min_gap_scale_at_max: float = 0.40

# 전역 스폰률 스케일(간격 배수) — 현재 코드 기준 유지
@export var global_spawn_rate_scale: float = 3.0

# 레인별 스폰 간격(기본 범위) + 가중치
@export var lane_gap_time_min: float = 0.60
@export var lane_gap_time_max: float = 1.80
@export var lane_gap_time_mul_top: float = 1.00
@export var lane_gap_time_mul_mid: float = 1.00
@export var lane_gap_time_mul_bot: float = 1.00

# 개별 장애물 속도 배수 범위(무작위 기본치)
@export var obstacle_speed_mul_min: float = 0.75
@export var obstacle_speed_mul_max: float = 1.35

# ▶ 추월 방지 보정 관련(미세 여유/안전계수)
@export var no_overtake_min_gap_px: float = 8.0
@export var no_overtake_safety: float = 0.98

# 중앙 레일 장식(선택)
@export var center_asset_path: String = "res://assets/lane.png"
@export var center_asset_scale: float = 1.0
@export var center_asset_gap_px: float = 480.0
@export var center_asset_y_offset: float = 0.0
@export var center_asset_zindex: int = -10000  # ★ Z_CENTER 기본치

@export var hp_max: int = 3
@export var gameover_wait: float = 3.0

# 파편 프리셋
const _PARTICLE_COUNT_HIT = 3
const _PARTICLE_SIZE_HIT = Vector2(6, 6)
const _PARTICLE_LIFETIME_HIT = 0.45
const _PARTICLE_GRAVITY_HIT = 520.0

const _PARTICLE_COUNT_DEATH = 24
const _PARTICLE_SIZE_DEATH = Vector2(5, 5)
const _PARTICLE_LIFETIME_DEATH = 0.9
const _PARTICLE_GRAVITY_DEATH = 680.0

# ---------- Z Index Plan ----------
const Z_BG = -20000
const Z_STARS = -15000
const Z_CENTER = -10000
const Z_FG_BASE = 0        # 전경 기본 (장애물/플레이어 공통 베이스)
# 같은 레인에서 플레이어가 위에 오도록 lane별 미세 정렬: lane*2 + (0=장애물,1=플레이어)

# 내부 상태
var _view_size: Vector2
var _ground_y: float = 420.0
var _base_obstacle_speed: float = 0.0
var _hp: int = 0
var _is_game_over: bool = false
var _elapsed: float = 0.0
var _last_player_lane: int = -1          # z 갱신용

# 노드
var _bg_space: ColorRect
var _starfield: Node
var _shards: Node
var _hud: Node
var _player_ctrl: Node
var _ground: ColorRect

# 레인/스케일
var _lanes_y: Array = []                  # [top, center, bottom]
var _lane_scales: Array = [0.9, 1.0, 1.1] # 원근 스케일

# 장애물(개별) — { "node": ColorRect, "speed": float, "lane": int }
var _obstacles: Array = []

# 레인별 다음 스폰 예정 시각
var _lane_next_spawn_t: Array = [0.0, 0.0, 0.0]

# 중앙 레일 에셋
var _center_asset_res: Resource
var _center_props: Array = []            # [{ "node": CanvasItem, "w": float }]

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

	# ★ 우주 배경(맨 뒤)
	_bg_space = ColorRect.new()
	_bg_space.color = bg_color_space
	_set_full_rect(_bg_space)
	_bg_space.z_as_relative = false
	_bg_space.z_index = Z_BG
	add_child(_bg_space)

	# StarField (별 파티클)
	var SF = load(starfield_script_path)
	if SF != null:
		_starfield = (SF as Script).new()
		if _starfield is CanvasItem:
			var ci = _starfield as CanvasItem
			ci.z_as_relative = false
			ci.z_index = Z_STARS
		add_child(_starfield)
		# 배경 앞, 중앙 레인 뒤 기준 정렬을 위해 자식 순서도 앞쪽에 둠
		move_child(_starfield, get_child_count() - 1)

	# ShardParticles (전경에 뜨지만 개별 z는 파편 자신이 가짐)
	var SP = load(shard_particles_script_path)
	if SP != null:
		_shards = (SP as Script).new()
		if _shards is CanvasItem:
			var si = _shards as CanvasItem
			si.z_as_relative = false
			si.z_index = Z_FG_BASE + 100  # 파편은 전경 위쪽에 보이도록 살짝 높임
		add_child(_shards)
		if "set_ground_y" in _shards:
			_shards.set_ground_y(_ground_y)

	# Ground 가이드(선택)
	_ground = ColorRect.new()
	_ground.color = bg_color_ground
	_ground.position = Vector2(0, _ground_y)
	_ground.custom_minimum_size = Vector2(_view_size.x, 4)
	_ground.z_as_relative = false
	_ground.z_index = Z_CENTER  # 중앙 레인 에셋과 비슷한 깊이 (장식 아래여도 무관)
	add_child(_ground)

	# Player
	var PC = load(player_controller_script_path)
	if PC != null:
		_player_ctrl = (PC as Script).new()
		add_child(_player_ctrl)
		if "setup" in _player_ctrl:
			_player_ctrl.setup(_ground_y, Vector2(44, 44), player_color, 220.0)
		# 초기 z는 이후 set_lanes에서 갱신
		_apply_player_zindex()
		# HUD보다 아래, 장애물과 같은 전경 레이어 영역
		move_child(_player_ctrl, get_child_count() - 1)

	# HUD
	var GH = load(game_hud_script_path)
	if GH != null:
		_hud = (GH as Script).new()
		if "text_color" in _hud: _hud.text_color = text_color
		if "gameover_text_color" in _hud: _hud.gameover_text_color = gameover_text_color
		if "font_size_label" in _hud: _hud.font_size_label = font_size_label
		if "font_size_hint" in _hud: _hud.font_size_hint = font_size_hint
		if "font_size_gameover" in _hud: _hud.font_size_gameover = font_size_gameover
		if _hud is CanvasItem:
			var hi = _hud as CanvasItem
			hi.z_as_relative = false
			hi.z_index = Z_FG_BASE + 200  # 항상 모든 것 위(텍스트)
		add_child(_hud)
		if "set_hp" in _hud: _hud.set_hp(_hp, hp_max)
		if "set_hint" in _hud: _hud.set_hint("↑/↓ 레인 이동, Space 점프")

	# Lanes + Player
	_make_lanes()
	if _player_ctrl:
		if "set_lanes" in _player_ctrl:
			_player_ctrl.set_lanes(_lanes_y, 1)  # 가운데 시작
		if "set_lane_scales" in _player_ctrl:
			_player_ctrl.set_lane_scales(_lane_scales)
		_apply_player_zindex()

	# 중앙 레인 에셋 로드
	_center_asset_res = null
	if center_asset_path.strip_edges() != "":
		var res = load(center_asset_path)
		if res != null and (res is Texture2D or res is PackedScene):
			_center_asset_res = res

	# 레인별 첫 스폰 예약
	var now = Time.get_ticks_msec() / 1000.0
	_lane_next_spawn_t[0] = now + _rand_lane_gap_time(0)
	_lane_next_spawn_t[1] = now + _rand_lane_gap_time(1)
	_lane_next_spawn_t[2] = now + _rand_lane_gap_time(2)

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

	_elapsed += delta

	# 속도 난이도: 자연 가속
	_base_obstacle_speed += obstacle_accel_per_sec * delta

	# StarField 속도 동기화
	_set_starfield_speed(_base_obstacle_speed)

	# Player 업데이트 + z 보정(라인 변경 감지)
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)
		_check_player_lane_and_update_z()

	# 레인별 스폰
	_try_spawn_lane(0)
	_try_spawn_lane(1)
	_try_spawn_lane(2)

	# 장애물 이동/정리
	_move_and_cleanup_obstacles(delta)

	# 중앙 레일 장식
	_move_and_cleanup_center_props(delta)
	_try_spawn_center_prop()

	# 충돌(같은 레인만)
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

# ───────────── 난이도 스케일(스폰 밀도) ─────────────
func _current_gap_scale() -> float:
	var T: float = max(spawn_density_ramp_duration, 0.001)
	var a: float = clamp(_elapsed / T, 0.0, 1.0)
	return lerp(1.0, clamp(min_gap_scale_at_max, 0.05, 1.0), a)

# ───────────── 레인별 스폰 ─────────────
func _rand_lane_gap_time(lane_idx: int) -> float:
	var mul: float = 1.0
	if lane_idx == 0:
		mul = lane_gap_time_mul_top
	elif lane_idx == 1:
		mul = lane_gap_time_mul_mid
	elif lane_idx == 2:
		mul = lane_gap_time_mul_bot

	var base_min: float = lane_gap_time_min
	var base_max: float = lane_gap_time_max
	if base_max < base_min:
		var t = base_min
		base_min = base_max
		base_max = t

	# 시간 경과 난이도 스케일 + 전역 스폰율 스케일(간격 배수)
	var scale: float = _current_gap_scale() * max(global_spawn_rate_scale, 0.01)
	return max(_rng.randf_range(base_min, base_max) * scale * mul, 0.05)

func _try_spawn_lane(lane_idx: int) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now < _lane_next_spawn_t[lane_idx]:
		return
	_spawn_obstacle(lane_idx)
	_lane_next_spawn_t[lane_idx] = now + _rand_lane_gap_time(lane_idx)

# ───────────── lane → z 계산/적용 ─────────────
func _z_for_lane(lane_idx: int, is_player: bool) -> int:
	# 같은 전경 레이어(Z_FG_BASE) 안에서 lane 순서를 유지하고,
	# 같은 lane에서는 플레이어가 +1로 항상 위.
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

# ───────────── 바로 앞차 정보 찾기(같은 레인, x가 가장 큰 차) ─────────────
func _find_front_car(lane_idx: int) -> Dictionary:
	var best = {}
	var best_x: float = -1e9
	var i: int = 0
	while i < _obstacles.size():
		var e = _obstacles[i]
		if e.has("lane") and int(e["lane"]) == lane_idx:
			var n: ColorRect = e["node"]
			if is_instance_valid(n) and n.position.x > best_x:
				best_x = n.position.x
				best = e
		i += 1
	return best

# ───────────── 추월 방지 속도 보정 계산 ─────────────
func _clamp_speed_no_overtake(desired_speed: float, spawn_x: float, lane_idx: int, scale_s: float) -> float:
	var front = _find_front_car(lane_idx)
	if front.size() == 0:
		return desired_speed

	var front_node: ColorRect = front["node"]
	var front_speed: float = front["speed"]
	if not is_instance_valid(front_node):
		return desired_speed

	var front_w: float = obstacle_size.x * (front_node.scale.x)
	var time_front_leave: float = (front_node.position.x + front_w + 8.0) / max(front_speed, 1.0)
	var gap: float = spawn_x - (front_node.position.x + front_w)
	if gap < 0.0:
		gap = 0.0

	var v_max_if_faster: float = front_speed + (gap + no_overtake_min_gap_px) / max(time_front_leave, 0.001)
	var allowed_max: float = min(v_max_if_faster * no_overtake_safety, max(v_max_if_faster, front_speed))
	return min(desired_speed, allowed_max)

# ───────────── 장애물 스폰 ─────────────
func _spawn_obstacle(lane_idx: int) -> void:
	var spawn_x: float = _view_size.x + 80.0
	var y: float = float(_lanes_y[lane_idx])

	var r = ColorRect.new()
	r.color = obstacle_color
	r.custom_minimum_size = obstacle_size
	var s: float = _lane_scales[lane_idx]
	r.scale = Vector2(s, s)
	r.position = Vector2(spawn_x, y)
	r.z_as_relative = false
	r.z_index = _z_for_lane(lane_idx, false)  # ★ 중앙 레인보다 항상 위, 같은 레인에선 플레이어 아래
	add_child(r)

	# 개별 기본 속도 (기본 난이도 속도 * 랜덤 배수)
	var mul: float = _rng.randf_range(obstacle_speed_mul_min, obstacle_speed_mul_max)
	var desired_speed: float = max(_base_obstacle_speed * mul, 20.0)

	# 추월 방지 보정
	var safe_speed: float = _clamp_speed_no_overtake(desired_speed, spawn_x, lane_idx, s)

	_obstacles.append({ "node": r, "speed": safe_speed, "lane": lane_idx })

# ───────────── 장애물 이동/정리 ─────────────
func _move_and_cleanup_obstacles(delta: float) -> void:
	var i: int = _obstacles.size() - 1
	while i >= 0:
		var e = _obstacles[i]
		var node: ColorRect = e["node"]
		var speed: float = e["speed"]
		if is_instance_valid(node):
			node.position.x -= speed * delta
			if node.position.x + (obstacle_size.x * node.scale.x) < -8.0:
				node.queue_free()
				_obstacles.remove_at(i)
		else:
			_obstacles.remove_at(i)
		i -= 1

# ───────────── 중앙 레일 에셋(장식) ─────────────
func _move_and_cleanup_center_props(delta: float) -> void:
	if _center_props.size() == 0:
		return
	var speed = _base_obstacle_speed
	var i: int = _center_props.size() - 1
	while i >= 0:
		var entry = _center_props[i]
		var node: CanvasItem = entry["node"]
		var w: float = entry["w"]
		if is_instance_valid(node):
			node.position.x -= speed * delta
			if node.position.x + w < -8.0:
				node.queue_free()
				_center_props.remove_at(i)
		else:
			_center_props.remove_at(i)
		i -= 1

func _try_spawn_center_prop() -> void:
	if _center_asset_res == null:
		return
	var rightmost_x: float = -1e9
	for entry in _center_props:
		var n: CanvasItem = entry["node"]
		if is_instance_valid(n):
			rightmost_x = max(rightmost_x, n.position.x)
	var spawn_edge: float = _view_size.x + 80.0
	if rightmost_x > -1e8 and (spawn_edge - rightmost_x) < center_asset_gap_px:
		return
	_spawn_center_prop(spawn_edge)

func _spawn_center_prop(spawn_x: float) -> void:
	if _lanes_y.size() < 2:
		return
	var y: float = float(_lanes_y[1]) + center_asset_y_offset

	if _center_asset_res is Texture2D:
		var tex: Texture2D = _center_asset_res
		var tr = TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tr.position = Vector2(spawn_x, y)
		tr.scale = Vector2(center_asset_scale, center_asset_scale)
		tr.z_as_relative = false
		tr.z_index = Z_CENTER  # ★ 강제 고정
		add_child(tr)
		var w: float = tex.get_size().x * center_asset_scale
		_center_props.append({ "node": tr, "w": w })
		return

	if _center_asset_res is PackedScene:
		var inst: Node = (_center_asset_res as PackedScene).instantiate()
		if inst is CanvasItem:
			var ci = inst as CanvasItem
			if ci is Control:
				(ci as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
			ci.position = Vector2(spawn_x, y)
			ci.scale = Vector2(center_asset_scale, center_asset_scale)
			ci.z_as_relative = false
			ci.z_index = Z_CENTER  # ★ 강제 고정
			add_child(ci)
			var w_scene: float = _estimate_canvasitem_width(ci)
			_center_props.append({ "node": ci, "w": w_scene })
		else:
			var wrapper = Control.new()
			wrapper.set_anchors_preset(Control.PRESET_TOP_LEFT)
			wrapper.position = Vector2(spawn_x, y)
			wrapper.scale = Vector2(center_asset_scale, center_asset_scale)
			wrapper.z_as_relative = false
			wrapper.z_index = Z_CENTER  # ★ 강제 고정
			wrapper.add_child(inst)
			add_child(wrapper)
			var w_wrap: float = 128.0 * center_asset_scale
			_center_props.append({ "node": wrapper, "w": w_wrap })
		return

	var cr = ColorRect.new()
	cr.color = Color(0.6, 0.6, 0.75, 0.9)
	var base_w: float = 128.0
	cr.custom_minimum_size = Vector2(base_w, 48.0)
	cr.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cr.position = Vector2(spawn_x, y)
	cr.scale = Vector2(center_asset_scale, center_asset_scale)
	cr.z_as_relative = false
	cr.z_index = Z_CENTER  # ★ 강제 고정
	add_child(cr)
	_center_props.append({ "node": cr, "w": base_w * center_asset_scale })

func _estimate_canvasitem_width(ci: CanvasItem) -> float:
	if ci is TextureRect:
		var texr = ci as TextureRect
		if texr.texture != null:
			return texr.texture.get_size().x * texr.scale.x
		return texr.size.x * texr.scale.x
	if ci is Sprite2D:
		var sp = ci as Sprite2D
		if sp.texture != null:
			return sp.texture.get_size().x * sp.scale.x
	if ci is Control:
		var c = ci as Control
		return max(c.size.x, c.custom_minimum_size.x) * c.scale.x
	return 128.0 * ci.scale.x

# ───────────── 충돌: 같은 레인의 장애물만 ─────────────
func _check_collision() -> void:
	if _player_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()

	var i: int = 0
	while i < _obstacles.size():
		var e = _obstacles[i]
		if e.has("lane") and int(e["lane"]) == p_lane:
			var r: ColorRect = e["node"]
			if is_instance_valid(r):
				var o_size: Vector2 = obstacle_size * r.scale.x
				var o_rect = Rect2(r.position, o_size)
				if p_rect.intersects(o_rect):
					_on_hit_obstacle(i)
					return
		i += 1

func _on_hit_obstacle(index: int) -> void:
	var e = _obstacles[index]
	var r: ColorRect = e["node"]

	# 파편
	if is_instance_valid(r) and _shards and "spawn_directional_shards" in _shards:
		var center = r.position + (obstacle_size * r.scale.x) * 0.5
		_shards.spawn_directional_shards(
			center, Vector2(-1, 0),
			_PARTICLE_COUNT_HIT, _PARTICLE_SIZE_HIT, _PARTICLE_LIFETIME_HIT, _PARTICLE_GRAVITY_HIT,
			obstacle_color, 260.0, 380.0, 18.0
		)

	# 제거
	if is_instance_valid(r):
		r.queue_free()
	_obstacles.remove_at(index)

	# HP/UI
	_hp -= 1
	if _hp < 0:
		_hp = 0
	if _hud and "set_hp" in _hud:
		_hud.set_hp(_hp, hp_max)
	if _hud and "tint_hp_hit" in _hud:
		_hud.tint_hp_hit()

	# 속도 최저치로 리셋 + StarField 동기화
	_base_obstacle_speed = obstacle_speed_start
	_set_starfield_speed(_base_obstacle_speed)

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

# ───────────── 게임오버 ─────────────
func _trigger_game_over() -> void:
	_is_game_over = true
	_set_starfield_speed(0.0)
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

# ───────────── StarField 연동 ─────────────
func _set_starfield_speed(v: float) -> void:
	if _starfield and "set_speed_px" in _starfield:
		_starfield.set_speed_px(v)

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
