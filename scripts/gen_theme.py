# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""強化版主題外觀產生器（2026-10-27 使用者裁定：80 種原版背包依網格合併成 22 種形狀，每種做 S.T.A.R.S.／保護傘兩件）。
  uv run scripts/gen_theme.py            # 寫 scripts/theme_shapes.json、44 張穿戴貼圖、44 個圖示、主題地面模型腳本（要 Blender）
  uv run scripts/gen_theme.py --check    # 重建到暫存目錄比對（遊戲更新後跑）：圖示以外逐位元組，圖示照 ICON_TOL 容差（見 main）
  uv run scripts/gen_theme.py --plain    # 只換色（不去字、不貼徽章），除錯用
做法（每種形狀一列，設定在 SHAPES）：
1. 底圖＝代表款（同網格裡最適合當底的那張原版貼圖）放大到主題邊長（common.TEX_SIZE：深藍 512、保護傘 256）。
2. 去字：erase 矩形內用周圍同類像素的調和補色蓋掉（Ivanov、HYDRO 之類）。
3. 換色：seeds 那一群顏色＝主布料，照相對亮度換成主題色；其他（背帶、扣具、灰黑部件）換成黑色尼龍（同 stage2 keep_paint）。
   keep 取色點的顏色群、和主布料裡亮過 keep_light 的（框架包的木頭）只降彩度、照原明暗；gain＝整張再乘的亮度（目前沒有款式用）。
4. 徽章：decal.apply 把隊徽／保護傘章（含黃黑警示條）照 3D 表面投影到 badge.seed 那一點，方向一定是正的（decal.py 檔頭）。
5. 圖示（使用者 2026-10-27 在設計稿頁面選 B）：主題貼圖貼回男版穿戴網格、拿掉繞過身體的背帶（icon_mesh），
   Blender 算圖（blender/bags/theme_icons.py），再照本 MOD 7 款的後製（build.icon）。icon_dir＝相機方向，icon_strap＝拿掉背帶。
