extends Node2D
## P1 뼈대 — 픽셀 퍼펙트 스트립 창 + 실시간 미러링 스텁.
## 논리 해상도 640×180 고정, 기준 배율 2x (전역 픽셀 원칙: 배율 혼용 금지).

@onready var sky: ColorRect = $Sky
@onready var clock_label: Label = $UI/ClockLabel

func _ready() -> void:
	_tick()
	var t := Timer.new()
	t.wait_time = 10.0
	t.timeout.connect(_tick)
	add_child(t)
	t.start()

func _tick() -> void:
	var d := Time.get_datetime_dict_from_system()
	clock_label.text = "%02d:%02d" % [d.hour, d.minute]
	sky.color = _sky_color(d.hour)

## 실시간 미러링: 게임 하늘이 실제 시각을 따른다 (GDD §3.4-②).
## 균일 틴트만 사용 — 그라데이션·페더 금지 (픽셀 원칙 8).
func _sky_color(hour: int) -> Color:
	if hour >= 22 or hour < 5:
		return Color8(24, 26, 44)    # 밤
	elif hour < 8:
		return Color8(120, 96, 110)  # 새벽·아침놀
	elif hour < 17:
		return Color8(130, 170, 200) # 낮
	elif hour < 20:
		return Color8(190, 120, 80)  # 노을
	else:
		return Color8(60, 56, 80)    # 초저녁
