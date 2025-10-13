# ShardParticles.gd
# Godot 4.4 / GDScript
# 히트/사망 시 생성되는 파편(ColorRect)들을 전담 관리하는 모듈
# - spawn_directional_shards(): 특정 진행 방향으로 좁은 각도 스프레드
# - spawn_radial_shards(): 사방(360도) 폭발 스프레드
# - 바닥 반사, 페이드아웃, 수명 관리 포함
extends Control

@export var ground_bounce_damping: float = 0.35  # 바닥 반사 감쇠
@export var air_damping: float = 0.985           # 공기저항 감쇠

var _ground_y: float = 99999.0
var _particles: Array = []  # { "node": ColorRect, "vel": Vector2, "ttl": float, "grav": float, "ttl_max": float }
var _rng: RandomNumberGenerator

func _ready() -> void:
	_set_full_rect(self)
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	set_process(true)

# ---- 외부에서 바닥 높이 갱신 ----
func set_ground_y(v: float) -> void:
	_ground_y = v

# ---- 진행방향 샤드 스폰 ----
func spawn_directional_shards(center_pos: Vector2, dir: Vector2, count: int, size_px: Vector2, lifetime: float, grav: float, color: Color, min_speed: float, max_speed: float, spread_deg: float) -> void:
	var d: Vector2 = dir.normalized()
	var i: int = 0
	while i < count:
		var shard = ColorRect.new()
		shard.color = color
		shard.custom_minimum_size = size_px
		var jitter: Vector2 = Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0))
		shard.position = center_pos - size_px * 0.5 + jitter
		add_child(shard)

		var angle_rad: float = deg_to_rad(_rng.randf_range(-spread_deg, spread_deg))
		var speed: float = _rng.randf_range(min_speed, max_speed)
		var vel: Vector2 = d.rotated(angle_rad) * speed
		vel.y += _rng.randf_range(-120.0, 40.0)

		var particle = {
			"node": shard,
			"vel": vel,
			"ttl": lifetime,
			"grav": grav,
			"ttl_max": lifetime
		}
		_particles.append(particle)
		i += 1

# ---- 전방위 샤드 스폰 ----
func spawn_radial_shards(center_pos: Vector2, count: int, size_px: Vector2, lifetime: float, grav: float, base_color: Color, min_speed: float, max_speed: float) -> void:
	var i: int = 0
	while i < count:
		var shard = ColorRect.new()
		var hue_shift: float = _rng.randf_range(-0.04, 0.04)
		var c: Color = base_color
		c = c.from_hsv(
			fposmod(c.h + hue_shift, 1.0),
			clamp(c.s + _rng.randf_range(-0.15, 0.15), 0.0, 1.0),
			clamp(c.v + _rng.randf_range(-0.10, 0.10), 0.0, 1.0),
			1.0
		)
		shard.color = c
		shard.custom_minimum_size = size_px
		var jitter: Vector2 = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
		shard.position = center_pos - size_px * 0.5 + jitter
		add_child(shard)

		var angle_rad: float = _rng.randf_range(0.0, TAU)
		var speed: float = _rng.randf_range(min_speed, max_speed)
		var vel: Vector2 = Vector2(cos(angle_rad), sin(angle_rad)) * speed

		var particle = {
			"node": shard,
			"vel": vel,
			"ttl": lifetime,
			"grav": grav,
			"ttl_max": lifetime
		}
		_particles.append(particle)
		i += 1

func _process(delta: float) -> void:
	_update_particles(delta)

func _update_particles(delta: float) -> void:
	var i: int = _particles.size() - 1
	while i >= 0:
		var p = _particles[i]
		var node: ColorRect = p["node"]
		var vel: Vector2 = p["vel"]
		var ttl: float = p["ttl"]
		var grav: float = p["grav"]
		var ttl_max: float = p["ttl_max"]

		vel.y += grav * delta
		vel = vel * air_damping

		if is_instance_valid(node):
			node.position += vel * delta
			ttl -= delta

			var t: float = clamp(ttl / max(ttl_max, 0.00001), 0.0, 1.0)
			var col: Color = node.color
			col.a = t
			node.color = col

			# 바닥 반사
			if node.position.y + node.custom_minimum_size.y > _ground_y:
				node.position.y = _ground_y - node.custom_minimum_size.y
				vel.y = -abs(vel.y) * ground_bounce_damping
		else:
			ttl = -1.0

		p["vel"] = vel
		p["ttl"] = ttl
		_particles[i] = p

		if ttl <= 0.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_particles.remove_at(i)
		i -= 1

# ---- 유틸 ----
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
