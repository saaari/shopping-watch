extends Node2D
## 알바생 — 테이블의 빈 접시를 치워 조리대 옆 설거지 더미로 나른다.
## 부지런히 오가는 모습 자체가 "왁자지껄"의 절반이다.

enum S { IDLE, TO_TABLE, CLEARING, RETURN }

const SPEED := 45.0
const CLEAR_TIME := 6.0
const HOME_X := 200.0

var state: int = S.IDLE
var target_table: Dictionary = {}
var clear_left := 0.0
var carrying := 0
var main: Node2D
var sprite: AnimatedSprite2D

func setup(frames: SpriteFrames) -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.play("walk")
	add_child(sprite)

func _process(delta: float) -> void:
	match state:
		S.IDLE:
			sprite.stop()
			sprite.frame = 0
			var t := _find_dirty_table()
			if not t.is_empty():
				target_table = t
				state = S.TO_TABLE
				sprite.play("walk")
		S.TO_TABLE:
			if _walk_to(float(target_table.x), delta):
				state = S.CLEARING
				clear_left = CLEAR_TIME
				sprite.stop()
		S.CLEARING:
			clear_left -= delta
			if clear_left <= 0.0:
				carrying = main.clear_table(target_table)
				state = S.RETURN
				sprite.play("walk")
		S.RETURN:
			if _walk_to(HOME_X, delta):
				if main != null and carrying > 0:
					main.kitchen.dirty_dishes += carrying
				carrying = 0
				state = S.IDLE

func _find_dirty_table() -> Dictionary:
	if main == null:
		return {}
	for t in main.tables:
		if int(t.plates) > 0 and not bool(t.get("claimed", false)):
			t.claimed = true
			return t
	return {}

func _walk_to(x: float, delta: float) -> bool:
	var dx := x - position.x
	sprite.flip_h = dx > 0.0
	position.x += clampf(dx, -SPEED * delta, SPEED * delta)
	return absf(dx) < 2.0
