# 쇼핑 새 매물 감시 → 디스코드 알림

여러 쇼핑 사이트에서 원하는 키워드의 **새 매물이 올라오면 디스코드로 알림**을 보내는 도구입니다.
GitHub Actions에서 **무료로 30분마다 자동 실행**됩니다. (내 컴퓨터를 켜둘 필요 없음)

## 지원 소스 (config.json 의 `source`)

| source | 사이트 | 안정성 |
|---|---|---|
| `bunjang` | 번개장터 | 🟢 안정 |
| `japanq` | 재팬큐 구매대행 (`shop`: mercari / rakuten / yhshop / amazon_jp / yhauc) | 🟢 안정 |
| `joongna` | 중고나라 (web.joongna.com) | 🟡 best-effort |
| `amazon_us` | 아마존 US | 🟡 best-effort (가끔 차단/가격 누락) |
| `ebay_us` | 이베이 US | 🟡 best-effort (가끔 차단) |

🟡 는 사이트가 막거나 개편하면 일시적으로 안 될 수 있습니다. 그래도 다른 소스엔 영향 없습니다.

---

## 설치 (한 번만)

### 1. 디스코드 웹훅 만들기
1. 알림 받을 디스코드 **서버 → 채널 설정(톱니) → 연동 → 웹후크 → 새 웹후크**
2. **웹후크 URL 복사** (`https://discord.com/api/webhooks/...`)

### 2. GitHub 저장소 만들기
1. github.com 에서 새 저장소(repository) 생성 (Private 가능)
2. 이 폴더의 파일 전부 업로드 (`watcher.py`, `config.json`, `seen.json`, `.github/workflows/watch.yml`, `README.md`)

### 3. 웹훅 URL 을 비밀값으로 등록
저장소 **Settings → Secrets and variables → Actions → New repository secret**
- Name: `DISCORD_WEBHOOK_URL`
- Secret: (1번에서 복사한 웹훅 URL)

### 4. 감시할 키워드 설정
`config.json` 의 `watches` 를 원하는 대로 수정 (GitHub 웹에서 파일 열어 ✏️ 편집 가능):

```json
{ "source": "bunjang", "keyword": "찾는 키워드", "price_max": 300000 }
```
- `price_min` / `price_max` 는 그 사이트 통화 기준(번개·중고나라=원, japanq=엔, 아마존·이베이=달러). 생략 가능.
- japanq 는 `"shop"` 도 넣어야 함 (위 표 참고). 일본 사이트라 **일본어 키워드**가 결과가 많음.

### 5. 자동 실행 켜기
- 저장소 **Actions 탭 → 워크플로우 활성화**
- `shopping-watch` 워크플로우 → **Run workflow** 로 수동 1회 실행 (첫 실행은 "현재 매물 기억"만 하고 알림은 안 보냄)
- 이후 **30분마다 자동 실행**되며, 새 매물이 생기면 디스코드로 알림이 옵니다.

---

## 동작 방식
- 각 watch 의 검색 결과를 신상품순으로 가져와 상품 ID를 `seen.json` 에 기록.
- 다음 실행 때 `seen.json` 에 없던 **새 ID만** 디스코드로 전송.
- 첫 실행은 알림 없이 현재 목록만 저장(폭탄 방지).

## 주기 바꾸기
`.github/workflows/watch.yml` 의 `cron: '*/30 * * * *'` 에서 `30` 을 원하는 분으로. (너무 짧으면 사이트 부담/차단 위험 — 10분 이상 권장)
