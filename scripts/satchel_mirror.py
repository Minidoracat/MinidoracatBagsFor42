# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""側背包穿在另一側的模型：第二個側背包位置的強化版用它，才不會和原版側背包疊在同一側。

用法（repo 根目錄）：
    uv run scripts/satchel_mirror.py           寫入 MOD 的 .X 與 scripts/satchel_mirror_map.json
    uv run scripts/satchel_mirror.py --check   只比對：已提交的檔和重建結果不同、或出現沒分類的新模型就回 1（遊戲更新後重跑）

來源：MDB_Recipes.txt 升級配方（MDB_UpgradeBagTier1）的背包清單裡 CanBeEquipped = base:satchel 的物品
（強化版除外：它們的 XML 由 gen_reinforced.py 依對照檔改寫），取 ClothingItem XML 的男女穿戴模型，每個不同模型做一份。
.X 空間 x=0 是身體中線（左右骨頭位置對稱，MaleBody／FemaleBody 的反綁定矩陣換算），原版側背包掛在 −x。兩種做法：
  mirror：整個網格 x 取負、Bip01_L_* 權重換到 Bip01_R_*、面序反轉；貼圖跟著左右顛倒，只用在貼圖沒有字的模型。
  rotate：背帶（點焊後的連通塊伸到肩上 y>0.7）照 mirror；包身、扣環、提把不鏡像，用剛體旋轉＋平移
          （ICP 對齊到鏡像後的位置，det +1），貼圖上的字與隊徽照樣是正的。這幾塊只掛 Bip01_BackPack，權重原樣。
