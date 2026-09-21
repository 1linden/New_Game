extends Node
## Saltmire Spark — one-call 2D particle bursts for Godot 4.
##
## Autoloaded as `Spark`. Fire a burst of short-lived particles at any point or
## node in a single line — hit sparks, pickups, explosions, dust, confetti.
## Self-contained, zero dependencies, no textures needed (procedural), MIT.
##
## Quick use:
##   Spark.burst(global_position)                 # default white spark pop
##   Spark.burst(enemy.global_position, "hit")    # a named preset
##   Spark.at(node, "explode")                     # burst at a node's position
##   Spark.burst(pos, {                            # or a full custom dict
##       "amount": 24,
##       "color": Color(1.0, 0.8, 0.2),
##       "speed": 320.0,
##       "lifetime": 0.5,
##       "size": 3.0,
##       "gravity": 600.0,
##       "spread": TAU,          # full circle
##   })
##
## Built-in presets (tweak Spark.presets or add your own):
##   "spark"    white/yellow quick pop (default)
##   "hit"      tight red-orange impact fan
##   "explode"  big fiery radial blast
##   "pickup"   soft upward cyan sparkle
##   "dust"     low, slow brown puff
##   "confetti" wide multicolor celebration

## Named presets. Any key omitted falls back to `base`.
var base := {
	"amount": 14,            # particles per burst
	"color": Color(1, 1, 1),  # base color (see color2 for gradient end)
	"color2": Color(1, 1, 1, 0),  # end color (fades to this)
	"speed": 220.0,          # initial px/s
	"speed_min": 0.35,       # min fraction of speed (randomized 0.35..1.0)
	"lifetime": 0.45,        # seconds
	"lifetime_rand": 0.35,   # +/- fraction randomization
	"size": 3.0,             # particle radius px
	"size_end": 0.0,         # radius at end of life (shrinks)
	"gravity": 480.0,        # downward px/s^2
	"damping": 2.0,          # velocity decay per second
	"spread": TAU,           # angular spread (radians)
	"direction": -PI / 2.0,  # center angle (up)
	"z_index": 100,
}

var presets := {
	"spark": {},
	"hit": {
		"amount": 12, "color": Color(1.0, 0.75, 0.2), "color2": Color(1.0, 0.2, 0.1, 0),
		"speed": 300.0, "lifetime": 0.28, "size": 3.0, "gravity": 200.0,
		"spread": PI * 0.7,
	},
	"explode": {
		"amount": 34, "color": Color(1.0, 0.85, 0.35), "color2": Color(0.8, 0.15, 0.05, 0),
		"speed": 380.0, "lifetime": 0.6, "size": 5.0, "gravity": 260.0,
		"spread": TAU, "damping": 2.6,
	},
	"pickup": {
		"amount": 12, "color": Color(0.5, 0.95, 1.0), "color2": Color(0.7, 1.0, 1.0, 0),
		"speed": 150.0, "lifetime": 0.5, "size": 2.5, "gravity": -120.0,
		"spread": PI * 0.9, "direction": -PI / 2.0,
	},
	"dust": {
		"amount": 10, "color": Color(0.72, 0.6, 0.45), "color2": Color(0.72, 0.6, 0.45, 0),
		"speed": 90.0, "lifetime": 0.55, "size": 4.0, "gravity": 60.0,
		"spread": PI * 0.6, "direction": -PI / 2.0, "damping": 3.0,
	},
	"confetti": {
		"amount": 28, "color": Color(1, 1, 1), "color2": Color(1, 1, 1, 0),
		"speed": 300.0, "lifetime": 0.9, "size": 3.5, "gravity": 520.0,
		"spread": TAU, "rainbow": true,
	},
}

var _pool: Node2D


func _ready() -> void:
	_ensure_pool()


func _ensure_pool() -> void:
	if _pool != null and is_instance_valid(_pool):
		return
	_pool = Node2D.new()
	_pool.name = "SaltmireSparkPool"
	add_child(_pool)


## Fire a burst at a global position. `opts` is a preset name (String) or a
## dict of overrides (over `base`), or omitted for the default spark.
func burst(global_position: Vector2, opts = {}) -> void:
	_ensure_pool()
	var o := _resolve(opts)
	var emitter := _SparkEmitter.new()
	emitter.global_position = global_position
	emitter.z_index = int(o.z_index)
	emitter.setup(o)
	_pool.add_child(emitter)


## Fire a burst at a node's global position (Node2D or Control).
func at(node: Node, opts = {}) -> void:
	if node == null or not is_instance_valid(node):
		return
	var pos := Vector2.ZERO
	if node is Node2D:
		pos = (node as Node2D).global_position
	elif node is Control:
		pos = (node as Control).global_position
	burst(pos, opts)


## Remove every live burst immediately.
func clear() -> void:
	_ensure_pool()
	for c in _pool.get_children():
		c.queue_free()


# ── internals ────────────────────────────────────────────────────────────────

func _resolve(opts) -> Dictionary:
	var out := base.duplicate()
	if typeof(opts) == TYPE_STRING:
		var p: Dictionary = presets.get(opts, {})
		for k in p:
			out[k] = p[k]
	elif typeof(opts) == TYPE_DICTIONARY:
		for k in opts:
			out[k] = opts[k]
	return out


## Self-drawing, self-freeing particle burst. One Node2D draws all its particles
## in _draw and animates them in _process — cheap and dependency-free.
class _SparkEmitter extends Node2D:
	var _parts: Array = []
	var _age := 0.0
	var _max_life := 0.5
	var _opts := {}

	func setup(o: Dictionary) -> void:
		_opts = o
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var amount := int(o.amount)
		var base_speed: float = o.speed
		var spread: float = o.spread
		var dir: float = o.direction
		var life: float = o.lifetime
		var life_rand: float = o.lifetime_rand
		var speed_min: float = o.speed_min
		var rainbow: bool = o.get("rainbow", false)
		_max_life = 0.0
		for i in amount:
			var ang := dir + rng.randf_range(-spread * 0.5, spread * 0.5)
			var sp := base_speed * rng.randf_range(speed_min, 1.0)
			var pl := life * (1.0 + rng.randf_range(-life_rand, life_rand))
			pl = maxf(0.05, pl)
			_max_life = maxf(_max_life, pl)
			var col: Color = o.color
			if rainbow:
				col = Color.from_hsv(rng.randf(), 0.85, 1.0)
			_parts.append({
				"pos": Vector2.ZERO,
				"vel": Vector2(cos(ang), sin(ang)) * sp,
				"age": 0.0,
				"life": pl,
				"col": col,
			})
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_age += delta
		var gravity: float = _opts.gravity
		var damping: float = _opts.damping
		var alive := 0
		for p in _parts:
			if p.age >= p.life:
				continue
			alive += 1
			p.age += delta
			p.vel.y += gravity * delta
			p.vel *= 1.0 - clampf(damping * delta, 0.0, 1.0)
			p.pos += p.vel * delta
		queue_redraw()
		if alive == 0 or _age > _max_life + 0.05:
			queue_free()

	func _draw() -> void:
		var size0: float = _opts.size
		var size1: float = _opts.size_end
		var col2: Color = _opts.color2
		for p in _parts:
			if p.age >= p.life:
				continue
			var t: float = clampf(p.age / p.life, 0.0, 1.0)
			var r: float = lerpf(size0, size1, t)
			if r <= 0.15:
				continue
			var c: Color = (p.col as Color).lerp(col2, t)
			draw_circle(p.pos, r, c)
