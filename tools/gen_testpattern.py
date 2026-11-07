#!/usr/bin/env python3
"""生成 sRGB 标准色块测试图（1920x1080，无 ICC 配置），用于投屏色偏比对。

判读方法：
  1) 纯色块 R/G/B/Y/C/M —— 电视明显更艳 = 饱和度被推高
  2) 灰阶 0..255 九级 —— 两端的格子并成一片 = 量程错配（limited/full）
  3) 近黑 0/4/8/16/24 与近白 255/247/239/235/228 —— 能分辨几格说明量程正常
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = (128, 128, 128)

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]


def load_font(size):
    for f in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(f, size)
        except Exception:
            continue
    return ImageFont.load_default()


F_PATCH = load_font(34)
F_TITLE = load_font(28)

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)


def patch(x, y, w, h, rgb, label):
    d.rectangle([x, y, x + w, y + h], fill=rgb, outline=(0, 0, 0))
    col = (255, 255, 255) if sum(rgb) < 380 else (0, 0, 0)
    d.text((x + 12, y + h - 52), label, fill=col, font=F_PATCH)


# ---- 1. 原色 / 间色 ----
prim = [
    ((255, 0, 0), "R 255,0,0"),
    ((0, 255, 0), "G 0,255,0"),
    ((0, 0, 255), "B 0,0,255"),
    ((255, 255, 0), "Y 255,255,0"),
    ((0, 255, 255), "C 0,255,255"),
    ((255, 0, 255), "M 255,0,255"),
]
pw, ph = 296, 300
gap = (W - pw * 6) // 7
for i, (rgb, lab) in enumerate(prim):
    patch(gap + i * (pw + gap), 56, pw, ph, rgb, lab)

# ---- 2. 灰阶 9 级 ----
levels = [0, 32, 64, 96, 128, 160, 192, 224, 255]
gw = (W - 120) // 9
for i, v in enumerate(levels):
    patch(60 + i * gw, 410, gw - 6, 180, (v, v, v), f"{v}")

# ---- 3. 近黑 / 近白 ----
nears_black = [0, 4, 8, 16, 24]
nw = 170
for i, v in enumerate(nears_black):
    patch(60 + i * (nw + 10), 640, nw, 150, (v, v, v), f"{v}")

nears_white = [228, 235, 239, 247, 255]
for i, v in enumerate(nears_white):
    patch(W - 60 - (5 - i) * (nw + 10) + 10, 640, nw, 150, (v, v, v), f"{v}")

# ---- 4. 肤色 / 中性参考 ----
skin = [(224, 172, 140), (241, 194, 170), (198, 134, 106)]
for i, c in enumerate(skin):
    patch(60 + i * 190, 840, 180, 180, c, f"skin{i + 1}")

patch(W - 60 - 190, 840, 180, 180, (118, 118, 118), "18% gray")
patch(W - 60 - 400, 840, 180, 180, (255, 255, 255), "white")
patch(W - 60 - 610, 840, 180, 180, (0, 0, 0), "black")

d.text((60, 12), "sRGB TEST PATTERN  1920x1080  no ICC profile", fill=(255, 255, 255), font=F_TITLE)

img.save("spectest.png", "PNG", optimize=True)  # 不写 ICC，避免被色彩管理
print("spectest.png", img.size)
