extends Node2D
## 손님 — 걷기 스프라이트(왼쪽 면) 기반. 오른쪽 이동은 좌우 반전.
## 철칙: 기다림에 벌 없음 — 요리가 없으면 화내지 않고 조용히 계속 기다린다.

signal left(customer)
signal started_eating(customer)
signal finished_meal(customer)
signal paid(customer, amount: int)

enum S { ARRIVING, WAITING, EATING, LEAVING }

const SPEED := 40.0     # 논리 px/s
const EAT_TIME := 300.0 # 오래 앉아 있는 손님이 왁자지껄한 장면을 만든다
const PAY := 10
const TEA_WAIT := 300.0 # 이만큼 기다리면 차만 마시고 흐뭇하게 떠난다 (무벌 회전)
const TEA_PAY := 3

var state: int = S.ARRIVING
var seat_x := 0.0
var table_idx := -1
var exit_x := 660.0
var eat_left := 0.0
var wait_left := TEA_WAIT
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
			sprite.flip_h = false
			position.x = maxf(seat_x, position.x - SPEED * delta)
			if position.x <= seat_x:
				state = S.WAITING
				sprite.stop()
				sprite.frame = 0
		S.WAITING:
			if kitchen != null and kitchen.take_dish():
				state = S.EATING
				eat_left = EAT_TIME
				started_eating.emit(self)
			else:
				wait_left -= delta
				if wait_left <= 0.0:  # 차 한 잔 룰
					# 잉걸불 날의 손님은 애초에 불을 쬐러 온 것 — 찻값을 후하게 놓고 간다
					var pay := 5 if State.fire_state == "ember" else TEA_PAY
					State.add_money(pay)
					paid.emit(self, pay)
					_leave()
		S.EATING:
			eat_left -= delta
			if eat_left <= 0.0:
				State.add_money(PAY)
				State.dishes_served += 1
				paid.emit(self, PAY)
				finished_meal.emit(self)
				_leave()
		S.LEAVING:
			position.x += SPEED * delta
			if position.x > exit_x:
				left.emit(self)
				queue_free()

func _leave() -> void:
	state = S.LEAVING
	sprite.flip_h = true
	sprite.play("walk")

## 개입: 서빙 돕기 — 대기 중 손님에게 즉시 서빙 + 팁
func serve_directly() -> bool:
	if state == S.WAITING and kitchen != null and kitchen.take_dish():
		state = S.EATING
		eat_left = EAT_TIME
		started_eating.emit(self)
		State.add_money(2)
		paid.emit(self, 2)
		return true
	return false
