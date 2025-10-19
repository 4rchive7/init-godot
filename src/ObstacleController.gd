# ObstacleController.gd
# Godot 4.4 / GDScript
# SRP: "장애물 관리"만 담당
#  - 스폰/이동/소멸
#  - 시간 경과 속도 가속
#  - 레인별 간격 스케줄 + 전역 스폰율 스케일 + 난이도 램프
#  - 텍스처/폴백(ColorRect) 지원, "보이는 크기 == 충돌 박스" 보장
#  - 같은 레인끼리 '추월 방지' 속도 보정
#  - 충돌 판정은 외부가 Rect2로 질의 → 인덱스 반환/소비
#
# 공개 API
#   set_environment(view_size, lanes_y, lane_scales_unused, z_fg_base)
#   set_spawn_config(min_t, max_t, mul_top, mul_mid, mul_bot, ramp_dur, min_gap_scale_at_max, global_rate_scale)
#   set_speed_config(speed_start, accel_per_sec, mul_min, mul_max, no_overtake_gap_px, no_overtake_safety)
#   set_visual_config(obstacle_size_px, texture_path, tex_scale, tint, collision_inset_px)
#   start()
#   update(delta)
#   get_base_speed() / set_base_speed(v) / reset_speed_to_start()
#   get_collision_index(player_rect: Rect2, player_lane: int) -> int
#   consume_hit(index: int) -> Vector2   # 중심 좌표 반환 + 제거
extends Control

# ── 환경/레이어 ──
var _view_size: Vector2 = Vector2.ZERO
var _lanes_y: Array = []                 # [top, center, bottom]
var _z_fg_base: int = 0

# ── "장애물 전용" 레인 스케일(원근) ──
# 요청: 위/중간/아래 = 0.9 / 1.0 / 1.05
@export var lane_scale_top: float = 0.9
@export var lane_scale_mid: float = 1.0
@export var lane_scale_bot: float = 1.05
func _lane_scale_for(idx: int) -> float:
	if idx == 0:
		return lane_scale_top
	elif idx == 1:
		return lane_scale_mid
	else:
		return lane_scale_bot

# ── 비주얼 ──
var _obstacle_size_px: Vector2 = Vector2(36, 36)   # 폴백 박스 크기
var _obstacle_texture_path: String = ""
var _obstacle_tex: Texture2D = null
var _obstacle_tex_scale: float = 1.0               # 레인 스케일과 곱해짐
var _obstacle_tint: Color = Color(1,1,1,1)
var _collision_inset_px: Vector2 = Vector2.ZERO    # 투명 여백 보정(좌상단 기준)

# ── 속도/난이도 ──
var _speed_start: float = 260.0
var _accel_per_sec: float = 10.0
var _speed_mul_min: float = 0.75
var _speed_mul_max: float = 1.35
var _base_speed: float = 0.0

# 추월 방지
var _no_overtake_min_gap_px: float = 8.0
var _no_overtake_safety: float = 0.98

# 스폰 간격
var _gap_min: float = 0.60
var _gap_max: float = 1.80
var _gap_mul_top: float = 1.0
var _gap_mul_mid: float = 1.0
var _gap_mul_bot: float = 1.0
var _spawn_ramp_dur: float = 90.0
var _min_gap_scale_at_max: float = 0.40
var _global_rate_scale: float = 1.0     # 3.0이면 간격 3배(수량 1/3)

# 스케줄/상태
var _lane_next_spawn_t: Array = [0.0, 0.0, 0.0]
var _elapsed: float = 0.0

# 장애물 엔트리: { "node": CanvasItem, "speed": float, "lane": int, "size": Vector2, "inset": Vector2 }
var _obstacles: Array = []

# RNG
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	set_process(false)

# ───────── 외부 세팅 ─────────
func set_environment(view_size: Vector2, lanes_y: Array, _lane_scales_unused: Array, z_fg_base: int) -> void:
	# (참고) 세 번째 인자는 플레이어용 스케일일 수 있으나,
	# 장애물 스케일은 본 컨트롤러의 lane_scale_* 값을 사용합니다.
	_view_size = view_size
	_lanes_y = lanes_y.duplicate()
	_z_fg_base = z_fg_base

