# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""背包一鍵重建（設定在 bags.py）：Tripo 高模 → 低模、貼圖、男女（ALT）穿戴與左右手 .X、地面 FBX、圖示。
  uv run scripts/blender/bags/build.py DayPack                     # 建到 temp/bags/DayPack/out/media，跑 verify_x
  uv run scripts/blender/bags/build.py DayPack --install <media>   # 驗證通過後複製進 <media>（MOD 的 42/media 或 temp 副本）
中間產物在 temp/bags/<款>/；verify_x.py 任一項失敗就中止，不安裝。
變體（bags.py variant_of）不重新烘焙：原款低模剛體搬到新擺法，只產出、安裝男女穿戴 .X（貼圖、圖示、地面模型沿用原款）。
"""
import os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

import bags
from common import BLENDER, HERE, out, temp
import stage2_assemble
import verify_x


def blender(script, name):
    subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, script), "--", name], check=True)


def icon(src, dst):
    """原版圖示風格：32×32 透明底、物體約 28 px、1 px 深色外框（抄 Knox Pass scripts/blender/build.py icon()）。"""
    im = Image.open(src).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    s = 28.0 / max(im.size)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    a = im.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    im = ImageEnhance.Sharpness(ImageEnhance.Color(ImageEnhance.Contrast(im.convert("RGB")).enhance(1.35)).enhance(1.3)).enhance(1.4)
    im = ImageEnhance.Brightness(im).enhance(1.35)   # 深藍在物品欄的深色底上幾乎看不見（第一版實機）；拉亮只動圖示，不動模型貼圖
    im.putalpha(a)
    canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    canvas.paste(im, ((32 - im.width) // 2, (32 - im.height) // 2), im)
    mask = canvas.getchannel("A")
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (32, 32), (28, 26, 24, 255)), (0, 0), mask.filter(ImageFilter.MaxFilter(3)))
    out.paste(canvas, (0, 0), mask)
    out.save(dst)


def relocate(name):
    """變體：原款低模（.X 空間）從原款擺法搬到變體擺法。兩邊都是 back 擺法、同高度、不後傾 → 平移底 y0 與背面 back_z；
    side="front" 是繞 y 轉 180°（x、z 取負，det>0，繞序不變），所以先轉回背後、平移、再照變體轉。UV 與面不動。"""
    cfg = bags.get(name)
    base = cfg["variant_of"]
    Pb, Pv = bags.get(base)["place"], cfg["place"]
    assert Pb["mode"] == Pv["mode"] == "back" and Pb["height"] == Pv["height"] and not Pb["lean"] and not Pv["lean"], "變體只支援同高度、不後傾的 back 擺法"
    d = dict(np.load(os.path.join(temp(base), "low_body.npz")))
    V, turn = d["V"].copy(), np.array([-1.0, 1.0, -1.0])
    if Pb.get("side") == "front":
        V *= turn
    V += [0, Pv["y0"] - Pb["y0"], Pv["back_z"] - Pb["back_z"]]
    if Pv.get("side") == "front":
        V *= turn
    os.makedirs(temp(name), exist_ok=True)
    np.savez(os.path.join(temp(name), "low_body.npz"), **dict(d, V=V))


def main(name):
    OUT, TEMP = out(name), temp(name)
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    for f in ("emblem.json", "tex_Navy_plain.png"):   # 拿掉 emblem 設定後不留上一次的隊徽對照
        if os.path.exists(f"{TEMP}/{f}"):
            os.remove(f"{TEMP}/{f}")
    base = bags.get(name).get("variant_of")
    if base:
        if not os.path.exists(os.path.join(temp(base), "low_body.npz")):
            blender("stage1_bake.py", base)   # stage1 可重現（重跑原款 .X 與貼圖逐位元組相同）
        relocate(name)
    else:
        blender("stage1_bake.py", name)
    stage2_assemble.main(name)
    blender("stage3_blender.py", name)
    for look in () if base else ("Navy", "Olive"):
        icon(f"{TEMP}/icon_raw_{look}.png", f"{OUT}/textures/Item_MDB_{name}_{look}.png")
    fail, info = verify_x.check(name, OUT)
    for k, v in info.items():
        print(k, v)
    if fail:
        sys.exit("VERIFY FAIL\n" + "\n".join("  - " + m for m in fail))
    verify_x.selftest(name)   # 植入違規要被抓到，證明檢查本身沒壞
    print("VERIFY OK")
    if "--install" in sys.argv:
        dst = sys.argv[sys.argv.index("--install") + 1]
        sub = "models_X/Skinned/BackPacks" if base else ""   # 變體只裝穿戴 .X
        shutil.copytree(os.path.join(OUT, sub), os.path.join(dst, sub), dirs_exist_ok=True)
        print("installed ->", dst)


if __name__ == "__main__":
    main(sys.argv[1])