6. 地面：原版地面模型腳本寫死 texture 的 4 種網格，各做兩個主題的模型腳本（MDB_ThemeGround.txt）。
theme_by_source：每個原版來源的每個 textureChoice 升級後用哪個主題（NAVY_SOURCES、OLIVE_SOURCES、COLOR_OLIVE，規則見 theme_of）。
"""
import json, os, re, subprocess, sys, tempfile

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "blender", "bags"))
import decal, emblem, xio  # noqa: E402
from build import icon as build_icon  # noqa: E402  本 MOD 7 款圖示的後製
from common import BLENDER, TEX_SIZE  # noqa: E402

MEDIA = os.path.join(REPO, "MOD", "MinidoracatBagsFor42", "Contents", "mods", "MinidoracatBagsFor42", "42", "media")
PZ = os.path.join(os.environ.get("PZ_PATH", r"D:\SteamLibrary\steamapps\common\ProjectZomboid"), "media")
MODULE = "MinidoracatBags"
THEMES = ("Navy", "Olive")
MANIFEST = os.path.join(HERE, "theme_shapes.json")
GROUND_SCRIPT = os.path.join(MEDIA, "scripts", "MDB_ThemeGround.txt")
ICON_TOL = (6, 24)   # 圖示重建容差：不透明範圍差幾個像素、兩邊都不透明處 RGB 差幾個色階（--check）
FRONT = (0.55, 1, 0.45)   # 穿在身體前面的（胸掛、背帶、前腰包）從前面拍圖示

# 主布料色取本 MOD 7 款貼圖的中位數（深藍 59,69,97；橄欖 90,85,63 偏亮一點，日行包卡其 133,120,88）；黑色尼龍的色偏
PALETTE = {
    "Navy": dict(main=np.array([59, 69, 97]) / 255, nylon=np.array([0.97, 0.99, 1.06])),
    "Olive": dict(main=np.array([96, 90, 64]) / 255, nylon=np.array([1.02, 1.01, 0.95])),
}

# ---- 22 種形狀 ----
# key＝代表款去掉 Base.；base＝代表款的哪個 textureChoice 當底圖；seeds＝主布料取色點 (u, v)；keep＝只降彩度的顏色群取色點；
# erase＝去字矩形 (u0, v0, u1, v1)；badge＝徽章：seed (u, v)＝外側面上一點，或 out＋hf（frame_out 自己找朝 out 的面）；h＝徽章高，.X 單位約公尺
SHAPES = [
    dict(mesh="m_duffelbag", icon_strap=True, icon_dir=(1, -0.5, 0.4), rep="Base.Bag_DuffelBag", base="clothes\\bag\\duffelbagblue", seeds=[(0.35, 0.25)],
         badge=dict(seed=(0.62, 0.2), h=0.045),   # 端蓋：左右兩半共用 UV，貼側面會出現兩個（一個左右反）
         members=["Base.Bag_BaseballBag", "Base.Bag_BreakdownBag", "Base.Bag_BurglarBag", "Base.Bag_DuffelBag", "Base.Bag_DuffelBagTINT",
                  "Base.Bag_FoodCanned", "Base.Bag_FoodSnacks", "Base.Bag_InmateEscapedBag", "Base.Bag_MedicalBag", "Base.Bag_Military",
                  "Base.Bag_MoneyBag", "Base.Bag_Police", "Base.Bag_SWAT", "Base.Bag_Sheriff", "Base.Bag_ShotgunBag", "Base.Bag_ShotgunDblBag",
                  "Base.Bag_ShotgunDblSawnoffBag", "Base.Bag_ShotgunSawnoffBag", "Base.Bag_TennisBag", "Base.Bag_ToolBag", "Base.Bag_WeaponBag",
                  "Base.Bag_WorkerBag"]),
    dict(mesh="m_clothsatchel", icon_strap=True, icon_dir=(1, -0.5, 0.3), rep="Base.Bag_ClothSatchel_Cotton", base="clothes\\bag\\clothsatchel_cotton", seeds=[(0.3, 0.5)],
         badge=dict(seed=(0.15, 0.75), h=0.03), ground="Satchel_Fishing_Ground", ground_tex="Bag_Satchel_Leather",
         members=["Base.Bag_ClothSatchel_Burlap", "Base.Bag_ClothSatchel_Cotton", "Base.Bag_ClothSatchel_Denim",
                  "Base.Bag_ClothSatchel_DenimBlack", "Base.Bag_ClothSatchel_DenimLight", "Base.Bag_HideSatchel"]),
    dict(mesh="m_riflecasecloth", icon_strap=True, rep="Base.Bag_RifleCaseCloth", base="clothes\\bag\\riflecasecloth_green", seeds=[(0.2, 0.5)],
         badge=dict(seed=(0.13, 0.4), h=0.03),
         members=["Base.Bag_RifleCaseCloth", "Base.Bag_RifleCaseCloth2", "Base.Bag_RifleCaseClothCamo", "Base.Bag_ShotgunCaseCloth",
                  "Base.Bag_ShotgunCaseCloth2"]),
    dict(mesh="m_satchel_new", icon_strap=True, rep="Base.Bag_Satchel_Leather", base="clothes\\bag\\Satchel_Leather", seeds=[(0.4, 0.4)],
         badge=dict(seed=(0.37, 0.4), h=0.035), ground="Satchel_Leather_Ground",
         members=["Base.Bag_Satchel_Fishing", "Base.Bag_Satchel_Leather", "Base.Bag_Satchel_Mail", "Base.Bag_Satchel_Medical",
                  "Base.Bag_Satchel_Military"]),
    dict(mesh="m_schoolbag", rep="Base.Bag_Schoolbag", base="clothes\\bag\\schoolbag_blue", seeds=[(0.1, 0.5)],
         badge=dict(seed=(0.35, 0.25), h=0.04),
         members=["Base.Bag_Schoolbag", "Base.Bag_Schoolbag_Kids", "Base.Bag_Schoolbag_Medical", "Base.Bag_Schoolbag_Patches",
                  "Base.Bag_Schoolbag_Travel"]),
    dict(mesh="m_alice_pack", rep="Base.Bag_ALICEpack", base="clothes\\bag\\alicepack_green", seeds=[(0.5, 0.3)],
         badge=dict(seed=(0.47, 0.33), h=0.045),
         members=["Base.Bag_ALICEpack", "Base.Bag_ALICEpack_Army", "Base.Bag_ALICEpack_DesertCamo", "Base.Bag_SurvivorBag"]),
    dict(mesh="m_alice_beltsus", icon_dir=FRONT, rep="Base.Bag_ALICE_BeltSus", base="clothes\\bag\\alice_beltsus_green", seeds=[(0.5, 0.5)],
         badge=dict(seed=(0.47, 0.825), h=0.038),   # 正面彈藥袋（原本貼在它的下角）袋面正中；使用者 2026-10-27：實機 25% 縮放下原本只有約 5 px
         members=["Base.Bag_ALICE_BeltSus", "Base.Bag_ALICE_BeltSus_Camo", "Base.Bag_ALICE_BeltSus_Green"]),
    dict(mesh="m_fannypactback", rep="Base.Bag_FannyPackBack", base="clothes\\bag\\fannypack", seeds=[(0.3, 0.3)],
         badge=dict(out=(0, 0, 1), hf=0.5, h=0.025),
         members=["Base.Bag_FannyPackBack", "Base.Bag_FannyPackBack_Hide", "Base.Bag_FannyPackBack_Tarp"]),
    dict(mesh="m_fannypackfront", icon_dir=FRONT, rep="Base.Bag_FannyPackFront", base="clothes\\bag\\fannypack", seeds=[(0.3, 0.3)],
         badge=dict(seed=(0.5, 0.65), h=0.025),
         members=["Base.Bag_FannyPackFront", "Base.Bag_FannyPackFront_Hide", "Base.Bag_FannyPackFront_Tarp"]),
    dict(mesh="m_sheetslingbag", rep="Base.Bag_SheetSlingBag", base="clothes\\bag\\sheetslingbag", seeds=[(0.8, 0.2)],
         badge=dict(seed=(0.43, 0.45), h=0.03),
         members=["Base.Bag_HideSlingBag", "Base.Bag_SheetSlingBag", "Base.Bag_TarpSlingBag"]),
    dict(mesh="m_bighikingbag", rep="Base.Bag_BigHikingBag", base="clothes\\bag\\bighikingbagblue", seeds=[(0.9, 0.6)],
         badge=dict(seed=(0.42, 0.5), h=0.04),
         members=["Base.Bag_BigHikingBag", "Base.Bag_BigHikingBag_Travel"]),
    dict(mesh="bob_chestrig", icon_dir=FRONT, rep="Base.Bag_ChestRig", base="clothes\\bag\\chestrig", seeds=[(0.5, 0.4)],
         badge=dict(out=(0, 0, -1), hf=0.75, h=0.032), ground="ChestRig_Ground",   # 胸前上方那片；胸掛在貼圖上只佔一小塊，徽章放大才看得到
         members=["Base.Bag_ChestRig", "Base.Bag_ChestRig_Tarp"]),
    dict(mesh="m_craftedframepack_lrg", rep="Base.Bag_CraftedFramepack_Large", base="clothes\\bag\\craftedframepack_lrg", seeds=[(0.2, 0.5)],
         keep_light=0.55, badge=dict(out=(0, 0, 1), hf=0.6, h=0.045),
         members=["Base.Bag_CraftedFramepack_Large", "Base.Bag_TarpFramepack_Large"]),
    dict(mesh="m_craftedframepack_small", rep="Base.Bag_CraftedFramepack_Small", base="clothes\\bag\\craftedframepack_small",
         seeds=[(0.3, 0.5)], keep_light=0.55, badge=dict(out=(0, 0, 1), hf=0.6, h=0.04),
         members=["Base.Bag_CraftedFramepack_Small", "Base.Bag_TarpFramepack_Small"]),
    dict(mesh="m_crudeleatherbag", rep="Base.Bag_CrudeLeatherBag", base="clothes\\bag\\crudeleatherbag", seeds=[(0.5, 0.7)],
         badge=dict(out=(0, 0, 1), hf=0.55, h=0.035),
         ground="CrudeLeatherBag_Ground", members=["Base.Bag_CrudeLeatherBag", "Base.Bag_CrudeTarpBag"]),
    dict(mesh="m_golfbag", icon_strap=True, icon_dir=(0.2, -1, 0.1), rep="Base.Bag_GolfBag", base="clothes\\bag\\golfbag_blue", seeds=[(0.3, 0.85)],
         erase=[(0.17, 0.035, 0.43, 0.135), (0.05, 0.215, 0.16, 0.555), (0.45, 0.215, 0.575, 0.565), (0.6, 0.17, 0.76, 0.235)],
         badge=dict(seed=(0.51, 0.45), h=0.035), members=["Base.Bag_GolfBag", "Base.Bag_GolfBag_Melee"]),
    dict(mesh="m_hikingbag", rep="Base.Bag_NormalHikingBag", base="clothes\\bag\\hikingbagblue", seeds=[(0.9, 0.25)],
         badge=dict(seed=(0.37, 0.72), h=0.04), members=["Base.Bag_HikingBag_Travel", "Base.Bag_NormalHikingBag"]),
    dict(mesh="m_hydrationbackpack", rep="Base.Bag_HydrationBackpack", base="clothes\\bag\\hydrationbackpack_blue", seeds=[(0.35, 0.4)],
         erase=[(0.22, 0.21, 0.43, 0.33)], badge=dict(seed=(0.33, 0.3), h=0.035),
         members=["Base.Bag_HydrationBackpack", "Base.Bag_HydrationBackpack_Camo"]),
    dict(mesh="m_satchel", icon_strap=True, rep="Base.Bag_Satchel", base="clothes\\bag\\satchel", seeds=[(0.6, 0.5)],
         badge=dict(seed=(0.5, 0.62), h=0.035), members=["Base.Bag_Satchel", "Base.Bag_SatchelPhoto"]),
    dict(mesh="m_craftedframepack_lrg2", rep="Base.Bag_CraftedFramepack_Large2", base="clothes\\bag\\craftedframepacl_lrg2",
         seeds=[(0.5, 0.75)], keep_light=0.55, badge=dict(out=(0, 0, 1), hf=0.6, h=0.045), members=["Base.Bag_CraftedFramepack_Large2"]),
    dict(mesh="m_craftedframepack_lrg3", rep="Base.Bag_CraftedFramepack_Large3", base="clothes\\bag\\craftedframepack_lrg3",
         seeds=[(0.5, 0.75)], keep_light=0.55, badge=dict(out=(0, 0, 1), hf=0.6, h=0.045), members=["Base.Bag_CraftedFramepack_Large3"]),
    dict(mesh="m_fishingbasket", icon_strap=True, rep="Base.Bag_FishingBasket", base="clothes\\bag\\fishingbasket", seeds=[(0.5, 0.5)],
         badge=dict(seed=(0.62, 0.45), h=0.035), members=["Base.Bag_FishingBasket"]),
]

# ---- 升級時的主題（使用者 2026-10-27 照設計稿建議）：先看來源分類，其他照那個 textureChoice 的顏色 ----
NAVY_SOURCES = {"Base.Bag_Police", "Base.Bag_Sheriff", "Base.Bag_SWAT"}   # 警用、警長、特警
OLIVE_SOURCES = {
    # 軍用、ALICE、迷彩、胸掛、槍盒
    "Base.Bag_Military", "Base.Bag_ALICEpack", "Base.Bag_ALICEpack_Army", "Base.Bag_ALICEpack_DesertCamo", "Base.Bag_SurvivorBag",
    "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICE_BeltSus_Camo", "Base.Bag_ALICE_BeltSus_Green", "Base.Bag_Satchel_Military",
    "Base.Bag_ChestRig", "Base.Bag_ChestRig_Tarp", "Base.Bag_RifleCaseCloth", "Base.Bag_RifleCaseCloth2", "Base.Bag_RifleCaseClothCamo",
    "Base.Bag_ShotgunCaseCloth", "Base.Bag_ShotgunCaseCloth2", "Base.Bag_HydrationBackpack_Camo",
    # 醫療
    "Base.Bag_MedicalBag", "Base.Bag_Satchel_Medical", "Base.Bag_Schoolbag_Medical",
    # 自製與天然材質（皮、獸皮、柳條、帆布、床單、自製布包）
    "Base.Bag_ClothSatchel_Burlap", "Base.Bag_ClothSatchel_Cotton", "Base.Bag_ClothSatchel_Denim", "Base.Bag_ClothSatchel_DenimBlack",
    "Base.Bag_ClothSatchel_DenimLight", "Base.Bag_HideSatchel", "Base.Bag_HideSlingBag", "Base.Bag_SheetSlingBag", "Base.Bag_TarpSlingBag",
    "Base.Bag_FannyPackBack_Hide", "Base.Bag_FannyPackBack_Tarp", "Base.Bag_FannyPackFront_Hide", "Base.Bag_FannyPackFront_Tarp",
    "Base.Bag_CraftedFramepack_Large", "Base.Bag_CraftedFramepack_Large2", "Base.Bag_CraftedFramepack_Large3",
    "Base.Bag_CraftedFramepack_Small", "Base.Bag_TarpFramepack_Large", "Base.Bag_TarpFramepack_Small", "Base.Bag_CrudeLeatherBag",
    "Base.Bag_CrudeTarpBag", "Base.Bag_FishingBasket", "Base.Bag_Satchel_Leather", "Base.Bag_Satchel_Fishing",
    "Base.Bag_Satchel", "Base.Bag_SatchelPhoto",   # 皮革側背包（三色都是皮）
}
COLOR_OLIVE = ("camo", "desert", "green", "khaki")   # 其他來源：綠、卡其、迷彩的那個顏色用保護傘


def theme_of(src, tex):
    if src in NAVY_SOURCES:
        return "Navy"
    if src in OLIVE_SOURCES:
        return "Olive"
    return "Olive" if any(w in tex.lower() for w in COLOR_OLIVE) else "Navy"


# ---- 讀原版 ----
def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return f.read().replace("\r\n", "\n")


def vanilla_items():
    """{完整 ID: 第一層欄位}（原版 generated/items）"""
    out = {}
    d = os.path.join(PZ, "scripts", "generated", "items")
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".txt"):
            continue
        t = re.sub(r"/\*.*?\*/", "", read(os.path.join(d, fn)), flags=re.S)
        module = None
        for m in re.finditer(r"^\s*module\s+(\w+)|^\s*item\s+(\w+)\s*\n\s*\{(.*?)\n\s*\}", t, re.S | re.M):
            if m.group(1):
                module = m.group(1)
                continue
            fields = {}
            depth = 0
            for line in m.group(3).split("\n"):
                f = re.match(r"^\s*(\w+)\s*=\s*(.*?),\s*$", line)
                if depth == 0 and f:
                    fields[f.group(1)] = f.group(2)
                depth += line.count("{") - line.count("}")
            out[f"{module}.{m.group(2)}"] = fields
    return out


def clothing(name):
    t = read(os.path.join(PZ, "clothing", "clothingItems", name + ".xml"))
    g = lambda k: re.findall(rf"<{k}>([^<]*)</{k}>", t)
    return dict(M=g("m_MaleModel")[0], tex=g("textureChoices"))


def png(rel):
    """原版貼圖路徑（clothes\\bag\\x，不分大小寫）→ 檔案"""
    d = os.path.join(PZ, "textures", *rel.replace("\\", "/").split("/")[:-1])
    want = rel.replace("\\", "/").split("/")[-1].lower() + ".png"
    for f in os.listdir(d):
        if f.lower() == want:
            return os.path.join(d, f)
    sys.exit(f"找不到原版貼圖 {rel}")


def model_path(xml_path):
    p = xml_path.replace("\\", "/")
    p = p[len("media/"):] if p.lower().startswith("media/") else "models_X/" + p
    d = os.path.join(PZ, os.path.dirname(p))
    b = os.path.basename(p).lower()
    for f in os.listdir(d):
        if f.lower() in (b, b + ".x"):
            return os.path.join(d, f)
    sys.exit(f"找不到網格 {xml_path}")


def read_mesh(path):
    """V、F、N、UV。部分原版 .X（書包等）法線與 UV 在 DeclData（DWORD 存 float）；女版水袋有兩個網格，挑和檔名同名的那個。"""
    t = open(path, encoding="latin-1", newline="").read()
    meshes = [(m.start(), m[1]) for m in re.finditer(r"\n\s*Mesh (\w+) \{", t)]
    stem = os.path.splitext(os.path.basename(path))[0].lower()
    start = next((p for p, n in meshes if n.lower() == stem), meshes[-1][0])
    ms, me = xio._block(t, start)
    sub = re.compile(r"\n\s*(MeshNormals|MeshTextureCoords|MeshMaterialList|DeclData|XSkinMeshHeader|SkinWeights)\b").search(t, ms, me).start()
    a = xio._nums(t[ms:sub])
    nv = int(a[0]); V = a[1:1 + 3 * nv].reshape(nv, 3)
    F = xio._faces(a, 2 + 3 * nv, int(a[1 + 3 * nv]))
    if re.compile(r"\n\s*DeclData\b").search(t, ms, me):
        s, e = xio._sub(t, ms, me, "DeclData")
        a = xio._nums(t[s:e])
        ne = int(a[0]); el = a[1:1 + 4 * ne].reshape(ne, 4).astype(int)
        size = {0: 1, 1: 2, 2: 3, 3: 4}
        nd_ = int(a[1 + 4 * ne])
        dw = a[2 + 4 * ne:2 + 4 * ne + nd_].astype(np.uint32).view(np.float32).astype(float).reshape(nv, -1)
        cols, k = {}, 0
        for typ, _, usage, idx in el:
            cols.setdefault((usage, idx), dw[:, k:k + size[typ]])
            k += size[typ]
        N, UV = cols[(3, 0)], cols[(5, 0)]
    else:
        s, e = xio._sub(t, ms, me, "MeshNormals"); a = xio._nums(t[s:e])
        nn = int(a[0]); NN = a[1:1 + 3 * nn].reshape(nn, 3); NF = xio._faces(a, 2 + 3 * nn, int(a[1 + 3 * nn]))
        N = np.zeros_like(V); N[F.ravel()] = NN[NF.ravel()]
        s, e = xio._sub(t, ms, me, "MeshTextureCoords"); a = xio._nums(t[s:e])
        UV = a[1:1 + 2 * int(a[0])].reshape(-1, 2)
    return dict(V=V, F=F, N=N, UV=UV)


# ---- 換色 ----
def lum(a):
    return a @ np.array([0.299, 0.587, 0.114])


def hsv(a):
    mx, mn = a.max(-1), a.min(-1)
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    return h, s, mx


def color_group(a, seeds, tol=0.09):
    """種子點附近最常見的顏色所在的群：有彩度的比色相，灰的比低彩度＋亮度。"""
    h, s, _ = hsv(a)
    L = lum(a)
    res = a.shape[0]
    m = np.zeros(a.shape[:2], bool)
    q = (a * 15).round().astype(int) @ np.array([256, 16, 1])
    for su, sv in seeds:
        y, x = min(int(sv * res), res - 1), min(int(su * res), res - 1)
        r = max(2, res // 64)
        y0, x0 = max(y - r, 0), max(x - r, 0)
        win = q[y0:y + r + 1, x0:x + r + 1]
        yy, xx = np.nonzero(win == np.bincount(win.ravel()).argmax())
        y, x = y0 + yy[0], x0 + xx[0]
        h0, s0, l0 = h[y, x], s[y, x], L[y, x]
        if s0 > 0.18:
            dh = np.abs(h - h0); dh = np.minimum(dh, 1 - dh)
            m |= (dh < tol) & (s > 0.45 * s0) & (L > 0.35 * l0)
        else:
            m |= (s < max(0.2, s0 + 0.08)) & (L > 0.55 * l0) & (L < 1.6 * l0 + 0.15)
    return nd.binary_opening(m, iterations=1) | (m & nd.binary_erosion(m))


def erase(a, rects, main, iters=400):
    """矩形內改成周圍同類像素（看外圈多數是主布料還是別的）的調和補色；矩形外 3 像素內不同類的（摺痕、描邊）一起補。回 (圖, 補過的主布料)。"""
    res = a.shape[0]
    out, holes = a.copy(), np.zeros(a.shape[:2], bool)
    rng = np.random.default_rng(1)
    for u0, v0, u1, v1 in rects:
        hole = np.zeros(a.shape[:2], bool)
        hole[int(v0 * res):int(np.ceil(v1 * res)), int(u0 * res):int(np.ceil(u1 * res))] = True
        ring = nd.binary_dilation(hole, iterations=3) & ~hole
        cls = main if main[ring].mean() >= 0.5 else ~main
        hole |= ring & ~cls
        _, (iy, ix) = nd.distance_transform_edt(hole | ~cls, return_indices=True)
        out[hole] = out[iy[hole], ix[hole]]
        for _ in range(iters):
            out[hole] = nd.uniform_filter(out, size=(3, 3, 1), mode="nearest")[hole]
        out[hole] = np.clip(out[hole] + rng.normal(0, 0.018, hole.sum())[:, None], 0, 1)   # 補回一點布紋
        if cls is main:
            holes |= hole
    return out, holes


def recolor(a, theme, main, keep=None):
    P = PALETTE[theme]
    L = lum(a)
    rel = L / max(float(np.median(L[main])) if main.any() else 0.5, 1e-3)
    fab = P["main"] * np.clip(rel, 0, 1)[..., None]
    fab = fab + (np.minimum(P["main"] * 1.9, 1) - P["main"]) * np.clip(rel - 1, 0, 1)[..., None] * 0.8
    out = np.where(main[..., None], fab, (L * 0.32 + 0.06)[..., None] * P["nylon"])
    if keep is not None:   # 只降彩度：灰階往主題色偏一點，照原明暗
        out[keep] = (L[keep, None] * 0.75 + 0.04) * (0.85 + 0.15 * P["main"] / P["main"].mean())
    return np.clip(out, 0, 1)


def umbrella(size=1024):
    """保護傘章：白底方章＋紅白相間八角（8 片），下方黃黑警示條（使用者 2026-10-27 選「八角章＋警示條」）。"""
    S = 4
    n = size * S
    H = int(n * 1.55)
    im = Image.new("RGBA", (n, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pad = n * 0.04
    d.rounded_rectangle([pad, pad, n - pad, n - pad], radius=n * 0.06, fill=(232, 228, 216, 255), outline=(40, 38, 34, 255), width=int(n * 0.025))
    c, r = n / 2, n * 0.36
    pts = [(c + r * np.cos(t), c + r * np.sin(t)) for t in np.deg2rad(np.arange(8) * 45 - 90 - 22.5)]
    for i in range(8):
        d.polygon([(c, c), pts[i], pts[(i + 1) % 8]], fill=(204, 28, 36, 255) if i % 2 == 0 else (245, 245, 240, 255))
    d.polygon(pts, outline=(150, 20, 26, 255), width=int(n * 0.012))
    y0, y1 = n * 1.12, n * 1.47
    stripe = Image.new("RGBA", (n, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stripe)
    sd.rectangle([pad, y0, n - pad, y1], fill=(236, 190, 20, 255))
    w, x = y1 - y0, pad - (y1 - y0)
    while x < n:
        sd.polygon([(x, y1), (x + w * 0.5, y1), (x + w * 1.5, y0), (x + w, y0)], fill=(24, 22, 20, 255))
        x += w
    clip = Image.new("L", (n, H), 0)
    ImageDraw.Draw(clip).rectangle([pad, y0, n - pad, y1], fill=255)
    im.paste(stripe, (0, 0), Image.fromarray(np.minimum(np.asarray(stripe.getchannel("A")), np.asarray(clip))))
    return im.resize((size, int(H / S)), Image.LANCZOS)


def frame_of(n0, p0):
    up = np.array([0.0, 1.0, 0.0]) if abs(n0[1]) < 0.9 else np.array([0.0, 0.0, -1.0])
    et = up - (up @ n0) * n0
    et /= np.linalg.norm(et)
    return dict(center=p0, normal=n0, up=et, right=np.cross(n0, et))


def frame_at(M, seed, res=512):
    """UV 點 (u, v) 在網格上的位置與面法線 → decal 用的 frame（上＝世界上方投影到表面）。"""
    V, F, UV, N = M["V"], M["F"], M["UV"], M["N"]
    ys, xs, fs, bs = decal.raster(V, F, UV, res)
    k = np.argmin((xs - seed[0] * res) ** 2 + (ys - seed[1] * res) ** 2)
    return frame_of(decal.face_normals(V, F, N)[fs[k]], bs[k] @ V[F[fs[k]]])


def frame_out(M, out, hf, xf=0.5):
    """朝 out 方向（.X 空間；+z＝角色背後）的外側面上一點：法線和 out 夾角 < 35° 的面裡，最靠外、
    高度在這些面的 hf、橫向在 xf 的那一面。框架包、胸掛這類 UV 島看不出朝向的用它，不用猜 UV 座標。"""
    V, F, N = M["V"], M["F"], M["N"]
    fn = decal.face_normals(V, F, N)
    od = np.array(out, float) / np.linalg.norm(out)
    cand = np.nonzero(fn @ od > 0.82)[0]
    C = V[F[cand]].mean(1)
    side = np.cross([0.0, 1.0, 0.0], od)
    s, y, depth = C @ side, C[:, 1], C @ od
    score = np.abs(y - (y.min() + hf * np.ptp(y))) + np.abs(s - (s.min() + xf * np.ptp(s))) - 0.6 * (depth - depth.max())
    k = cand[np.argmin(score)]
    return frame_of(fn[k], V[F[k]].mean(0))


_EMB = {}


def badge_art(theme):
    if theme not in _EMB:
        _EMB[theme] = emblem.draw(1024) if theme == "Navy" else umbrella(1024)
    return _EMB[theme]


def texture(shape, theme, plain=False):
    res = TEX_SIZE[theme]
    big = Image.open(png(shape["base"])).convert("RGBA").resize((res, res), Image.BICUBIC)
    alpha = np.asarray(big.getchannel("A"))
    a = np.clip(np.asarray(big.convert("RGB")).astype(float) / 255, 0, 1)
    main = color_group(a, shape["seeds"])
    hole = np.zeros(main.shape, bool)
    if not plain and shape.get("erase"):
        a, hole = erase(a, shape["erase"], main)
        main = color_group(a, shape["seeds"]) | hole
    keep = color_group(a, shape["keep"]) & ~main if shape.get("keep") else None
    if shape.get("keep_light"):   # 框架包的木頭和皮同色相、比較亮：亮過門檻的只降彩度
        wood = main & (lum(a) > shape["keep_light"])
        main, keep = main & ~wood, wood if keep is None else keep | wood
    tex = (np.clip(recolor(a, theme, main, keep) * shape.get("gain", 1.0), 0, 1) * 255).round().astype(np.uint8)
    b = shape.get("badge")
    if not plain and b:
        M = shape["_mesh"]
        fr = frame_at(M, b["seed"]) if "seed" in b else frame_out(M, b["out"], b["hf"], b.get("xf", 0.5))
        fr = dict(fr, old=np.zeros((res, res), bool))
        h = b["h"] * (1.55 if theme == "Olive" else 1.0)   # 保護傘章下面多一條警示條：章本身和隊徽一樣高
        tex, _, _ = decal.apply(tex, M["V"], M["F"], M["UV"], M["N"], fr, badge_art(theme), h)
    return Image.fromarray(np.dstack([tex, alpha]))


def icon_mesh(shape):
    """圖示只畫包本身：icon_strap 的款式（側背、斜背、手提類）拿掉繞過身體的背帶（伸到肩上 y ≥ 0.78、又繞到身體前面 z < −0.02 的連通塊），
    否則側背包、釣具籃會畫成一條長背帶加一個小包。背包類的肩帶和包身連在一起，從背後拍也被包身擋住，整件畫。"""
    V, F, UV = shape["_mesh"]["V"], shape["_mesh"]["F"], shape["_mesh"]["UV"]
    if not shape.get("icon_strap"):
        return V, F, UV
    q = np.unique(np.round(V / 1e-4).astype(np.int64), axis=0, return_inverse=True)[1].ravel()
    e = q[np.concatenate([F[:, [0, 1]], F[:, [1, 2]]])]
    n = q.max() + 1
    lab = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)), directed=False)[1][q]
    drop = [c for c in np.unique(lab) if V[lab == c, 1].max() >= 0.78 and V[lab == c, 2].min() < -0.02]
    keep = ~np.isin(lab, drop)
    if not drop or not keep.any():
        sys.exit(f"{shape['key']}: 找不到背帶，或整件都被當成背帶，先看網格的連通塊再改 icon_mesh")
    return V, F[keep[F].all(1)], UV


def render_icons(root, shapes, work):
    """Blender 算圖示原圖（blender/bags/theme_icons.py），再照本 MOD 7 款的後製（build.icon）存成 32×32。"""
    job = []
    for s in shapes:
        V, F, UV = icon_mesh(s)
        npz = os.path.join(work, s["key"] + ".npz")
        np.savez(npz, V=V, F=F, UV=UV)
        for th in THEMES:
            job.append(dict(npz=npz, dir=s.get("icon_dir", (0.55, -1, 0.45)), out=os.path.join(work, f"{s['key']}_{th}.png"),
                            tex=os.path.join(root, os.path.relpath(MEDIA, REPO), "textures", *tex_name(s["key"], th).split("/")) + ".png"))
    with open(os.path.join(work, "icons.json"), "w", encoding="utf-8") as f:
        json.dump(job, f)
    subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "blender", "bags", "theme_icons.py"), "--",
                    os.path.join(work, "icons.json")], check=True, stdout=subprocess.DEVNULL)
    out = []
    for s in shapes:
        for th in THEMES:
            p = os.path.join(root, os.path.relpath(MEDIA, REPO), "textures", f"Item_{icon_name(s['key'], th)}.png")
            build_icon(os.path.join(work, f"{s['key']}_{th}.png"), p)
            out.append(os.path.relpath(p, root))
    return out


# ---- 組裝 ----
def tex_name(key, theme):
    return f"Clothes/Bag/MDB_{key}_{theme}"


def icon_name(key, theme):
    return f"MDB_{key}_{theme}"


def ground_name(key, theme):
    return f"MDB_{key}_{theme}_Ground"


def vanilla_model(name):
    for fn in ("models_items.txt", "models_clothes.txt"):
        t = read(os.path.join(PZ, "scripts", "generated", fn))
        m = re.search(rf"\n(\s*)model {name}\s*\n\s*\{{(.*?)\n\1\}}", t, re.S)
        if m:
            return m.group(2)
    sys.exit(f"原版模型腳本找不到 {name}")


def ground_script(shapes):
    out = ["/* 由 scripts/gen_theme.py 產生，不要手改。強化版主題款放在地上的模型：原版這 4 種網格的地面模型腳本寫死 texture",
           "   （寫了 texture 就不看物品的貼圖，WorldItemAtlas.java:603-609），所以各做兩個主題。網格、縮放照抄原版。",
           "   布側背包照原版做法：地上是 Satchel_Fishing 網格（Satchel_New 的 UV），貼 Satchel_New 形狀的主題貼圖。 */",
           f"module {MODULE}", "{"]
    for s in shapes:
        if not s.get("ground"):
            continue
        body = vanilla_model(s["ground"])
        for th in THEMES:
            tex_key = s.get("ground_tex", s["key"])
            b, n = re.subn(r"(\n\s*texture\s*=\s*)[^,\n]+,", rf"\g<1>{tex_name(tex_key, th)},", body)
            if n != 1:
                sys.exit(f"{s['ground']}: texture 不是剛好一行")
            out += [f"    model {ground_name(s['key'], th)}", "    {" + b.replace("\n        ", "\n        ").rstrip(), "    }", ""]
    out[-1:] = ["}", ""]
    return "\n".join(out)


def build(root, plain=False):
    """把所有產物寫到 root（結構同 repo）：回 (逐位元組重現的檔, 圖示)，都是相對路徑。"""
    items = vanilla_items()
    shapes, written, by_source = [], [], {}
    seen = []
    for cfg in SHAPES:
        s = dict(cfg, key=cfg["rep"].split(".", 1)[1])
        rep = items.get(s["rep"]) or sys.exit(f"原版沒有 {s['rep']}")
        ci = clothing(rep["ClothingItem"])
        if s["base"].lower() not in [t.lower() for t in ci["tex"]]:
            sys.exit(f"{s['rep']}: textureChoices 沒有 {s['base']}")
        for m in s["members"]:
            f = items.get(m) or sys.exit(f"原版沒有 {m}")
            mesh = os.path.splitext(os.path.basename(clothing(f["ClothingItem"])["M"].replace("\\", "/")))[0].lower()
            if mesh != s["mesh"]:
                sys.exit(f"{m}: 網格是 {mesh}，不是 {s['mesh']}")
            tex = clothing(f["ClothingItem"])["tex"]
            by_source[m] = [theme_of(m, t) for t in tex] or [theme_of(m, "")]
            seen.append(m)
        s["_mesh"] = read_mesh(model_path(ci["M"]))
        shapes.append(s)
    if len(seen) != len(set(seen)):
        sys.exit("有原版背包同時在兩種形狀裡")
    # 和原版比對：每個用這 22 種網格、可以穿的背包都要在表裡（遊戲更新多了新背包時停下來）
    meshes = {s["mesh"] for s in shapes}
    extra = []
    for full, f in items.items():
        if full in seen or not f.get("ClothingItem") or f.get("ItemType", "").lower() != "base:container":
            continue
        xml = os.path.join(PZ, "clothing", "clothingItems", f["ClothingItem"] + ".xml")
        if os.path.isfile(xml) and os.path.splitext(os.path.basename(clothing(f["ClothingItem"])["M"].replace("\\", "/")))[0].lower() in meshes:
            extra.append(full)
    if extra:
        print(f"注意：這些原版容器也用這 22 種網格，但不在 SHAPES（不在升級清單就不用管）：{sorted(extra)}")
    tex_dir = os.path.join(root, os.path.relpath(MEDIA, REPO), "textures")
    os.makedirs(os.path.join(tex_dir, "Clothes", "Bag"), exist_ok=True)
    for s in shapes:
        for th in THEMES:
            p = os.path.join(tex_dir, *tex_name(s["key"], th).split("/")) + ".png"
            texture(s, th, plain).save(p, optimize=True)
            written.append(os.path.relpath(p, root))
        print(s["key"], flush=True)
    with tempfile.TemporaryDirectory() as work:
        icons = render_icons(root, shapes, work)
    manifest = dict(version=1, shapes=[dict(
        key=s["key"], mesh=s["mesh"], representative=s["rep"], members=s["members"], base_texture=s["base"],
        texture={th: tex_name(s["key"], th) for th in THEMES}, icon={th: icon_name(s["key"], th) for th in THEMES},
        ground={th: (f"{MODULE}.{ground_name(s['key'], th)}" if s.get("ground") else None) for th in THEMES}) for s in shapes],
        theme_by_source=dict(sorted(by_source.items())))
    for rel, text in ((os.path.relpath(MANIFEST, REPO), json.dumps(manifest, ensure_ascii=False, indent=1) + "\n"),
                      (os.path.relpath(GROUND_SCRIPT, REPO), ground_script(shapes))):
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        written.append(rel)
    return written, icons


def icon_diff(a, b):
    """兩張圖示的差：(不透明範圍不同的像素數, 兩邊都不透明處 RGB 最大差)。"""
    x, y = (np.asarray(Image.open(p).convert("RGBA")).astype(int) for p in (a, b))
    ma, mb = x[..., 3] > 127, y[..., 3] > 127
    both = ma & mb
    return int((ma != mb).sum()), int(np.abs(x[both, :3] - y[both, :3]).max(initial=0))


def main():
    plain = "--plain" in sys.argv
    if "--check" in sys.argv:
        # 貼圖、清單檔、地面模型腳本逐位元組比對。圖示是 Blender 算圖再縮到 32 px：同一台機器、同一版 Blender（5.2）重建兩次實測範圍差 0、顏色差 0，
        # 但換顯示卡驅動或 Blender 版本可能差幾個色階，所以圖示用容差比：不透明範圍差 ≤ ICON_TOL[0] 像素、顏色差 ≤ ICON_TOL[1] 色階
        with tempfile.TemporaryDirectory() as tmp:
            exact, icons = build(tmp, plain)
            stale = [rel for rel in exact if not os.path.isfile(os.path.join(REPO, rel))
                     or open(os.path.join(REPO, rel), "rb").read() != open(os.path.join(tmp, rel), "rb").read()]
            worst = (0, 0)
            for rel in icons:
                if not os.path.isfile(os.path.join(REPO, rel)):
                    stale.append(rel)
                    continue
                d = icon_diff(os.path.join(REPO, rel), os.path.join(tmp, rel))
                worst = max(worst[0], d[0]), max(worst[1], d[1])
                if d[0] > ICON_TOL[0] or d[1] > ICON_TOL[1]:
                    stale.append(f"{rel}（範圍差 {d[0]} 像素、顏色差 {d[1]}）")
        if stale:
            sys.exit("主題產物和重建結果不同，重跑 uv run scripts/gen_theme.py：\n  " + "\n  ".join(stale))
        print(f"OK：{len(exact)} 個檔逐位元組相同；{len(icons)} 個圖示在容差內（最大範圍差 {worst[0]} 像素、顏色差 {worst[1]}）")
        return
    exact, icons = build(REPO, plain)
    print(f"寫了 {len(exact) + len(icons)} 個檔")


if __name__ == "__main__":
    main()
