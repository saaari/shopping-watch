extends AnimatedSprite2D
## 역귀 — 주방 스테이션을 오가며 일한다. 한가할 땐 홀을 둥실 떠다닌다 (유령).

const SPEED := 30.0
const HEARTH_X := 62.0    # 화덕 앞 (조리)
const COUNTER_X := 128.0  # 조리대 (손질)
const IDLE_MIN_X := 130.0
const IDLE_MAX_X := 214.0

var kitchen: Node
var base_y := 96.0
var target_x := 148.0
var idle_left := 2.0
var t := 0.0

func _process(delta: float) -> void:
	t += delta
	var station := ""
	if kitchen.prepping:
		station = "prep"
		target_x = COUNTER_X
	elif kitchen.pot_servings > 0:
		station = "cook"
		target_x = HEARTH_X
	else:
		idle_left -= delta
		if idle_left <= 0.0:
			idle_left = randf_range(3.0, 8.0)
			target_x = randf_range(IDLE_MIN_X, IDLE_MAX_X)
	var dx := target_x - position.x
	if absf(dx) > 2.0:
		flip_h = dx > 0.0  # 원본이 왼쪽 면 — 오른쪽 이동만 반전
		position.x += clampf(dx, -SPEED * delta, SPEED * delta)
		if animation != "walk" or not is_playing():
			play("walk")
	elif station != "":
		flip_h = false  # 스테이션은 모두 왼쪽에 있다
		if animation != "cook" or not is_playing():
			play("cook")
	else:
		stop()
		frame = 0
	# 유령의 둥실거림 — 픽셀 스냅이 1px 계단으로 래스터한다
	position.y = base_y + sin(t * 1.6) * 1.5
