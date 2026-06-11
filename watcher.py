#!/usr/bin/env python3
"""쇼핑 사이트 새 매물 감시 → 디스코드 알림 (다중 소스).

config.json 의 watches 항목마다 해당 소스에서 검색 결과를 가져와,
seen.json 에 기록된 '이전에 본 상품 ID'와 비교해 새 매물만 디스코드로 보낸다.
표준 라이브러리만 사용(설치 불필요).

소스(source):
  - bunjang    : 번개장터 (공개 JSON API)
  - japanq     : 재팬큐 구매대행 (shop 지정: mercari/rakuten/yhshop/amazon_jp/yhauc)
  - amazon_us  : 아마존 US (best-effort, 봇차단 시 그냥 건너뜀)
"""
import gzip
import html as html_mod
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import zlib

STATE_FILE = "seen.json"
CONFIG_FILE = "config.json"
MAX_SEEN = 1000  # watch 별로 기억할 상품 ID 최대 개수

UA_MOBILE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
             "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1")
UA_DESKTOP = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
UA_SAFARI = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
             "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")


# ---------------------------------------------------------------- HTTP helpers
def _read(resp):
    raw = resp.read()
    enc = (resp.headers.get("Content-Encoding") or "").lower()
    if enc == "gzip":
        raw = gzip.decompress(raw)
    elif enc == "deflate":
        raw = zlib.decompress(raw)
    return raw.decode("utf-8", "replace")


def http_get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {"User-Agent": UA_DESKTOP})
    with urllib.request.urlopen(req, timeout=30) as r:
        return _read(r)


def http_post(url, data, headers=None):
    body = urllib.parse.urlencode(data).encode()
    h = {"User-Agent": UA_DESKTOP,
         "X-Requested-With": "XMLHttpRequest",
         "Content-Type": "application/x-www-form-urlencoded"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=body, headers=h)
    with urllib.request.urlopen(req, timeout=30) as r:
        return _read(r)


# ---------------------------------------------------------------- 번개장터
def fetch_bunjang(w):
    kw = urllib.parse.quote(w["keyword"])
    url = ("https://api.bunjang.co.kr/api/1/find_v2.json?q=%s&order=date"
           "&page=0&n=100&stat_device=w&req_ref=search&version=4" % kw)
    data = json.loads(http_get(url, {"User-Agent": UA_MOBILE}))
    items = []
    for it in data.get("list", []):
        if it.get("ad"):
            continue  # 광고 상품 제외
        pid = str(it.get("pid"))
        img = (it.get("product_image") or "").replace("{res}", "300")
        items.append({
            "id": "bunjang:%s" % pid,
            "name": it.get("name", ""),
            "price": int(it.get("price") or 0),
            "currency": "₩",
            "img": img,
            "link": "https://m.bunjang.co.kr/products/%s" % pid,
        })
    return items


# ---------------------------------------------------------------- 재팬큐
_PUSH_RE = re.compile(r"\.push\((\{.*?\})\);", re.DOTALL)


def _jq_field(obj, key):
    m = re.search(r"%s\s*:\s*'((?:[^'\\]|\\.)*)'" % key, obj)
    return m.group(1).strip() if m else ""


def fetch_japanq(w):
    shop = w["shop"]
    endpoint = "/parse/auction" if shop == "yhauc" else "/parse/index"
    data = {
        "shop_id": shop, "keyword": w["keyword"], "sort": "5",  # 5 = 신상품순
        "skin": "", "now_level": "", "link_code": "", "lo": "", "select": "",
        "stock": "", "delivery": "", "review": "", "low": "", "high": "",
        "category": "", "seller": "", "main_keyword": w["keyword"],
        "ad": "", "is_condition": "", "listing": "", "goods_limit": "",
        "old_page": "", "urlString": "",
    }
    html = http_post("https://japanq.co.kr" + endpoint, data)
    items = []
    for m in _PUSH_RE.finditer(html):
        obj = m.group(1)
        shop_url = urllib.parse.unquote(_jq_field(obj, "shop_url"))
        if not shop_url:
            continue
        tail = html[m.end():m.end() + 1500]
        wm = re.search(r"window\.open\('([^']+)'", tail)
        link = shop_url
        if wm and wm.group(1).startswith("/"):
            link = "https://japanq.co.kr" + wm.group(1)
        try:
            price = int(_jq_field(obj, "price") or 0)
        except ValueError:
            price = 0
        items.append({
            "id": "japanq:%s:%s" % (shop, shop_url),
            "name": _jq_field(obj, "name"),
            "price": price,
            "currency": "¥",
            "img": _jq_field(obj, "imgs"),
            "link": link,
        })
    return items


