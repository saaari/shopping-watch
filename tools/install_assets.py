#!/usr/bin/env python3
"""PixelLab 후보를 골라 res/ 에 설치한다.

  python3 tools/install_assets.py picks.json

picks.json 항목: {"res": "출력명", "src": "art/.../fra-07.png", "group": "hearth"}
- 같은 group 은 공통 bbox 하나로 크롭한다 (상태 전환 시 그림이 안 흔들리게).
- group 없으면 각자 투명 여백 크롭. 리샘플은 절대 하지 않는다 (픽셀 무가공).
- 알파는 이진화(128 미만 버림, 이상 255) — 페더 금지 원칙.
"""
import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "res"


def binarize(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v >= 128 else 0)
    im.putalpha(a)
    return im


def main() -> None:
    picks = json.loads(pathlib.Path(sys.argv[1]).read_text())
    RES.mkdir(exist_ok=True)
    groups: dict[str, list[dict]] = {}
    for p in picks:
        groups.setdefault(p.get("group") or p["res"], []).append(p)

    for gname, items in groups.items():
        images = [(p, binarize(Image.open(ROOT / p["src"]))) for p in items]
        boxes = [im.getbbox() for _, im in images]
        boxes = [b for b in boxes if b]
        if not boxes:
            print(f"SKIP {gname}: 전부 빈 이미지")
            continue
        # 그룹 공통 bbox (union)
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes),
               max(b[2] for b in boxes), max(b[3] for b in boxes))
        for p, im in images:
            out = RES / f"{p['res']}.png"
            im.crop(box).save(out)
            print(f"{p['src']} -> {out.relative_to(ROOT)} "
                  f"{box[2]-box[0]}x{box[3]-box[1]}")


if __name__ == "__main__":
    main()
