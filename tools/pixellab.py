#!/usr/bin/env python3
"""PixelLab API — 리소스 생성·수신.

토큰은 리포에 두지 않는다: 환경변수 PIXELLAB_TOKEN 또는 ~/.config/pixellab/token.

  python3 tools/pixellab.py balance
  python3 tools/pixellab.py items --size 32 --view sidescroller --desc "설명" ...
  python3 tools/pixellab.py object8 --desc "설명" [--style 파일.png | --ref 파일.png]
  python3 tools/pixellab.py select <object_id> --indices 7      # 후보 중 하나 고르기
  python3 tools/pixellab.py states <object_id> --edit "설명" --name hurt1
  python3 tools/pixellab.py resize 원본.png 결과.png --desc "설명" --to 24x24
  python3 tools/pixellab.py edit 원본.png 결과.png --desc "이렇게 고쳐" --guidance 9
  python3 tools/pixellab.py fetch <object_id> <출력폴더>

생성은 비동기다(작업 제출 → object_id). fetch 로 진행 상황을 보고 완성되면 받는다.
PixelLab 은 지정 해상도의 진짜 픽셀 그리드로 뽑으므로 import_ai_art.py 의 격자 복원
단계가 필요 없다 — fetch 는 알파 이진화와 팔레트 검사만 한다.
"""
import argparse
import base64
import json
import os
import pathlib
import time
import urllib.error
import urllib.request

from PIL import Image

BASE = "https://api.pixellab.ai/v2"


def token() -> str:
    t = os.environ.get("PIXELLAB_TOKEN", "").strip()
    if t:
        return t
    p = pathlib.Path.home() / ".config/pixellab/token"
    if p.exists():
        return p.read_text().strip()
    raise SystemExit("토큰 없음 — PIXELLAB_TOKEN 또는 ~/.config/pixellab/token")