# ---------------------------------------------------------------- 아마존 US
def fetch_amazon_us(w):
    url = "https://www.amazon.com/s?k=" + urllib.parse.quote_plus(w["keyword"])
    doc = http_get(url, {"User-Agent": UA_DESKTOP,
                         "Accept-Language": "en-US,en;q=0.9",
                         "Accept-Encoding": "gzip, deflate"})
    low = doc.lower()
    if "validatecaptcha" in low or "not a robot" in low or "api-services-support" in low:
        raise RuntimeError("아마존 봇차단(캡차)")
    items, seen = [], set()
    matches = list(re.finditer(r'data-asin="([A-Z0-9]{10})"', doc))
    for i, m in enumerate(matches):
        asin = m.group(1)
        if asin in seen:
            continue
        seen.add(asin)
        end = matches[i + 1].start() if i + 1 < len(matches) else m.start() + 4000
        seg = doc[m.start():end]
        am = re.search(r'<img[^>]*class="s-image"[^>]*alt="([^"]{4,})"', seg)
        if not am:
            continue
        name = re.sub(r"^Sponsored Ad - ", "", am.group(1).strip())
        pm = re.search(r'<span class="a-offscreen">\$([0-9,]+\.?\d*)</span>', seg)
        im = re.search(r"(https://m\.media-amazon\.com/images/[^\s\"]+\.jpg)", seg)
        items.append({
            "id": "amazon_us:%s" % asin,
            "name": html_mod.unescape(name),
            "price": int(float(pm.group(1).replace(",", ""))) if pm else 0,
            "currency": "$",
            "img": im.group(1) if im else "",
            "link": "https://www.amazon.com/dp/%s" % asin,
        })
    return items


# ---------------------------------------------------------------- 중고나라 (joongna)
_JN_PROD = re.compile(r'href="/product/(\d+)"')


def fetch_joongna(w):
    url = ("https://web.joongna.com/search/"
           + urllib.parse.quote(w["keyword"]) + "?sortType=2")  # 2 = 최신순
    doc = http_get(url, {"User-Agent": UA_DESKTOP, "Accept-Language": "ko-KR,ko;q=0.9"})
    items, seen = [], set()
    matches = list(_JN_PROD.finditer(doc))
    for i, m in enumerate(matches):
        pid = m.group(1)
        if pid in seen:
            continue
        seen.add(pid)
        end = matches[i + 1].start() if i + 1 < len(matches) else m.start() + 2000
        seg = doc[m.start():end]
        am = re.search(r'alt="([^"]*?)\s*이미지"', seg)
        im = re.search(r'src="(https://img2\.joongna\.com[^"]+)"', seg)
        pm = re.search(r"([0-9]{1,3}(?:,[0-9]{3})+)\s*(?:</span>\s*<span[^>]*>\s*)?원", seg)
        name = am.group(1).strip() if am else ""
        if not name:
            continue
        items.append({
            "id": "joongna:%s" % pid,
            "name": html_mod.unescape(name),
            "price": int(pm.group(1).replace(",", "")) if pm else 0,
            "currency": "₩",
            "img": im.group(1) if im else "",
            "link": "https://web.joongna.com/product/%s" % pid,
        })
    return items


# ---------------------------------------------------------------- 이베이 US
def fetch_ebay_us(w):
    url = ("https://www.ebay.com/sch/i.html?_nkw="
           + urllib.parse.quote_plus(w["keyword"]) + "&_sop=10")  # 10 = 신규 등록순
    doc = http_get(url, {
        "User-Agent": UA_SAFARI,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "gzip, deflate",
        "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Site": "none",
        "Upgrade-Insecure-Requests": "1",
    })
    if "pardon our interruption" in doc.lower() or "are you a human" in doc.lower():
        raise RuntimeError("이베이 봇차단")
    items, seen = [], set()
    matches = list(re.finditer(r"https://www\.ebay\.com/itm/(\d+)", doc))
    for i, m in enumerate(matches):
        iid = m.group(1)
        if iid in seen:
            continue
        seen.add(iid)
        end = matches[i + 1].start() if i + 1 < len(matches) else m.start() + 3000
        seg = doc[m.start():end]
        am = re.search(r'<img[^>]*alt="([^"]{4,})"', seg)
        name = re.sub(r"\s+\d{6,}$", "", am.group(1).strip()) if am else ""
        if not name:
            continue
        im = re.search(r'(https://i\.ebayimg\.com/[^\s"]+\.(?:jpg|webp|png))', seg)
        pm = re.search(r"\$([0-9][0-9,]*\.?\d*)", seg)
        items.append({
            "id": "ebay_us:%s" % iid,
            "name": html_mod.unescape(name),
            "price": int(float(pm.group(1).replace(",", ""))) if pm else 0,
            "currency": "$",
            "img": im.group(1) if im else "",
            "link": "https://www.ebay.com/itm/%s" % iid,
        })
    return items


