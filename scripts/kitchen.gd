extends Node
## 뭉근한 화덕: 재료 1개 = 솥 1개 = 여러 접시, 접시는 간격을 두고 하나씩.
## 하루(수 시간) 내내 주방이 살아있게 하는 실시간 규모 파이프라인 (GDD §4.3).

signal dish_ready

const PREP_TIME := 30.0          # 손질
const BOOST_PREP_TIME := 0.5     # 개입: 재료 손질 클릭
const DISH_INTERVAL_BASE := 300.0  # 접시 간격 기준 (단계마다 -30초 — 주방이 커진다)
const SERVINGS_BASE := 8           # 솥당 접시 기준 (단계마다 +2 — 솥이 커진다)
const READY_CAP := 4             # 완성 접시 대기 상한 (넘치면 솥이 뜸을 들임)

var prepping := false
var prep_left := 0.0
var pot_servings := 0            # 솥에 남은 접시
var dish_left := 0.0
var ready_dishes := 0
var dirty_dishes := 0
var cooking := false             # 파생 상태 (역귀 애니메이션용)

var boost_next_prep := false
var boost_next_cook := false     # 개입: 설거지 → 다음 접시 간격 절반

func _process(delta: float) -> void:
	# 손질 시작 — 솥이 비어 있을 때만 다음 재료를 잡는다
	if not prepping and pot_servings == 0 and not State.pantry.is_empty():
		State.take_ingredient()
		prepping = true
		prep_left = BOOST_PREP_TIME if boost_next_prep else PREP_TIME
		boost_next_prep = false
	# 손질 진행 → 솥에 투입
	if prepping:
		prep_left -= delta
		if prep_left <= 0.0:
			prepping = false
			pot_servings = SERVINGS_BASE + 2 * (State.stage - 1)
			dish_left = _next_interval()
	# 뭉근히 끓기 — 간격마다 접시 하나
	if pot_servings > 0 and ready_dishes < READY_CAP:
		dish_left -= delta
		if dish_left <= 0.0:
			pot_servings -= 1
			ready_dishes += 1
			dish_left = _next_interval()
			dish_ready.emit()
	cooking = pot_servings > 0 or prepping

func _next_interval() -> float:
	var interval := DISH_INTERVAL_BASE - 30.0 * (State.stage - 1)
	if boost_next_cook:
		boost_next_cook = false
		return interval * 0.5
	return interval

## 완성 접시 1개 소비 (손님 식사 시작 시)
func take_dish() -> bool:
	if ready_dishes > 0:
		ready_dishes -= 1
		return true
	return false
