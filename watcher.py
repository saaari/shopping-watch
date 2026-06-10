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
        print("DISCORD_WEBHOOK_URL 환경변수가 없습니다.")
        sys.exit(1)

    with open(CONFIG_FILE, encoding="utf-8") as f:
        config = json.load(f)
    state = {}
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding="utf-8") as f:
            state = json.load(f)

    changed = False
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
