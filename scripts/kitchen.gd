extends Node
## 자동 파이프라인: 재료 → (자동) 손질 → (자동) 조리 → 완성 접시 (GDD §4.3).
## 방치가 기본값 — 개입 부스트는 순수 가속 보너스.

signal dish_ready
signal stage_changed

const PREP_TIME := 4.0
const COOK_TIME := 6.0
const BOOST_PREP_TIME := 0.5   # 개입: 재료 손질 클릭
const BOOST_COOK_MULT := 0.5   # 개입: 설거지 클릭 (다음 조리 가속)

var prepping := false
var cooking := false
var prep_left := 0.0
var cook_left := 0.0
var prepped_count := 0
var ready_dishes := 0
var dirty_dishes := 0

var boost_next_prep := false
var boost_next_cook := false

func _process(delta: float) -> void:
	# 손질 시작
	if not prepping and not State.pantry.is_empty():
		State.take_ingredient()
		prepping = true
		prep_left = BOOST_PREP_TIME if boost_next_prep else PREP_TIME
		boost_next_prep = false
		stage_changed.emit()
	# 손질 진행
	if prepping:
		prep_left -= delta
		if prep_left <= 0.0:
			prepping = false
			prepped_count += 1
			stage_changed.emit()
	# 조리 시작
	if not cooking and prepped_count > 0:
		prepped_count -= 1
		cooking = true
		cook_left = COOK_TIME * (BOOST_COOK_MULT if boost_next_cook else 1.0)
		boost_next_cook = false
		stage_changed.emit()
	# 조리 진행
	if cooking:
		cook_left -= delta
		if cook_left <= 0.0:
			cooking = false
			ready_dishes += 1
			dish_ready.emit()
			stage_changed.emit()

## 완성 접시 1개 소비 (손님 식사 시작 시)
func take_dish() -> bool:
	if ready_dishes > 0:
		ready_dishes -= 1
		stage_changed.emit()
		return true
	return false