鏡像後包身仍越過中線約 3 cm，會和第一個位置的原側背包在背後中間互穿（兩個包加起來比背後半圈寬），所以再繞身體縱軸
把包身轉到另一側髖部（背帶在包頂以下跟著轉、肩下以上不動），轉到和同性別每一款原側背包都不互穿再多 2°；
轉過去比原本貼身的話，包身整塊往外平移（不變形），背帶過渡段逐點推出。兩條斜背帶在胸前、背後的交叉不處理（見 mirror_model）。
R 骨頭的反綁定矩陣取同性別身體 .X（模板裡只有 L）。輸出 MDB_<原模型名>_Mirror.X（本 MOD 的模型已有 MDB_ 前綴就不重複）；檔名是全域的。
"""
import json
import os
import re
import shutil
import sys
import tempfile

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "blender", "bags"))
import gen_reinforced as gr  # noqa: E402
import xio  # noqa: E402
from verify_x import SKIN_TOL, skin_dist  # noqa: E402

MAP = os.path.join(HERE, "satchel_mirror_map.json")
OUT_DIR = r"media\models_X\Skinned\BackPacks"
S = np.array([-1.0, 1.0, 1.0])
STRAP_Y = 0.7   # 背帶連通塊伸到肩上；包身、扣環、提把都在 y<0.6
ORBIT_Y = (0.59, 0.76)   # 背帶跟著包身轉的範圍：包頂以下全轉、肩下以上不轉
ORBIT_MAX, ORBIT_MARGIN = 75, 2   # 度

# 每個模型怎麼做，看過它所有貼圖才分類（新模型不在表裡就失敗，先看貼圖有沒有字）
MODE = {
    "M_ClothSatchel": "mirror", "F_ClothSatchel": "mirror",   # 布側背包 6 款：補丁與縫線，沒有字
    "M_Satchel": "mirror", "F_Satchel": "mirror",             # 側背包／相機包：Satchel、_green、_khaki，扣帶沒有字
    "M_Satchel_New": "rotate", "F_Satchel_New": "rotate",     # FIRST AID、MAIL、ARMY＋序號、釣具徽章
    "MDB_CourierSatchel_M": "rotate", "MDB_CourierSatchel_F": "rotate",   # 深藍款 S.T.A.R.S. 隊徽
}


def sources():
    """[(物品全名, ClothingItem, 男模型字串, 女模型字串)]"""
    recipes = gr.read(gr.RECIPES)
    m = re.search(r"craftRecipe MDB_UpgradeBagTier1\b.*?item 1 \[([^\]]+)\]", recipes, re.S)
    if not m:
        sys.exit("MDB_Recipes.txt 找不到 MDB_UpgradeBagTier1 的背包清單")
    blocks = gr.item_blocks()
    out = []
    for full in m.group(1).split(";"):
        if full.endswith(gr.SUFFIX):
            continue
        if full not in blocks:
            sys.exit(f"{full}: 找不到物品腳本")
        kv = dict(re.findall(r"^\s*(\w+)\s*=\s*(.*?),?\s*$", "\n".join(blocks[full]), re.M))
        if kv.get("CanBeEquipped", "").lower() != "base:satchel":
            continue
        ci = kv["ClothingItem"]
        xml = next((gr.read(os.path.join(d, ci + ".xml")) for d in gr.CLOTHING_DIRS
                    if os.path.exists(os.path.join(d, ci + ".xml"))), None)
        if xml is None:
            sys.exit(f"{full}: 找不到 ClothingItem {ci}.xml")
        out.append((full, ci, re.search(r"<m_MaleModel>(.*?)</", xml).group(1), re.search(r"<m_FemaleModel>(.*?)</", xml).group(1)))
    return out


def resolve(model):
    """XML 裡的模型字串（media\\...）→ 檔案路徑：本 MOD 先，原版後"""
    rel = model.replace("\\", "/").split("media/", 1)[1]
    for root in (gr.MEDIA, gr.PZ):
        p = os.path.join(root, rel)
        if os.path.exists(p):
            return p
    sys.exit(f"找不到模型 {model}")


def stem(model):
    return os.path.splitext(model.replace("\\", "/").rsplit("/", 1)[1])[0]


def welded_parts(V, F, tol=1e-4):
    """面相連＋位置重合（UV 縫拆開的點）合成連通塊，回每個頂點的塊編號"""
    p = np.arange(len(V))

    def find(a):
        while p[a] != a:
            p[a] = p[p[a]]
            a = p[a]
        return a
    for a, b in [(f[0], f[1]) for f in F] + [(f[1], f[2]) for f in F] + list(cKDTree(V).query_pairs(tol)):
        ra, rb = find(a), find(b)
        if ra != rb:
            p[ra] = rb
    return np.array([find(i) for i in range(len(V))])


def strap_mask(V, F):
    """背帶＝伸到肩上的點焊連通塊；其餘是包身、扣環、提把"""
    part = welded_parts(V, F)
    return np.isin(part, [r for r in np.unique(part) if V[part == r, 1].max() > STRAP_Y])


def kabsch(P, Q):
    """P→Q 的剛體變換（det +1）"""
    cp, cq = P.mean(0), Q.mean(0)
    U, _, Vt = np.linalg.svd((P - cp).T @ (Q - cq))
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    R = Vt.T @ np.diag([1, 1, d]) @ U.T
    return R, cq - R @ cp


def fit_rotate(P):
    """找剛體 (R, t) 讓 P 落在 P 的鏡像上：初值＝鏡像再沿包身自己的主軸鏡像一次（兩次鏡像＝旋轉），三個主軸都試、ICP 收斂，取殘差最小"""
    Q = P * S
    tree = cKDTree(Q)
    c = P.mean(0)
    best = None
    for n in np.linalg.svd(P - c)[2]:
        R = np.diag(S) @ (np.eye(3) - 2 * np.outer(n, n))
        t = c * S - R @ c
        for _ in range(100):
            _, j = tree.query(P @ R.T + t)
            R2, t2 = kabsch(P, Q[j])
            done = np.abs(R2 - R).max() < 1e-10 and np.abs(t2 - t).max() < 1e-10
            R, t = R2, t2
            if done:
                break
        rms = float(np.sqrt((tree.query(P @ R.T + t)[0] ** 2).mean()))
        if best is None or rms < best[2]:
            best = (R, t, rms)
    return best


def faces_out(V, N, F):
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    return float((np.einsum("ij,ij->i", fn, N[F].sum(1)) > 0).mean())


def crossings(VA, FA, VB, FB):
    """兩個網格互穿的交點：A 的每條邊穿過 B 的三角形，加上反過來（Möller–Trumbore）。len() 就是互穿邊數"""
    out = [np.zeros((0, 3))]
    for (V1, F1), (V2, F2) in (((VA, FA), (VB, FB)), ((VB, FB), (VA, FA))):
        if not len(F1) or not len(F2):
            continue
        E = np.unique(np.sort(np.r_[F1[:, [0, 1]], F1[:, [1, 2]], F1[:, [2, 0]]], 1), axis=0)
        P0, D = V1[E[:, 0]], V1[E[:, 1]] - V1[E[:, 0]]
        T0, e1, e2 = V2[F2[:, 0]], V2[F2[:, 1]] - V2[F2[:, 0]], V2[F2[:, 2]] - V2[F2[:, 0]]
        h = np.cross(D[:, None], e2[None])
        a = np.einsum("ijk,jk->ij", h, e1)
        f = 1 / np.where(np.abs(a) > 1e-12, a, np.inf)
        s = P0[:, None] - T0[None]
        q = np.cross(s, e1[None])
        u, v, t = f * np.einsum("ijk,ijk->ij", s, h), f * np.einsum("ijk,ik->ij", q, D), f * np.einsum("ijk,jk->ij", q, e2)
        i, j = np.nonzero((f != 0) & (u >= 0) & (v >= 0) & (u + v <= 1) & (t >= 0) & (t <= 1))
        out.append(P0[i] + D[i] * t[i, j][:, None])
    return np.concatenate(out)


def follow(V, strap):
    """每個點跟著包身動的比例：包身 1；背帶在包頂以下 1、肩下 ORBIT_Y 以上 0，中間平滑過渡"""
    a = np.clip((ORBIT_Y[1] - V[:, 1]) / (ORBIT_Y[1] - ORBIT_Y[0]), 0, 1)
    return np.where(strap, a * a * (3 - 2 * a), 1.0)


def orbit(V, N, strap, deg, zc):
    """繞身體縱軸（x=0、z=zc）往 +x 轉 deg 度：包身整塊轉，背帶照 follow 的比例轉"""
    a = follow(V, strap) * np.radians(deg)
    c, s = np.cos(a), np.sin(a)
    R = np.zeros((len(V), 3, 3))
    R[:, 0, 0], R[:, 0, 2], R[:, 1, 1], R[:, 2, 0], R[:, 2, 2] = c, s, 1, -s, c
    o = np.r_[0.0, 0.0, zc]
    return np.einsum("nij,nj->ni", R, V - o) + o, np.einsum("nij,nj->ni", R, N)


def place(V, N, strap, deg, zc, body, gap):
    """orbit 後，包身離身體最近的點比 gap 近，就把包身整塊（背帶照 follow 的比例）沿包身中心的身體法線往外平移到 gap：
    包身轉到髖部後貼得比原本近，整塊平移不讓包身變形、貼圖上的字不歪"""
    P, Nn = orbit(V, N, strap, deg, zc)
    k = follow(P, strap)[:, None]
    d = body_normal(P[~strap].mean(0, keepdims=True), body)
    for _ in range(5):
        lack = gap - skin_dist(P[~strap], body).min()
        if lack <= 1e-5:
            break
        P = P + d * k * lack
    return P, Nn


def body_normal(P, body):
    """每個點最近 3 個身體頂點的法線平均（單位長）"""
    nn = cKDTree(body["V"]).query(P, k=3)[1]
    n = body["N"][nn].sum(1)
    return n / np.linalg.norm(n, axis=1, keepdims=True)


def push_out(V, body, target):
    """離身體比 target 近的點，沿最近身體頂點法線推到 target（同 stage2_assemble.py 的 skin_push 量法）；回推過的點數"""
    moved = np.zeros(len(V), bool)
    for _ in range(3):
        nn = cKDTree(body["V"]).query(V, k=3)[1]
        s = np.einsum("ikj,ikj->ik", V[:, None] - body["V"][nn], body["N"][nn])
        lack = np.maximum(target - s.max(1), 0) * (np.linalg.norm(V[:, None] - body["V"][nn], axis=2).min(1) < 0.05)
        V += body["N"][nn[np.arange(len(V)), s.argmax(1)]] * lack[:, None]
        moved |= lack > 0
    return int(moved.sum())


def mirror_model(src, dst, mode, body, avoid):
    """寫 dst，回檢查數值；任一項不過就 sys.exit。
    avoid＝同性別所有原側背包 [(V, F, 包身的面, 背帶的面)]：鏡像版穿在第二個位置時，不能和第一個位置上的任何一款互穿"""
    X = xio.read_x(src)
    V, N, F, UV = X["V"], X["N"], X["F"], X["UV"]
    assert len(N) == len(V) and (X["NF"] == F).all(), f"{src}: 法線不是逐頂點"
    strap = strap_mask(V, F)
    rigid = ~strap if mode == "rotate" else np.zeros(len(V), bool)
    V2, N2 = V * S, N * S
    info = dict(mode=mode, verts=len(V), strap_verts=int(strap.sum()), rigid_verts=int(rigid.sum()))
    if rigid.any():
        for b, (idx, w, _) in X["sw"].items():
            if b != "Bip01_BackPack" and (w[rigid[idx]] > 0).any():
                sys.exit(f"{src}: 剛體部分掛到 {b}，旋轉後權重對不上，改用別的做法")
        R, t, rms = fit_rotate(V[rigid])
        V2[rigid] = V[rigid] @ R.T + t
        N2[rigid] = N[rigid] @ R.T
        info.update(rotate_det=round(float(np.linalg.det(R)), 6), rotate_deg=round(float(np.degrees(np.arccos((np.trace(R) - 1) / 2))), 2),
                    fit_rms=round(rms, 5))
    flip = ~rigid[F[:, 0]]   # 一個面只屬於一個連通塊；鏡像的面反轉繞序
    F2 = F.copy()
    F2[flip] = F[flip][:, ::-1]
    Fb2 = F2[~strap[F2[:, 0]]]
    # 原版側背包斜掛後腰、包身越過中線約 3 cm，單純鏡像會和它在背後中間互穿（兩個包加起來比背後半圈寬）：
    # 繞身體縱軸把包身轉到另一側髖部，轉到包身和每一款原側背包都不互穿、背帶不穿過原包身，再多 ORBIT_MARGIN 度
    hip = body["V"][(body["V"][:, 1] > 0.45) & (body["V"][:, 1] < 0.6)]
    zc = float(hip[:, 2].min() + hip[:, 2].max()) / 2
    gap = skin_dist(V[~strap], body).min()
    clear = lambda P: all(not len(crossings(A, FA, P, Fb2)) and not len(crossings(A, FbA, P, F2)) for A, FA, FbA, _ in avoid)
    deg = next((d for d in range(0, ORBIT_MAX + 1) if clear(place(V2, N2, strap, d, zc, body, gap)[0])), None)
    if deg is None:
        sys.exit(f"{src}: 轉到 {ORBIT_MAX}° 還是會和原側背包互穿")
    V2, N2 = place(V2, N2, strap, deg + ORBIT_MARGIN, zc, body, gap)
    P = V2[strap]
    pushed = push_out(P, body, skin_dist(V[strap], body).min())   # 背帶過渡段逐點推出，不比原背帶更貼身
    V2[strap] = P
    # 背帶和原背帶在胸前、背後的交叉不處理：原版背帶在交叉處是側立的窄條（法線幾乎和身體表面平行），
    # 墊高 1 cm 交叉邊數也沒少；兩條斜背帶交叉本來就碰在一起，交叉邊數寫進 info（strap_cross）
    info.update(orbit_deg=deg + ORBIT_MARGIN, orbit_min_deg=deg, pushed=pushed)
    W = {b.replace("_L_", "_R_") if "_L_" in b else b: (idx, w) for b, (idx, w, _) in X["sw"].items()}
    extra = {b: body["sw"][b][2] for b in W if "_R_" in b}
    xio.write_skinned_x(src, dst, V2, N2, UV, F2, W, name=stem(dst), extra_ibm=extra)
    # 讀回檢查
    Y = xio.read_x(dst)
    fo = faces_out(Y["V"], Y["N"], Y["F"])
    fo0 = faces_out(V, N, F)
    # 穿模（skinned-bags.md §8）：整件、和包身各自離身體最近的點，都不能比原模型再貼近 5 mm 以上
    near = {k: (skin_dist(Y["V"][sel], body).min(), skin_dist(V[sel], body).min())
            for k, sel in (("skin_min", np.ones(len(V), bool)), ("body_skin_min", ~strap))}
    side = (Y["V"][~strap, 0].mean(), V[~strap, 0].mean())
    # 背帶兩端接到扣環：每個背帶端點離包身最近的距離，不能比原模型同一點再遠 5 mm 以上
    ends = strap & (V[:, 1] < 0.6)
    grow = cKDTree(Y["V"][~strap]).query(Y["V"][ends])[0] - cKDTree(V[~strap]).query(V[ends])[0]
    Fb = Y["F"][~strap[Y["F"][:, 0]]]
    cross = [len(crossings(A, FA, Y["V"], Fb)) + len(crossings(A, FbA, Y["V"], Y["F"])) for A, FA, FbA, _ in avoid]
    strap_cross = [len(crossings(A, FsA, Y["V"], Y["F"][strap[Y["F"][:, 0]]])) for A, _, _, FsA in avoid]
    info.update(faces_out=round(fo, 3), faces_out_src=round(fo0, 3), body_x=round(float(side[0]), 4), body_x_src=round(float(side[1]), 4),
                strap_gap_grow=round(float(grow.max()), 4), body_cross=cross, strap_cross=strap_cross, bones=list(Y["sw"]))
    for k, (ours, van) in near.items():
        info.update({k: round(float(ours), 4), k + "_src": round(float(van), 4)})
    bad = []
    if fo < min(0.95, fo0):
        bad.append(f"面朝外只有 {fo:.1%}（原版 {fo0:.1%}）")
    for k, (ours, van) in near.items():
        if ours < van - SKIN_TOL:
            bad.append(f"{k}：離身體最近 {ours:.4f}，比原模型 {van:.4f} 再貼近超過 {SKIN_TOL}（穿模）")
    if not side[0] * side[1] < 0:
        bad.append(f"包身 x 平均 {side[0]:.4f}，沒有換到另一側（原版 {side[1]:.4f}）")
    if grow.max() > SKIN_TOL:
        bad.append(f"背帶端點離扣環比原模型遠 {grow.max():.4f}，接縫裂開")
    if any(cross):
        bad.append(f"包身和原側背包互穿，或背帶穿過原包身（各款互穿邊數 {cross}）")
    if any("_L_" in b for b in Y["sw"]) or any(not np.array_equal(Y["sw"][b][2], body["sw"][b][2]) for b in extra):
        bad.append("還有 L 骨頭，或 R 骨頭的反綁定矩陣不是身體 .X 的")
    if not np.array_equal(Y["UV"], UV):
        bad.append("UV 和原模型不同（貼圖要共用）")
    if bad:
        sys.exit(f"{dst}:\n  " + "\n  ".join(bad))
    return info


def build(media_root):
    """在 media_root（結構同 MOD 的 media/）寫出所有鏡像模型，回 (對照表, 檢查數值, 來源)"""
    src = sources()
    models = {}
    for _, _, m, f in src:
        models[m], models[f] = "MaleBody.x", "FemaleBody.x"
    unknown = [m for m in models if stem(m) not in MODE]
    if unknown:
        sys.exit(f"沒分類的新側背包模型 {unknown}：先看它所有貼圖有沒有字，再加進 MODE")
    bodies = {b: xio.read_x(os.path.join(gr.PZ, "models_X", "Skinned", b)) for b in set(models.values())}
    avoid = {b: [] for b in bodies}
    for m, b in models.items():
        A = xio.read_x(resolve(m))
        st = strap_mask(A["V"], A["F"])[A["F"][:, 0]]
        avoid[b].append((A["V"], A["F"], A["F"][~st], A["F"][st]))
    mapping, info = {}, {}
    for m, b in sorted(models.items()):
        name = f"{'' if stem(m).startswith('MDB_') else 'MDB_'}{stem(m)}_Mirror.X"
        dst = os.path.join(media_root, "models_X", "Skinned", "BackPacks", name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        info[name] = mirror_model(resolve(m), dst, MODE[stem(m)], bodies[b], avoid[b])
        mapping[m] = f"{OUT_DIR}\\{name}"
    return mapping, info, src


def dump(mapping):
    return json.dumps(mapping, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def main():
    check = "--check" in sys.argv
    tmp = tempfile.mkdtemp() if check else None
    try:
        mapping, info, src = build(tmp or gr.MEDIA)
        groups = {}
        for full, ci, m, f in src:
            groups.setdefault((m, f), []).append(f"{full}（{ci}）")
        for (m, f), items in groups.items():
            print(f"{stem(m)} / {stem(f)} ← {len(items)} 件：" + "、".join(items))
        for k, v in info.items():
            print(k, v)
        if not check:
            with open(MAP, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(dump(mapping))
            print(f"寫入 {len(info)} 個模型與 {os.path.relpath(MAP)}")
            return
        diff = [] if os.path.exists(MAP) and gr.read(MAP) == dump(mapping) else [os.path.relpath(MAP)]
        for name in info:
            rel = os.path.join("models_X", "Skinned", "BackPacks", name)
            a, b = os.path.join(gr.MEDIA, rel), os.path.join(tmp, rel)
            if not os.path.exists(a) or open(a, "rb").read() != open(b, "rb").read():
                diff.append(rel)
        if diff:
            print("和重建結果不同（跑 uv run scripts/satchel_mirror.py 重建）：\n  " + "\n  ".join(diff))
            sys.exit(1)
        print(f"OK：{len(info)} 個模型與對照檔都和重建結果相同")
    finally:
        if tmp:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
