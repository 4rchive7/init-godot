# ObstacleController.gd
# Godot 4.4 / GDScript
extends Control

# ── 환경/레이어 ──
var _view_size: Vector2 = Vector2.ZERO
var _lanes_y: Array = []
var _z_fg_base: int = 0

# ── 레인 스케일 ──
@export var lane_scale_top: float = 0.9
@export var lane_scale_mid: float = 1.0
@export var lane_scale_bot: float = 1.05

# ★★★ km/h 상한 설정(편집기에서 바로 조절) ★★★
@export var max_speed_kmh: float = 100.0       # ← 여기 값을 100으로!
@export var overcap_kmh: float = 20.0         # 부스트 시 일시 초과 허용치(+10km/h)
@export var kmh_per_pxps: float = 0.1          # HUD에서 km/h = v(px/s)*0.1 을 쓴다면 0.1 유지

var _overcap_left: float = 0.0                # 부스트 초과 허용 잔여시간(초)

func _lane_scale_for(idx: int) -> float:
	if idx == 0: return lane_scale_top
	elif idx == 1: return lane_scale_mid
	else: return lane_scale_bot

# ── 비주얼 ──
var _obstacle_size_px: Vector2 = Vector2(36, 36)
var _obstacle_texture_path: String = ""
var _obstacle_tex: Texture2D = null
var _obstacle_tex_scale: float = 1.0
var _obstacle_tint: Color = Color(1,1,1,1)
var _collision_inset_px: Vector2 = Vector2.ZERO

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
var _global_rate_scale: float = 1.0

# 스케줄/상태
var _lane_next_spawn_t: Array = [0.0, 0.0, 0.0]
var _elapsed: float = 0.0

# 엔트리
var _obstacles: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	set_process(false)

# ───────── 외부 세팅 ─────────
func set_environment(view_size: Vector2, lanes_y: Array, _lane_scales_unused: Array, z_fg_base: int) -> void:
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

func start_overcap(duration_sec: float) -> void:
	# 현재 최고 속도(px/s) 계산
	var normal_cap_pxps: float = _pxps_from_kmh(max_speed_kmh)
	
	# 현재 속도가 최고 속도 이상일 때만 오버캡 발동
	if _base_speed >= normal_cap_pxps - 0.01:
		_overcap_left = max(duration_sec, 0.0)


# func set_base_speed(v: float) -> void:
# 	var cap_kmh: float = max_speed_kmh
# 	if _overcap_left > 0.0:
# 		cap_kmh = max_speed_kmh + overcap_kmh
# 	var cap_pxps: float = _pxps_from_kmh(cap_kmh)
# 	_base_speed = min(v, cap_pxps)


# ───────── 런타임 ─────────
func update(delta: float) -> void:
	# 경과 시간 및 오버캡 감소
	_elapsed += delta
	_overcap_left = max(_overcap_left - delta, 0.0)

	# 최고속도(px/s)와 오버캡 속도(px/s) 미리 계산
	var normal_cap: float = _pxps_from_kmh(max_speed_kmh)
	var overcap_cap: float = _pxps_from_kmh(max_speed_kmh + overcap_kmh)

	# 기본 가속 로직
	if _base_speed < normal_cap:
		_base_speed += _accel_per_sec * delta
	elif _base_speed >= normal_cap:
		# 최고속도 이상인 경우
		if _overcap_left > 0.0:
			# 오버캡 중이면 +overcap_kmh 적용
			_base_speed = overcap_cap
		else:
			# 오버캡이 끝났다면 최고속도로 복귀
			_base_speed = normal_cap

	# 스폰 및 이동 처리
	_try_spawn_lane(0)
	_try_spawn_lane(1)
	_try_spawn_lane(2)
	_move_and_cleanup(delta)


func get_base_speed() -> float:
	return _base_speed

func set_base_speed(v: float) -> void:
	_base_speed = min(v, _pxps_from_kmh(max_speed_kmh))  # ★ 상한 유지

func reset_speed_to_start() -> void:
	_base_speed = min(_speed_start, _pxps_from_kmh(max_speed_kmh))  # ★ 상한 유지

# km/h → px/s 변환 (HUD와 동일한 규칙 사용)
func _pxps_from_kmh(kmh: float) -> float:
	# km/h = px/s * kmh_per_pxps  →  px/s = km/h ÷ kmh_per_pxps
	return kmh / max(kmh_per_pxps, 0.00001)

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
	if lane_idx == 0: mul = _gap_mul_top
	elif lane_idx == 1: mul = _gap_mul_mid
	elif lane_idx == 2: mul = _gap_mul_bot

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
	var BIG_OFFSET: int = 100
	return _z_fg_base + BIG_OFFSET + lane_idx * 2

func _spawn_obstacle(lane_idx: int) -> void:
	var spawn_x: float = _view_size.x + 80.0
	var y: float = float(_lanes_y[lane_idx])

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

		var tex_size: Vector2 = _obstacle_tex.get_size()
		var s_total: float = _obstacle_tex_scale * s_lane
		tr.scale = Vector2(s_total, s_total)
		tr.z_as_relative = false
		tr.z_index = _z_for_lane(lane_idx)
		add_child(tr)

		node = tr
		size_px = tex_size * s_total
	else:
		var r = ColorRect.new()
		r.color = Color(1.0, 0.35, 0.35)
		r.custom_minimum_size = _obstacle_size_px
		r.set_anchors_preset(Control.PRESET_TOP_LEFT)
		r.position = Vector2(spawn_x, y)
		r.scale = Vector2(s_lane, s_lane)
		r.z_as_relative = false
		r.z_index = _z_for_lane(lane_idx)
		add_child(r)

		node = r
		size_px = _obstacle_size_px * s_lane

	# 속도(기본 * 랜덤) + 추월 방지
	var mul: float = _rng.randf_range(_speed_mul_min, _speed_mul_max)
	var desired_speed: float = max(_base_speed * mul, 20.0)
	var safe_speed: float = _clamp_speed_no_overtake(desired_speed, spawn_x, lane_idx, size_px)
	_obstacles.append({
		"node": node,
		"speed": safe_speed,
		"lane": lane_idx,
		"size": size_px,
		"inset": inset_px
	})

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
	if gap < 0.0: gap = 0.0

	var v_max_if_faster: float = v_front + (gap + _no_overtake_min_gap_px) / max(time_front_leave, 0.001)
	var allowed_max: float = min(
		v_max_if_faster * _no_overtake_safety,
		max(v_max_if_faster, v_front)
	)

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

# 정상 상한(px/s): 오버캡 미적용 상태 기준
func get_normal_cap_pxps() -> float:
	return _pxps_from_kmh(max_speed_kmh)

# 지금이 정상 상한에 거의 도달했는지(부동소수 오차 감안)
func is_at_normal_cap() -> bool:
	return _base_speed >= get_normal_cap_pxps() - 0.01
