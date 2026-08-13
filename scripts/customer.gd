extends Node2D
## 손님 — 걷기 스프라이트(왼쪽 면) 기반. 오른쪽 이동은 좌우 반전.
## 철칙: 기다림에 벌 없음 — 요리가 없으면 화내지 않고 조용히 계속 기다린다.

signal left(customer)

enum S { ARRIVING, WAITING, EATING, LEAVING }

const SPEED := 40.0     # 논리 px/s
const EAT_TIME := 5.0
const PAY := 10
const EXIT_X := 660.0

var state: int = S.ARRIVING
var seat_x := 0.0
var eat_left := 0.0
var kitchen: Node
var guest_name := ""
var sprite: AnimatedSprite2D

func setup(frames: SpriteFrames) -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.play("walk")
	add_child(sprite)

func _process(delta: float) -> void:
	match state:
		S.ARRIVING:
			sprite.flip_h = false  # 왼쪽으로 이동 = 원본 방향
			position.x = maxf(seat_x, position.x - SPEED * delta)
			if position.x <= seat_x:
				state = S.WAITING
				sprite.stop()
				sprite.frame = 0
		S.WAITING:
			if kitchen != null and kitchen.take_dish():
				_start_eating()
		S.EATING:
			eat_left -= delta
			if eat_left <= 0.0:
				State.add_money(PAY)
				State.dishes_served += 1
				if kitchen != null:
					kitchen.dirty_dishes += 1
				state = S.LEAVING
				sprite.flip_h = true  # 오른쪽으로 퇴장 = 반전
				sprite.play("walk")
		S.LEAVING:
			position.x += SPEED * delta
			if position.x > EXIT_X:
				left.emit(self)
				queue_free()

func _start_eating() -> void:
	state = S.EATING
	eat_left = EAT_TIME

## 개입: 서빙 돕기 — 대기 중 손님에게 즉시 서빙 + 팁
func serve_directly() -> bool:
	if state == S.WAITING and kitchen != null and kitchen.take_dish():
		_start_eating()
		State.add_money(2)  # 팁
		return true
	return false