func set_spawn_config(min_t: float, max_t: float, mul_top: float, mul_mid: float, mul_bot: float, ramp_dur: float, min_gap_scale: float, global_rate_scale: float) -> void:
	_gap_min = min_t
	_gap_max = max_t
	_gap_mul_top = mul_top
	_gap_mul_mid = mul_mid
	_gap_mul_bot = mul_bot
	_spawn_ramp_dur = ramp_dur
	_min_gap_scale_at_max = min_gap_scale
	_global_rate_scale = max(global_rate_scale, 0.01)

func set_speed_config(speed_start: float, accel_per_sec: float, mul_min: float, mul_max: float, no_overtake_gap_px: float, no_overtake_safety: float) -> void:
	_speed_start = speed_start
	_accel_per_sec = accel_per_sec
	_speed_mul_min = mul_min
	_speed_mul_max = mul_max
	_no_overtake_min_gap_px = no_overtake_gap_px
	_no_overtake_safety = no_overtake_safety

func set_visual_config(obstacle_size_px: Vector2, texture_path: String, tex_scale: float, tint: Color, collision_inset_px: Vector2) -> void:
	_obstacle_size_px = obstacle_size_px
	_obstacle_texture_path = texture_path
	_obstacle_tex_scale = tex_scale
	_obstacle_tint = tint
	_collision_inset_px = collision_inset_px
	_obstacle_tex = null
	if _obstacle_texture_path.strip_edges() != "":
		var r = load(_obstacle_texture_path)
		if r != null and r is Texture2D:
			_obstacle_tex = r

func start() -> void:
	_base_speed = _speed_start
	_elapsed = 0.0
	var now = Time.get_ticks_msec() / 1000.0
	_lane_next_spawn_t[0] = now + _rand_lane_gap_time(0)
	_lane_next_spawn_t[1] = now + _rand_lane_gap_time(1)
	_lane_next_spawn_t[2] = now + _rand_lane_gap_time(2)
	set_process(true)

# ───────── 런타임 ─────────
func update(delta: float) -> void:
	_elapsed += delta
	_base_speed += _accel_per_sec * delta
	_try_spawn_lane(0)
	_try_spawn_lane(1)
	_try_spawn_lane(2)
	_move_and_cleanup(delta)

func get_base_speed() -> float:
	return _base_speed

func set_base_speed(v: float) -> void:
	_base_speed = v

func reset_speed_to_start() -> void:
	_base_speed = _speed_start

# ───────── 충돌 질의/소비 ─────────
func get_collision_index(p_rect: Rect2, p_lane: int) -> int:
	var i: int = 0
	while i < _obstacles.size():
		var e = _obstacles[i]
		if int(e["lane"]) == p_lane:
			var n: CanvasItem = e["node"]
			if is_instance_valid(n):
				var o_sz: Vector2 = e["size"]
				var inset: Vector2 = e["inset"]
				var o_rect = Rect2(n.position + inset, o_sz - inset * 2.0)
				if p_rect.intersects(o_rect):
					return i
		i += 1
	return -1

func consume_hit(index: int) -> Vector2:
	if index < 0 or index >= _obstacles.size():
		return Vector2.ZERO
	var e = _obstacles[index]
	var n: CanvasItem = e["node"]
	var size_px: Vector2 = e["size"]
	var center = Vector2.ZERO
	if is_instance_valid(n):
		center = n.position + size_px * 0.5
		n.queue_free()
	_obstacles.remove_at(index)
	return center

# ───────── 내부: 스폰/이동 ─────────
func _current_gap_scale() -> float:
	var T: float = max(_spawn_ramp_dur, 0.001)
	var a: float = clamp(_elapsed / T, 0.0, 1.0)
	return lerp(1.0, clamp(_min_gap_scale_at_max, 0.05, 1.0), a)

func _rand_lane_gap_time(lane_idx: int) -> float:
	var mul: float = 1.0
	if lane_idx == 0:
		mul = _gap_mul_top
	elif lane_idx == 1:
		mul = _gap_mul_mid
	elif lane_idx == 2:
		mul = _gap_mul_bot
	var base_min: float = _gap_min
	var base_max: float = _gap_max
	if base_max < base_min:
		var t = base_min
		base_min = base_max
		base_max = t
	var scale = _current_gap_scale() * _global_rate_scale
	return max(_rng.randf_range(base_min, base_max) * scale * mul, 0.05)

