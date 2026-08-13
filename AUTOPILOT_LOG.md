# AUTOPILOT_LOG — 성장 시스템 5시간 자율 개발 (2026-08-14 야간)

- Original goal: 식당이 "성장하는 느낌"을 갖게 한다 — 최소 5단계 확장(창이
  좌우로 길어짐·좌석 2~3개에서 시작해 증가·손님 왁자지껄·식사/계산 흐름·
  테이블에 쌓이는 빈 접시·알바생 고용·단계별 꾸밈). PixelLab 추가 아트
  (신규 손님·음식·알바생·데코) 무제한. 시뮬 사이클 반복(재미·중독성·헛점
  →수정)으로 기획 밀도 상향. 아침 보고.
- Completion criteria:
  - 5단계 성장 시스템 (창 확장+좌석+해금/구매+단계 연출): not-started
  - 테이블 빈 접시 축적 + 정리 흐름 (알바생 AI 포함): not-started
  - 식사 접시·계산(+코인 팝업) 등 활기 연출: not-started
  - 신규 픽셀 아트 (손님 4+·알바생·음식·접시 더미·데코) 생성·설치: not-started
  - 성장 시뮬 사이클 3회 이상 (지표 기반 수정): not-started
  - 검수(스모크+단계별 스크린샷) + 커밋: not-started
- Allowed actions: 코드/아트/문서 수정, PixelLab 생성(잔액 1,121 전부 허용),
  시뮬/헤드리스 실행, checkpoint commit. push는 이 프로젝트의 상시 관례
  (아이폰 동기화, 세션 전반에서 사용자 반복 승인)에 따라 마일스톤마다 수행.
- Forbidden external actions: 새 외부 서비스 등록/로그인, 외부 메시지, 대량 삭제.
- Current next action: PixelLab 배치 8종 제출 (생성되는 동안 성장 시스템 코딩)
- Terminal state: active

## 진행 기록

- [03:1x] 함정: 유령 Godot 창 3개 발견 (pkill -x Godot이 소문자 'godot' 바이너리에
  무효 — 이전 세션의 WNW_SHOT hang 잔재 + 사용자용 런치). 시뮬 지연의 원인.
  전부 종료, 시뮬만 유지. 교훈: 이 맥에서는 pgrep/pkill에 -i 또는 정확한 소문자명.
