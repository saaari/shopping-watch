extends ColorRect
## 손님 (P1 플레이스홀더 — 색 사각형).
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

func _process(delta: float) -> void:
	match state:
		S.ARRIVING:
			position.x = maxf(seat_x, position.x - SPEED * delta)
			if position.x <= seat_x:
				state = S.WAITING
		S.WAITING:
			# 완성 접시가 나오면 먹기 시작. 없어도 그냥 기다린다 (무벌).
			if kitchen != null and kitchen.take_dish():
				state = S.EATING
				eat_left = EAT_TIME
		S.EATING:
			eat_left -= delta
			if eat_left <= 0.0:
				State.add_money(PAY)
				State.dishes_served += 1
				if kitchen != null:
					kitchen.dirty_dishes += 1
				state = S.LEAVING
		S.LEAVING:
			position.x += SPEED * delta
			if position.x > EXIT_X:
				left.emit(self)
				queue_free()

## 개입: 서빙 돕기 — 대기 중 손님에게 즉시 서빙 + 팁
func serve_directly() -> bool:
	if state == S.WAITING and kitchen != null and kitchen.take_dish():
		state = S.EATING
		eat_left = EAT_TIME
		State.add_money(2)  # 팁
		return true
	return false
