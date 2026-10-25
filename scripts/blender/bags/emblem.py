"""S.T.A.R.S. 隊徽（經典臂章：上方弧形布條＋下方圓章）。全部用程式畫，輸出 1024 px 透明底 PNG。
  uv run --with numpy --with pillow --with scipy python emblem.py <輸出.png> [對照圖輸出.png]
幾何照 capcomdb 平面圖量（temp/bags/emblem_measure.py）：設計座標以圓章外緣半徑為 1、圓心為原點、v 朝下。
那張圖垂直方向被拉長（圓章外緣寬 312 px、高 328 px），這裡照官方琺瑯徽章畫成正圓；對照圖會把設計拉回那張圖的比例再疊。
顏色取官方琺瑯徽章實物照（official-enamel-pin.jpg）的中位數：深藍 (23,29,55)、黃 (253,177,6)、白 (229,228,227)。
字型 Cabin Bold（Johnston／Gill 一路的人文無襯線，最接近原圖粗圓的大寫；SIL OFL 1.1，授權全文 scripts/blender/fonts/OFL-Cabin.txt）。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as nd

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "fonts", "Cabin[wdth,wght].ttf")
NAVY, YELLOW, WHITE = (23, 29, 55), (253, 177, 6), (229, 228, 227)
U0, V0, SPAN = 0.0, -0.33, 2.8          # 畫布中心與邊長（設計單位）：u −1.4～1.4、v −1.73～1.07
SS = 4                                   # 超取樣倍數

# 圓章（半徑，由外往內）：深藍描邊、白邊、深藍外圈（字）、白線、深藍內圈（星）
R_OUT, R_WHITE, R_RING, R_LINE, R_DISK = 1.0, 0.964, 0.921, 0.636, 0.600
# 弧形布條：上緣圓（圓心 (0, 0.304)、半徑 1.882）、下緣圓（(0, 0.142)、1.288）、兩側直線（v=−1.207 時 u=±1.096，du/dv=−0.338）
BAN_TOP, BAN_BOT = (0.304, 1.882), (0.142, 1.288)
BAN_SIDE = (1.096, -1.207, -0.338)
BAN_WHITE, BAN_OUTLINE, BAN_HALO = 0.040, 0.040, 0.045   # 白邊、深藍描邊、和圓章之間的白縫
# S.T.A.R.S.：字中心（u, v）照量到的位置，字頭朝弧心 (0, 0.611) 的反方向；字高 0.33；句點是圓點
STARS_ARC, STARS_H = 0.611, 0.33
STARS_GLYPHS = [("S", -0.845, -1.128), ("T", -0.512, -1.300), ("A", -0.031, -1.322), ("R", 0.478, -1.291), ("S", 0.859, -1.122)]
STARS_DOTS, STARS_DOT_R = [(-0.619, -1.067), (-0.312, -1.168), (0.241, -1.181), (0.646, -1.072), (0.916, -0.934)], 0.038
# 外圈字：順時針、字頭朝外、字中心在半徑 0.785，字高 0.23；角度＝從正上方順時針（度），照量到的每個字
RING_R, RING_H = 0.785, 0.23
RING_GLYPHS = [("R", -52.5), ("A", -35.0), ("C", -17.5), ("C", 0.0), ("O", 17.5), ("O", 35.0), ("N", 52.5),
               ("P", 104.7), ("O", 121.0), ("L", 136.5), ("I", 149.5), ("C", 163.0), ("E", 179.0),
               ("D", 231.4), ("E", 248.0), ("P", 264.2)]
RING_DOTS, DOT_R = (84.0, 208.0), 0.038
# 三顆星：凸包找 5 個尖、相鄰尖之間最靠近重心的邊界點當凹點（照 capcomdb 圖量，星的形狀本來就不規則）
STARS = [
    [(0.113, -0.091), (-0.214, -0.165), (-0.445, 0.098), (-0.394, -0.201), (-0.541, -0.262), (-0.362, -0.366),
     (-0.297, -0.573), (-0.176, -0.476), (0.081, -0.585), (-0.067, -0.341)],
    [(0.497, 0.268), (0.286, 0.049), (0.023, 0.152), (0.171, -0.098), (0.023, -0.311), (0.279, -0.25),
     (0.408, -0.427), (0.427, -0.189), (0.594, -0.116), (0.478, -0.049)],
    [(0.267, 0.39), (0.113, 0.409), (0.094, 0.543), (-0.035, 0.402), (-0.291, 0.402), (-0.131, 0.305),
     (-0.214, 0.11), (0.004, 0.207), (0.158, 0.134), (0.145, 0.299)],
]


def _grid(n):
    s = (np.arange(n) + 0.5) / n
    return np.meshgrid(U0 + (s - 0.5) * SPAN, V0 + (s - 0.5) * SPAN)


def _banner_mask(u, v):
    top = np.hypot(u, v - BAN_TOP[0]) <= BAN_TOP[1]
    bot = np.hypot(u, v - BAN_BOT[0]) >= BAN_BOT[1]
    u0, v0, k = BAN_SIDE
    side = np.abs(u) <= u0 + k * (v - v0)
    return top & bot & side & (v < 0)


def _font(cap_px):
    """Cabin Bold，大寫 H 高＝cap_px。"""
    f = ImageFont.truetype(FONT, 1000)
    f.set_variation_by_axes([700, 100])   # 軸順序：Weight、Width
    l, t, r, b = f.getbbox("H")
    f = ImageFont.truetype(FONT, max(1, int(round(cap_px * 1000 / (b - t)))))
    f.set_variation_by_axes([700, 100])
    return f


def _px(cu, cv, n):
    return (cu - U0) / SPAN * n + n / 2, (cv - V0) / SPAN * n + n / 2


def _glyph(img, ch, cu, cv, height, angle_deg, color, n):
    """在設計座標 (cu, cv) 畫一個字（字框中心對齊）：大寫高＝height，順時針轉 angle_deg（0＝正立）。"""
    font = _font(height / SPAN * n)
    l, t, r, b = font.getbbox(ch)
    g = Image.new("L", (r - l + 8, b - t + 8), 0)
    ImageDraw.Draw(g).text((4 - l, 4 - t), ch, font=font, fill=255)
    g = g.crop(g.getbbox()).rotate(-angle_deg, resample=Image.BICUBIC, expand=True)
    x, y = _px(cu, cv, n)
    img.paste(Image.new("RGBA", g.size, color + (255,)), (int(round(x - g.width / 2)), int(round(y - g.height / 2))), g)


def _dot(d, cu, cv, rad, color, n):
    x, y = _px(cu, cv, n)
    rd = rad / SPAN * n
    d.ellipse([x - rd, y - rd, x + rd, y + rd], fill=color + (255,))


def draw(size=1024):
    n = size * SS
    u, v = _grid(n)
    px = SPAN / n
    rr = np.hypot(u, v)
    rgba = np.zeros((n, n, 4), np.uint8)

    def fill(mask, col):
        rgba[mask] = col + (255,)

    # 圓章
    fill(rr <= R_OUT, NAVY)
    fill(rr <= R_WHITE, WHITE)
    fill(rr <= R_RING, NAVY)
    fill(rr <= R_LINE, WHITE)
    fill(rr <= R_DISK, NAVY)
    img = Image.fromarray(rgba, "RGBA")
    d = ImageDraw.Draw(img)
    for poly in STARS:
        d.polygon([_px(pu, pv, n) for pu, pv in poly], fill=YELLOW + (255,))
    for ch, a in RING_GLYPHS:
        t = np.radians(a)
        _glyph(img, ch, RING_R * np.sin(t), -RING_R * np.cos(t), RING_H, a, WHITE, n)
    for a in RING_DOTS:
        t = np.radians(a)
        _dot(d, RING_R * np.sin(t), -RING_R * np.cos(t), DOT_R, WHITE, n)
    # 布條：疊在圓章上；由外往內白縫、深藍描邊、白邊、深藍底
    rgba = np.array(img)
    fillm = _banner_mask(u, v)
    dist = nd.distance_transform_edt(~fillm) * px
    for w, col in ((BAN_WHITE + BAN_OUTLINE + BAN_HALO, WHITE), (BAN_WHITE + BAN_OUTLINE, NAVY), (BAN_WHITE, WHITE)):
        m = dist <= w
        if col == WHITE and w > BAN_WHITE + BAN_OUTLINE:
            m &= rr <= R_OUT   # 白縫只蓋在圓章上，不往外長
        rgba[m] = col + (255,)
    rgba[fillm] = NAVY + (255,)
    img = Image.fromarray(rgba, "RGBA")
    for ch, cu, cv in STARS_GLYPHS:
        _glyph(img, ch, cu, cv, STARS_H, np.degrees(np.arctan2(cu, STARS_ARC - cv)), WHITE, n)
    d = ImageDraw.Draw(img)
    for cu, cv in STARS_DOTS:
        _dot(d, cu, cv, STARS_DOT_R, WHITE, n)
    return img.resize((size, size), Image.LANCZOS)


def compare(img, out):
    """左：capcomdb 參考圖；中：我們的（拉成參考圖的比例）；右：疊圖（參考圖半透明在下、我們的輪廓在上）；下排：官方琺瑯徽章照片。"""
    REF = "D:/github/MinidoracatServerPatchFor42/temp/bags-design/stars-emblem/refs/"
    ref = Image.open(REF + "capcomdb-STARSBadge.webp").convert("RGB")
    W, H = ref.size
    CX, CY, SX, SY = 190.4, 278.0, 156.0, 164.0   # 參考圖的設計座標換算（emblem_measure.py）
    # 我們的圖：設計座標 → 參考圖像素
    n = img.width
    sx = SX * SPAN / n
    sy = SY * SPAN / n
    ours = img.resize((int(round(n * sx)), int(round(n * sy))), Image.LANCZOS)
    ox = CX - (0 - U0 + SPAN / 2) / SPAN * ours.width
    oy = CY - (0 - V0 + SPAN / 2) / SPAN * ours.height
    on_ref = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    on_ref.paste(ours, (int(round(ox)), int(round(oy))), ours)
    a = np.asarray(ref).astype(float)
    o = np.asarray(on_ref.convert("RGB")).astype(float)
    edges = np.asarray(on_ref.convert("L").filter(__import__("PIL.ImageFilter", fromlist=["x"]).FIND_EDGES)) > 60
    ov = a * 0.55 + 255 * 0.45
    ov[edges] = (230, 0, 0)
    k = 2
    sheet = Image.new("RGB", (W * 3 * k, H * k + 40 + 520), (40, 40, 40))
    for i, im_ in enumerate((ref, on_ref.convert("RGB"), Image.fromarray(ov.astype(np.uint8)))):
        sheet.paste(im_.resize((W * k, H * k), Image.LANCZOS), (i * W * k, 40))
    pin = Image.open(REF + "official-enamel-pin.jpg").convert("RGB").crop((180, 420, 820, 1160))
    pin = pin.resize((int(pin.width * 520 / pin.height), 520))
    sheet.paste(pin, (0, H * k + 40))
    sq = Image.new("RGB", (520, 520), (110, 140, 175))
    tr = img.resize((520, 520), Image.LANCZOS)
    sq.paste(tr, (0, 0), tr)
    sheet.paste(sq, (pin.width + 20, H * k + 40))
    dr = ImageDraw.Draw(sheet)
    lab = ["capcomdb reference", "ours (stretched to reference aspect)", "overlay: reference + ours edges (red)"]
    for i, t in enumerate(lab):
        dr.text((i * W * k + 8, 10), t, fill=(255, 255, 255))
    dr.text((8, H * k + 44), "official enamel pin", fill=(255, 255, 255))
    dr.text((pin.width + 28, H * k + 44), "ours (true circle, 1024 px, on denim-ish blue)", fill=(0, 0, 0))
    sheet.save(out)


if __name__ == "__main__":
    im = draw(1024)
    im.save(sys.argv[1])
    if len(sys.argv) > 2:
        compare(im, sys.argv[2])