def call(path: str, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method or ("POST" if data else "GET"),
        headers={"Authorization": "Bearer " + token(),
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode()[:600]}")


def b64_image(path: str) -> dict:
    raw = pathlib.Path(path).read_bytes()
    return {"type": "base64", "base64": base64.b64encode(raw).decode(),
            "format": "png"}


def show_usage(r: dict) -> None:
    u = r.get("usage") or {}
    print(f"  비용: {u.get('generations', u.get('usd'))} ({u.get('type')})")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance")

    pi = sub.add_parser("items", help="1방향 오브젝트 — 크기가 작으면 한 번에 여러 개")
    pi.add_argument("--size", type=int, default=32)
    pi.add_argument("--view", default="sidescroller",
                    choices=["top-down", "sidescroller"])
    pi.add_argument("--desc", nargs="+", required=True)
    pi.add_argument("--style", nargs="*", default=[],
                    help="스타일 참조 PNG (넣으면 size 는 무시되고 참조 크기가 출력 크기)")

    po = sub.add_parser("object8", help="8방향 오브젝트 — 반측면 앞/뒤를 여기서 고른다")
    po.add_argument("--desc", required=True)
    po.add_argument("--size", type=int, default=64)
    po.add_argument("--view", default="low top-down",
                    choices=["low top-down", "high top-down", "side"])
    g = po.add_mutually_exclusive_group()
    g.add_argument("--style", help="이 그림의 화풍으로 새 오브젝트를 만든다")
    g.add_argument("--ref", help="이 그림 그대로 8방향을 만든다")

    pa = sub.add_parser("animate", help="기존 오브젝트에 애니메이션 추가")
    pa.add_argument("object_id")
    pa.add_argument("--desc", required=True, help="동작 설명 (예: 'oozing forward')")
    pa.add_argument("--name", required=True, help="상태 이름 (walk/attack …)")
    pa.add_argument("--frames", type=int, default=4,
                    help="짝수 4~16 만 허용 — 결과 PNG 는 시작 프레임이 더해져 +1장")
    pa.add_argument("--group", help="기존 애니메이션에 방향을 이어 붙일 때 animation_group_id")
    pa.add_argument("--dirs", nargs="+",
                    default=["south", "south-west", "west", "north-west", "north"],
                    help="애니메이션할 방향 — 왼쪽 면만 쓰므로 기본값이 5방향")

    ps = sub.add_parser("select", help="후보 여러 장 중 남길 것을 골라 완성 오브젝트로")
    ps.add_argument("object_id")
    ps.add_argument("--indices", nargs="+", type=int, required=True)

    pt = sub.add_parser("states", help="완성 오브젝트에서 상태(표정·열림 등) 파생")
    pt.add_argument("object_id")
    pt.add_argument("--edit", required=True, help="무엇을 바꿀지 (같은 인물·물건 유지)")
    pt.add_argument("--name", required=True, help="상태 이름 (hurt1/open …)")

    pr = sub.add_parser("resize", help="픽셀 그리드를 다시 그려 크기 변경 (16~200px)")
    pr.add_argument("src")
    pr.add_argument("dst")
    pr.add_argument("--desc", required=True)
    pr.add_argument("--to", required=True, help="WxH")
    pr.add_argument("--view", default="side",
                    choices=["side", "low top-down", "high top-down"])

    ped = sub.add_parser("edit", help="그림 한 장을 설명대로 고친다 (팔레트 유지)")
    ped.add_argument("src")
    ped.add_argument("dst")
    ped.add_argument("--desc", required=True)
    ped.add_argument("--guidance", type=float, default=6.0, help="설명을 따르는 정도 1~10")
    ped.add_argument("--seed", type=int)

    prot = sub.add_parser("rotate", help="그림 한 장을 다른 방향에서 본 모습으로")
    prot.add_argument("src")
    prot.add_argument("dst")
    prot.add_argument("--from-dir", default="south")
    prot.add_argument("--to-dir", required=True)
    prot.add_argument("--view", default="side",
                      choices=["side", "low top-down", "high top-down"])
    prot.add_argument("--guidance", type=float, default=3.0,
                      help="원본을 얼마나 따를지 (1~20)")

    pf = sub.add_parser("fetch")
    pf.add_argument("object_id")
    pf.add_argument("outdir")

    a = ap.parse_args()

    if a.cmd == "balance":
        print(json.dumps(call("/balance"), ensure_ascii=False, indent=2))
        return

    if a.cmd == "items":
        body = {"description": a.desc[0], "view": a.view}
        if len(a.desc) > 1:
            body["item_descriptions"] = a.desc
        if a.style:
            body["style_images"] = [b64_image(p) for p in a.style]
        else:
            body["size"] = a.size
        r = call("/create-1-direction-object", body)
        print("object_id:", r.get("object_id"), " 후보 프레임:", r.get("n_frames"),
              " 상태:", r.get("status"))
        show_usage(r)
        return

    if a.cmd == "object8":
        body = {"description": a.desc, "view": a.view}
        if a.ref:
            body["reference_image"] = b64_image(a.ref)
        elif a.style:
            body["style_image"] = b64_image(a.style)
        else:
            body["size"] = a.size
        r = call("/create-8-direction-object", body)
        print("object_id:", r.get("object_id"), " 상태:", r.get("status"))
        show_usage(r)
        return

    if a.cmd == "animate":
        body = {"mode": "v3", "animation_description": a.desc, "directions": a.dirs,
                "display_name": a.name, "frame_count": a.frames}
        if a.group:
            body["animation_group_id"] = a.group
        r = call(f"/objects/{a.object_id}/animations", body)
        print("animation_group_id:", r.get("animation_group_id"),
              " 프레임", r.get("frame_count"), " 방향", len(a.dirs))
        show_usage(r)
        return

    if a.cmd == "select":
        r = call(f"/objects/{a.object_id}/select-frames", {"indices": a.indices})
        print("새 오브젝트:", r.get("created_object_ids"))
        show_usage(r)
        return

    if a.cmd == "states":
        r = call(f"/objects/{a.object_id}/states",
                 {"edit_description": a.edit, "state_name": a.name})
        print("object_id:", r.get("object_id"), " 상태:", r.get("status"))
        show_usage(r)
        return

    if a.cmd == "resize":
        w, h = (int(v) for v in a.to.lower().split("x"))
        src = Image.open(a.src)
        r = call("/resize", {
            "description": a.desc, "view": a.view,
            "reference_image": b64_image(a.src),
            "reference_image_size": {"width": src.width, "height": src.height},
            "target_size": {"width": w, "height": h}})
        dst = pathlib.Path(a.dst)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(base64.b64decode(r["image"]["base64"]))
        print(f"{a.dst}  {src.width}x{src.height} → {w}x{h}")
        show_usage(r)
        return

    if a.cmd == "edit":
        src = Image.open(a.src)
        body = {"image": b64_image(a.src), "color_image": b64_image(a.src),
                "image_size": {"width": src.width, "height": src.height},
                "width": src.width, "height": src.height,
                "description": a.desc, "text_guidance_scale": a.guidance,
                "no_background": True}
        if a.seed is not None:
            body["seed"] = a.seed
        r = call("/edit-image", body)
        job = r["background_job_id"] # 비동기다 — 끝날 때까지 물어본다
        for _ in range(60):
            time.sleep(3)
            j = call(f"/background-jobs/{job}")
            if j.get("status") in ("completed", "succeeded", "done"):
                break
            if j.get("status") in ("failed", "error"):
                raise SystemExit(f"실패: {j}")
        img = (j.get("last_response") or {}).get("image")
        if not img:
            raise SystemExit(f"이미지 없음: {json.dumps(j)[:400]}")
        raw = base64.b64decode(img["base64"])
        dst = pathlib.Path(a.dst)
        dst.parent.mkdir(parents=True, exist_ok=True)
        if raw[:8] == b"\x89PNG\r\n\x1a\n":
            dst.write_bytes(raw)
        else: # 이 엔드포인트는 PNG 가 아니라 생 RGBA 바이트를 준다
            Image.frombytes("RGBA", (src.width, src.height), raw).save(dst)
        print(f"{a.dst}  {src.width}x{src.height}")
        show_usage(j)
        return

    if a.cmd == "rotate":
        src = Image.open(a.src)
        r = call("/rotate", {
            "from_image": b64_image(a.src), "color_image": b64_image(a.src),
            "image_size": {"width": src.width, "height": src.height},
            "from_view": a.view, "to_view": a.view,
            "from_direction": a.from_dir, "to_direction": a.to_dir,
            "image_guidance_scale": a.guidance})
        dst = pathlib.Path(a.dst)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(base64.b64decode(r["image"]["base64"]))
        print(f"{a.dst}  {a.from_dir} → {a.to_dir}  {src.width}x{src.height}")
        show_usage(r)
        return

    # fetch — 진행 상황 확인 후 완성분 내려받기
    o = call(f"/objects/{a.object_id}")
    print(f"{o.get('name')} | 상태 {o.get('status')} {o.get('progress_percent')}%"
          f" | 크기 {o.get('size')} | 방향 {o.get('directions')}"
          f" | eta {o.get('eta_seconds')}s")
    urls = {}
    for key in ("rotation_urls", "frame_urls"): # storage_urls 는 frame_urls 와 동일
        v = o.get(key)
        if isinstance(v, dict):
            urls.update({f"{key[:3]}-{k}": u for k, u in v.items() if u})
        elif isinstance(v, list):
            urls.update({f"{key[:3]}-{i:02d}": u for i, u in enumerate(v) if u})
    for anim in (o.get("animations") or []):
        nm = anim.get("display_name") or "anim"
        for d in (anim.get("directions") or []):
            dn = d.get("direction", "?")
            for i, u in enumerate((d.get("storage_urls") or {}).get("frames") or []):
                if u:
                    urls[f"anim-{nm}-{dn}-{i:02d}"] = u
    if not urls: # states 로 만든 1장짜리 오브젝트는 여기에만 이미지가 있다
        urls.update({f"img-{k}": u
                     for k, u in (o.get("storage_urls") or {}).items() if u})
    if not urls:
        print("아직 받을 이미지가 없다 (생성 중이면 잠시 뒤 다시)")
        return
    out = pathlib.Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    got = 0
    for name, url in sorted(urls.items()):
        dst = out / f"{name}.png"
        try: # 아직 안 만들어진 프레임은 403/404 — 건너뛴다 (생성이 순차 진행된다)
            # 스토리지가 기본 urllib UA 를 거부한다 — UA 를 붙여야 200 이 온다
            rq = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
            with urllib.request.urlopen(rq) as r:
                dst.write_bytes(r.read())
            got += 1
        except (urllib.error.HTTPError, urllib.error.URLError):
            dst.unlink(missing_ok=True)
    print(f"{got}/{len(urls)}장 저장 → {out}")


if __name__ == "__main__":
    main()
