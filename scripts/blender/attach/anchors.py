"""強化版背包額外掛點的位置（掛點骨頭 Bip01_BackPack 空間）：讀原版穿戴 .X 的網格與骨頭反綁定矩陣，射線找包身表面。
uv run --no-project --with numpy python scripts/blender/attach/anchors.py        印出每個網格、男女、每個掛點的座標（Lua 表）

骨頭空間（反綁定矩陣換算，xio.read_x 的 sw[骨名][2]；頂點列向量 × 矩陣）：+x 離開背部朝外、+y 角色左邊、+z 往上。
原版 bedroll_bottom（models_characters.txt:358-375）在 (0.05, 0, -0.2)，正好在四款包身下方，可當對照。
只取 Bip01_BackPack 權重 > 0.5 的三角形當包身（肩帶、腰帶掛在 Spine／Clavicle，會跟著身體動）。
這裡算的是起點：實機截圖（E2E attach-art-sp）調過的最終值寫在 client/MDB_AttachClient.lua，兩邊不必一致。
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bags"))
import xio  # noqa: E402

X = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media/models_X/Skinned/BackPacks/"
MESH = {  # 家族 → (男, 女) 穿戴網格；旅行登山包用一般登山包的網格（Bag_HikingBag_Travel.xml）
    "Alice": ("M_ALICE_Pack.x", "F_ALICE_Pack.x"),
    "Duffel": ("M_Duffelbag.x", "F_DuffelBag.x"),
    "Hiking": ("M_HikingBag.x", "F_HikingBag.x"),
    "BigHiking": ("M_BigHikingBag.x", "F_BigHikingBag.x"),
}
BONE = "Bip01_BackPack"


def body(path):
    d = xio.read_x(X + path)
    idx, w, ibm = d["sw"][BONE]
    L = (np.c_[d["V"], np.ones(len(d["V"]))] @ ibm)[:, :3]
    wb = np.zeros(len(L))
    wb[idx] = w
    return L, d["F"][(wb[d["F"]] > 0.5).all(1)]


def hits(L, F, o, d):
    """射線 o + t·d 和三角形的所有交點 t（Möller–Trumbore）。"""
    v0, e1, e2 = L[F[:, 0]], L[F[:, 1]] - L[F[:, 0]], L[F[:, 2]] - L[F[:, 0]]
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = o - v0
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (d * q).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    return np.sort(t[ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)])


def surface(L, F, axis, sign, a, b):
    """沿 axis 從 sign 那一側往內射，回最外面的表面座標；另兩軸固定在 (a, b)（依 x、y、z 順序）。
    低面數網格在接縫可能漏接：附近 ±1 cm 多射幾條，取最外面的那條。"""
    best = None
    for da in (0.0, -0.01, 0.01):
        for db in (0.0, -0.01, 0.01):
            o = np.zeros(3)
            d = np.zeros(3)
            o[axis], d[axis] = sign * 1.0, -sign
            o[[i for i in range(3) if i != axis]] = (a + da, b + db)
            t = hits(L, F, o, d)
            if len(t) and (best is None or 1 - t[0] > best):
                best = 1 - t[0]
    return None if best is None else sign * best


def anchors(fam, path):
    L, F = body(path)
    lo, hi = L[np.unique(F)].min(0), L[np.unique(F)].max(0)
    out = {}
    if fam == "Duffel":
        # 圓筒包橫在下背、右低左高：沿包身取三點，各自找外側表面
        for i, y in enumerate((0.07, -0.02, -0.11), 1):
            zc = np.mean([surface(L, F, 2, 1, 0.06, y), surface(L, F, 2, -1, 0.06, y)])
            out[f"Slot{i}"] = (surface(L, F, 0, 1, y, zc), y, zc)
        yb = hi[1] - 0.04
        zt = surface(L, F, 2, 1, 0.06, yb)
        out["Plushie"] = (0.06, yb, zt)
        yr = lo[1] + 0.03
        zr = np.mean([surface(L, F, 2, 1, 0.06, yr), surface(L, F, 2, -1, 0.06, yr)])
        out["BottleR"] = (surface(L, F, 0, 1, yr, zr), yr, zr)
        out["UmbrellaR"] = (0.06, lo[1], zr)
        out["Flashlight"] = (0.06, -0.05, surface(L, F, 2, 1, 0.06, -0.05))   # 頂部偏右，和左端的玩偶錯開
        return out
    zc = lo[2] + 0.4 * (hi[2] - lo[2])          # 物品槽一排在包身下半
    for i, y in enumerate((0.055, 0.0, -0.055), 1):
        out[f"Slot{i}"] = (surface(L, F, 0, 1, y, zc), y, zc)
    xp = hi[0] - 0.045                          # 玩偶坐在包頂靠外側（玩偶比包厚，置中會碰到頭）
    out["Plushie"] = (xp, 0.0, surface(L, F, 2, 1, xp, 0.0))
    xb, xu = lo[0] + 0.45 * (hi[0] - lo[0]), lo[0] + 0.75 * (hi[0] - lo[0])   # 側面：水瓶在中段、側邊束帶靠外
    zb = lo[2] + 0.25 * (hi[2] - lo[2])
    zm = (lo[2] + hi[2]) / 2
    for s, sign in (("R", -1), ("L", 1)):
        out["Bottle" + s] = (xb, surface(L, F, 1, sign, xb, zb), zb)
        out["Umbrella" + s] = (xu, surface(L, F, 1, sign, xu, zm), zm)
    zf = lo[2] + 0.75 * (hi[2] - lo[2])
    side = 1 if fam == "Alice" else -1           # 手電筒在側邊束帶的另一邊
    out["Flashlight"] = (xb, surface(L, F, 1, side, xb, zf), zf)
    return out


def main():
    print("-- scripts/blender/attach/anchors.py 輸出（Bip01_BackPack 空間，x 朝外、y 左、z 上）")
    for fam, (m, f) in MESH.items():
        for sex, path in (("M", m), ("F", f)):
            a = anchors(fam, path)
            print(f"{fam}.{sex} = {{")
            for k, v in a.items():
                print(f"    {k} = {{ {v[0]:.3f}, {v[1]:.3f}, {v[2]:.3f} }},")
            print("}")


if __name__ == "__main__":
    main()