SOURCES = {
    "bunjang": fetch_bunjang,
    "japanq": fetch_japanq,
    "joongna": fetch_joongna,
    "amazon_us": fetch_amazon_us,
    "ebay_us": fetch_ebay_us,
}


# ---------------------------------------------------------------- 디스코드
def _post_json(url, payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()


def send_discord(webhook, items, label):
    for i in range(0, len(items), 10):
        chunk = items[i:i + 10]
        embeds = []
        for it in chunk:
            price = "%s%s" % (it["currency"], format(it["price"], ",")) if it["price"] else "-"
            e = {"title": (it["name"] or "(제목 없음)")[:240], "url": it["link"],
                 "fields": [{"name": "가격", "value": price, "inline": True}],
                 "footer": {"text": label}}
            if it.get("img"):
                e["thumbnail"] = {"url": it["img"]}
            embeds.append(e)
        payload = {"embeds": embeds}
        if i == 0:
            payload["content"] = "🆕 새 매물 %d건 — %s" % (len(items), label)
        _post_json(webhook, payload)
        time.sleep(1)


# ---------------------------------------------------------------- 디스코드 명령
DISCORD_API = "https://discord.com/api/v10"

# 채팅에서 쓰는 사이트 별칭 → (source, shop)
SOURCE_ALIASES = {
    "번개": ("bunjang", None), "번개장터": ("bunjang", None),
    "중고나라": ("joongna", None), "중고": ("joongna", None),
    "메루카리": ("japanq", "mercari"), "메루": ("japanq", "mercari"), "mercari": ("japanq", "mercari"),
    "라쿠텐": ("japanq", "rakuten"), "rakuten": ("japanq", "rakuten"),
    "야후쇼핑": ("japanq", "yhshop"),
    "아마존재팬": ("japanq", "amazon_jp"), "아마존jp": ("japanq", "amazon_jp"),
    "야후옥션": ("japanq", "yhauc"), "야옥": ("japanq", "yhauc"),
    "아마존": ("amazon_us", None), "아마존us": ("amazon_us", None),
    "이베이": ("ebay_us", None), "ebay": ("ebay_us", None),
}
HELP_TEXT = ("📖 명령어\n"
             "`추가 <사이트> <키워드>`  예) `추가 번개 구찌 마몬트 지갑`\n"
             "`삭제 <번호>`  (번호는 목록에서 확인)\n"
             "`목록`  현재 감시 목록 보기\n"
             "사이트: 번개 · 중고나라 · 메루카리 · 라쿠텐 · 야후쇼핑 · 아마존재팬 · 야후옥션 · 아마존 · 이베이")


def reply(webhook, text):
    try:
        _post_json(webhook, {"content": text})
    except Exception as e:
        print("답장 실패:", e)


def discord_get_messages(token, channel_id, after):
    url = "%s/channels/%s/messages?limit=100" % (DISCORD_API, channel_id)
    if after:
        url += "&after=%s" % after
    req = urllib.request.Request(url, headers={
        "Authorization": "Bot %s" % token, "User-Agent": "shopping-watch"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(_read(r))


def handle_command(text, config, webhook):
    parts = text.split()
    if not parts:
        return False
    cmd = parts[0]
    if cmd in ("추가", "add"):
        if len(parts) < 3 or parts[1] not in SOURCE_ALIASES:
            reply(webhook, "사용법: `추가 <사이트> <키워드>`\n" + HELP_TEXT)
            return False
        source, shop = SOURCE_ALIASES[parts[1]]
        w = {"source": source, "keyword": " ".join(parts[2:])}
        if shop:
            w["shop"] = shop
        config["watches"].append(w)
        reply(webhook, "✅ 추가됨: [%s] `%s` — 다음 실행(최대 30분)부터 감시합니다." % (parts[1], w["keyword"]))
        return True
    if cmd in ("삭제", "remove", "del"):
        ws = config["watches"]
        if len(parts) < 2 or not parts[1].isdigit():
            reply(webhook, "사용법: `삭제 <번호>` — 번호는 `목록`으로 확인")
            return False
        idx = int(parts[1]) - 1
        if 0 <= idx < len(ws):
            removed = ws.pop(idx)
            reply(webhook, "🗑️ 삭제됨: `%s`" % removed.get("keyword", ""))
            return True
        reply(webhook, "그 번호는 없어요. `목록`으로 확인하세요.")
        return False
    if cmd in ("목록", "list"):
        ws = config["watches"]
        if not ws:
            reply(webhook, "감시 목록이 비어 있어요. `추가`로 등록하세요.")
            return False
        lines = ["📋 감시 목록"]
        for i, w in enumerate(ws, 1):
            tag = w["source"] + ("/" + w["shop"] if w.get("shop") else "")
            lines.append("%d. [%s] %s" % (i, tag, w["keyword"]))
        reply(webhook, "\n".join(lines))
        return False
    if cmd in ("도움", "help", "명령어"):
        reply(webhook, HELP_TEXT)
        return False
    return False  # 명령이 아닌 일반 메시지는 무시


def process_commands(config, state, webhook):
    """디스코드 명령 채널을 읽어 키워드 추가/삭제 처리. config 변경 시 True."""
    token = os.environ.get("DISCORD_BOT_TOKEN")
    channel = os.environ.get("DISCORD_CHANNEL_ID")
    if not token or not channel:
        return False  # 명령 기능 미설정 → 알림만 동작
    after = state.get("_cmd_last_id")
    try:
        msgs = discord_get_messages(token, channel, after)
    except Exception as e:
        print("명령 읽기 실패:", e)
        return False
    if not msgs:
        return False
    if after is None:
        # 첫 실행: 기존 메시지는 명령으로 처리하지 않고 기준점만 저장
        state["_cmd_last_id"] = str(max(int(m["id"]) for m in msgs))
        return True
    changed = False
    for m in sorted(msgs, key=lambda x: int(x["id"])):
        state["_cmd_last_id"] = m["id"]
        if m.get("author", {}).get("bot"):
            continue
        if handle_command((m.get("content") or "").strip(), config, webhook):
            changed = True
    return True  # 메시지를 읽어 처리 포인터(_cmd_last_id)가 갱신됨


# ---------------------------------------------------------------- main
def watch_label(w):
    src = w["source"]
    if src == "japanq":
        return "japanq·%s · %s" % (w["shop"], w["keyword"])
    return "%s · %s" % (src, w["keyword"])


def watch_key(w):
    return "%s|%s|%s" % (w["source"], w.get("shop", ""), w["keyword"])


def main():
    webhook = os.environ.get("DISCORD_WEBHOOK_URL")
    if not webhook:
        print("DISCORD_WEBHOOK_URL 미설정 — 알림 보낼 곳이 없어 이번엔 건너뜁니다. (시크릿 등록하면 동작)")
        return

    with open(CONFIG_FILE, encoding="utf-8") as f:
        config = json.load(f)
    state = {}
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding="utf-8") as f:
            state = json.load(f)

    changed = False

    # 디스코드 명령 처리 (키워드 추가/삭제/목록) → config 변경 시 저장
    if process_commands(config, state, webhook):
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
        changed = True

    for w in config["watches"]:
        label = watch_label(w)
        fn = SOURCES.get(w["source"])
        if not fn:
            print("[%s] 알 수 없는 source — 건너뜀" % label)
            continue
        try:
            items = fn(w)
        except Exception as e:
            print("[%s] 수집 실패 — %s" % (label, e))
            continue

        pmin, pmax = w.get("price_min") or 0, w.get("price_max") or 0
        if pmin:
            items = [it for it in items if it["price"] >= pmin]
        if pmax:
            items = [it for it in items if it["price"] <= pmax]

        key = watch_key(w)
        current = [it["id"] for it in items]
        seen = state.get(key)

        if seen is None:
            state[key] = current[:MAX_SEEN]
            changed = True
            print("[%s] 첫 실행 — %d건 시드(알림 생략)" % (label, len(current)))
            time.sleep(2)
            continue

        seen_set = set(seen)
        new_items = [it for it in items if it["id"] not in seen_set]
        if new_items:
            send_discord(webhook, new_items, label)
            print("[%s] 새 매물 %d건 알림" % (label, len(new_items)))
        else:
            print("[%s] 새 매물 없음 (%d건 확인)" % (label, len(items)))

        merged = current + [i for i in seen if i not in set(current)]
        state[key] = merged[:MAX_SEEN]
        changed = True
        time.sleep(2)

    if changed:
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
    print("완료")


if __name__ == "__main__":
    main()