func _try_spawn_lane(lane_idx: int) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now < _lane_next_spawn_t[lane_idx]:
		return
	_spawn_obstacle(lane_idx)
	_lane_next_spawn_t[lane_idx] = now + _rand_lane_gap_time(lane_idx)

func _z_for_lane(lane_idx: int) -> int:
	return _z_fg_base + lane_idx * 2   # (플레이어는 GameLayer에서 +1 적용)

func _spawn_obstacle(lane_idx: int) -> void:
	var spawn_x: float = _view_size.x + 80.0
	var y: float = float(_lanes_y[lane_idx])

	# ★ 요청 스케일 반영: 0.9 / 1.0 / 1.05
	var s_lane: float = _lane_scale_for(lane_idx)

	var node: CanvasItem = null
	var size_px: Vector2
	var inset_px: Vector2 = _collision_inset_px

	if _obstacle_tex != null:
		var tr = TextureRect.new()
		tr.texture = _obstacle_tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tr.position = Vector2(spawn_x, y)
		tr.modulate = _obstacle_tint

		# 텍스처 고유 크기 × (텍스처 스케일 × 레인 스케일)
		var tex_size: Vector2 = _obstacle_tex.get_size()
		var s_total: float = _obstacle_tex_scale * s_lane
		tr.scale = Vector2(s_total, s_total)   # ← X/Y 동일하게 적용 (찌그러짐 방지)
		tr.z_as_relative = false
		tr.z_index = _z_for_lane(lane_idx)
		add_child(tr)
		node = tr
		size_px = tex_size * s_total
	else:
		var r = ColorRect.new()
		r.color = Color(1.0, 0.35, 0.35)
		r.custom_minimum_size = _obstacle_size_px
		r.position = Vector2(spawn_x, y)
		r.scale = Vector2(s_lane, s_lane)      # ← X/Y 동일
		r.z_as_relative = false
		r.z_index = _z_for_lane(lane_idx)
		add_child(r)
		node = r
		size_px = _obstacle_size_px * s_lane

	# 속도 + 추월 방지
	var mul: float = _rng.randf_range(_speed_mul_min, _speed_mul_max)
	var desired_speed: float = max(_base_speed * mul, 20.0)
	var safe_speed: float = _clamp_speed_no_overtake(desired_speed, spawn_x, lane_idx, size_px)

	_obstacles.append({ "node": node, "speed": safe_speed, "lane": lane_idx, "size": size_px, "inset": inset_px })

func _find_front_car(lane_idx: int) -> Dictionary:
	var best = {}
	var best_x: float = -1e9
	var i: int = 0
	while i < _obstacles.size():
		var e = _obstacles[i]
		if int(e["lane"]) == lane_idx:
			var n: CanvasItem = e["node"]
			if is_instance_valid(n) and n.position.x > best_x:
				best_x = n.position.x
				best = e
		i += 1
	return best

func _clamp_speed_no_overtake(desired_speed: float, spawn_x: float, lane_idx: int, size_px_new: Vector2) -> float:
	var front = _find_front_car(lane_idx)
	if front.size() == 0:
		return desired_speed
	var fn: CanvasItem = front["node"]
	if not is_instance_valid(fn):
		return desired_speed
	var v_front: float = front["speed"]
	var size_front: Vector2 = front["size"]

	var time_front_leave: float = (fn.position.x + size_front.x + 8.0) / max(v_front, 1.0)
	var gap: float = spawn_x - (fn.position.x + size_front.x)
	if gap < 0.0:
		gap = 0.0

	var v_max_if_faster: float = v_front + (gap + _no_overtake_min_gap_px) / max(time_front_leave, 0.001)
	var allowed_max: float = min(v_max_if_faster * _no_overtake_safety, max(v_max_if_faster, v_front))
	return min(desired_speed, allowed_max)

func _move_and_cleanup(delta: float) -> void:
	var i: int = _obstacles.size() - 1
	while i >= 0:
		var e = _obstacles[i]
		var n: CanvasItem = e["node"]
		var speed: float = e["speed"]
		var sz: Vector2 = e["size"]
		if is_instance_valid(n):
			n.position.x -= speed * delta
			if n.position.x + sz.x < -8.0:
				n.queue_free()
				_obstacles.remove_at(i)
		else:
			_obstacles.remove_at(i)
		i -= 1
