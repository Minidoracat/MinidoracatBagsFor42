"""背包產物逐項斷言（研究第 9 步）。build.py 每次建置都跑，任一項失敗就讓建置失敗。
uv run --with numpy --with pillow scripts/blender/bags/verify_x.py <款> [--selftest]
  --selftest：把產物複製一份、植入違規，確認每一種都被抓到。
"""
import json, os, shutil, sys, tempfile
import numpy as np
from PIL import Image

import bags
from common import MEDIA, PZ, TEX_SIZE, fbx_node_transforms, out, temp, xio

BP = "models_X/Skinned/BackPacks/"
HAND_BONES = {"RHand": {"Bip01_R_Hand", "Bip01_Prop1"}, "LHand": {"Bip01_L_Hand", "Bip01_Prop2"}}
MAX_VERTS, TARGET_VERTS = 1100, 600
SKIN_TOL = 0.005   # 繞身體的款式：每個頂點離身體的距離不能比原版最貼的那點再近 5 mm


def files(cfg):
    """{輸出檔名後綴: 原版模板}"""
    f = {"M": cfg["worn"]["M"], "F": cfg["worn"]["F"]}
    if cfg.get("alt"):
        f.update(ALT_M=cfg["alt"]["M"], ALT_F=cfg["alt"]["F"])
    if cfg.get("hands"):
        f.update(RHand=cfg["hands"]["R"], LHand=cfg["hands"]["L"])
    return f


def ray_z(P, V, F):
    """每個點往 +z（角色背後）射線：回 (穿過的三角形數, 第一個交點 z；沒打到為 inf)。奇數＝點在封閉網格裡。"""
    a, e1, e2 = V[F[:, 0]], V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]
    det = e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]
    det = np.where(np.abs(det) < 1e-12, np.nan, det)
    q = P[:, None, :2] - a[None, :, :2]
    u = (q[..., 0] * e2[:, 1] - q[..., 1] * e2[:, 0]) / det
    v = (e1[:, 0] * q[..., 1] - e1[:, 1] * q[..., 0]) / det
    z = a[:, 2] + u * e1[:, 2] + v * e2[:, 2]
    hit = (u >= 0) & (v >= 0) & (u + v <= 1) & (z > P[:, 2:3])
    return hit.sum(1), np.where(hit, z, np.inf).min(1)


def skin_dist(G, B):
    """衣物頂點沿最近 3 個身體頂點法線的帶號距離（取最大）；只看離身體 5 cm 內的點。低面數身體上的粗略量，只拿來和原版比。"""
    d = np.linalg.norm(G[:, None] - B["V"][None], axis=2)
    nn = np.argsort(d, 1)[:, :3]
    s = np.einsum("ikj,ikj->ik", G[:, None] - B["V"][nn], B["N"][nn]).max(1)
    return s[d.min(1) < 0.05]


def check(name, media):
    cfg = bags.get(name)
    fail, info = [], {}

    def ok(cond, msg):
        if not cond:
            fail.append(msg)

    X = {}
    for suf, van in files(cfg).items():
        nm = f"MDB_{name}_{suf}"
        p = f"{media}/{BP}{nm}.X"
        if not os.path.exists(p):
            fail.append(f"{nm}.X 不存在"); continue
        d = X[suf] = xio.read_x(p)
        T = xio.read_x(PZ + "/" + van)
        nv = len(d["V"])
        ok(nv <= MAX_VERTS, f"{nm}: {nv} 頂點 > {MAX_VERTS}")
        bones = set(d["sw"])
        ok(bones <= HAND_BONES.get(suf, set(cfg["bones"])) and len(bones) <= 5, f"{nm}: 骨頭 {sorted(bones)} 不在白名單")
        cnt, ws = np.zeros(nv, int), np.zeros(nv)
        for b, (idx, w, ibm) in d["sw"].items():
            cnt[idx] += 1; ws[idx] += w
            ok(b in T["sw"] and np.array_equal(ibm, T["sw"][b][2]), f"{nm}: {b} 反綁定矩陣和原版 {os.path.basename(van)} 不同")
        ok(cnt.max() <= 4, f"{nm}: 每頂點最多 {cnt.max()} 個權重 > 4")
        ok(np.abs(ws - 1).max() < 2e-3, f"{nm}: 權重和 {ws.min():.4f}–{ws.max():.4f} 不是 1")
        ok(d["UV"].min() >= 0 and d["UV"].max() <= 1, f"{nm}: UV 超出 [0,1]")
        ok(np.abs(np.linalg.norm(d["N"], axis=1) - 1).max() < 1e-3, f"{nm}: 法線不是單位長")
        fn = np.cross(d["V"][d["F"][:, 1]] - d["V"][d["F"][:, 0]], d["V"][d["F"][:, 2]] - d["V"][d["F"][:, 0]])
        fo = (np.einsum("ij,ij->i", fn, d["N"][d["F"]].sum(1)) > 0).mean()
        ok(fo >= 0.95, f"{nm}: 只有 {fo:.1%} 的面繞序和頂點法線同向（右手定則朝外）")
        info[nm] = dict(verts=nv, tris=len(d["F"]), bones=sorted(bones), max_influences=int(cnt.max()), faces_out=round(float(fo), 3),
                        bbox=[d["V"].min(0).round(4).tolist(), d["V"].max(0).round(4).tolist()])
    if len(X) == len(files(cfg)):
        uv = X["M"]["UV"]
        for k, d in X.items():
            ok(len(d["UV"]) == len(uv) and np.abs(d["UV"] - uv).max() < 1e-6, f"MDB_{name}_{k}: UV 和男版不同")
        g = np.load(os.path.join(temp(name), "ground_check.npz"))["UV"]   # FBX 讀回是 float32：用距離比，不用集合
        dist = lambda A, B: np.abs(A[:, None] - B[None]).max(2).min(1).max()
        ok(max(dist(g, uv), dist(uv, g)) < 1e-4, "地面 FBX 的 UV 和穿戴模型不同")
        worn = [("M", "MaleBody.x"), ("F", "FemaleBody.x")] + ([("ALT_M", "MaleBody.x"), ("ALT_F", "FemaleBody.x")] if cfg.get("alt") else [])
        for k, body in worn:
            nm, d = f"MDB_{name}_{k}", X[k]
            bt = d["F"][(d["UV"][d["F"]][..., 0] < cfg["body_u"] + 0.006).all(1)]   # 本體的面（右側長條是沿用的原版子網格）
            b = d["V"][np.unique(bt)]
            B = xio.read_x(PZ + "/models_X/Skinned/" + body)
            if cfg.get("bedroll") is not None:
                ok(0.52 <= b[:, 1].min() <= 0.57, f"{nm}: 本體底部 y={b[:, 1].min():.4f} 不在 0.52–0.57（睡袋掛點在底下）")
                ok(b[:, 2].max() >= 0.10, f"{nm}: 本體外側 z={b[:, 2].max():.4f} < 0.10")
                ok(cfg["bedroll"] < b[:, 1].min(), f"{nm}: 睡袋點 y={cfg['bedroll']} 埋進本體")
                info[nm].update(bottom_y=round(float(b[:, 1].min()), 4), outer_z=round(float(b[:, 2].max()), 4))
            if cfg["clearance"] == "closed":
                n, first = ray_z(B["V"], d["V"], bt)
                ok((n % 2 == 0).all(), f"{nm}: 身體有 {int((n % 2).sum())} 個頂點在本體裡（穿模）")
                info[nm].update(body_inside=int((n % 2).sum()),
                                min_clearance_behind_body=round(float((first - B["V"][:, 2])[n % 2 == 0].min()), 4))
            else:
                ours = skin_dist(d["V"], B).min()
                van = skin_dist(xio.read_x(PZ + "/" + files(cfg)[k])["V"], B).min()
                ok(ours >= van - SKIN_TOL, f"{nm}: 離身體最近 {ours:.4f}，比原版 {van:.4f} 再貼近超過 {SKIN_TOL}（穿模）")
                info[nm].update(skin_min=round(float(ours), 4), vanilla_skin_min=round(float(van), 4))
        gj = json.load(open(os.path.join(temp(name), "ground.json")))
        o, v = np.array(gj["ours_pz_bbox"]), np.array(gj["vanilla_pz_bbox"])
        ok(np.abs((o[1] - o[0])[:2].max() / (v[1] - v[0])[:2].max() - 1) < 0.1,
           f"地面 FBX 長邊 {(o[1] - o[0])[:2].max():.4f} 和原版 {(v[1] - v[0])[:2].max():.4f} 差超過 10%")
        ok(abs(o[0][2]) < 0.005, f"地面 FBX 最低點 {o[0][2]:.4f} 沒有貼地")
        # 網格節點要是單位矩陣：PZ 讀靜態網格會套節點變換鏈（items-and-icons.md §1），縮放、旋轉不對地上就變大小或翻倒
        gp = f"{media}/models_X/WorldItems/Clothing/MDB_{name}_Ground.fbx"
        nodes = fbx_node_transforms(gp) if os.path.exists(gp) else {}
        ok(len(nodes) == 1, f"地面 FBX 應該只有一個節點，讀到 {list(nodes)}")
        for nd, tr in nodes.items():
            ident = {"Lcl Translation": (0, 0, 0), "Lcl Rotation": (0, 0, 0), "Lcl Scaling": (1, 1, 1)}
            ok(all(abs(a - e) < 1e-6 for k, v in ident.items() for a, e in zip(tr[k], v)),
               f"地面 FBX 節點 {nd} 不是單位矩陣（節點縮放 {tr['Lcl Scaling']}、旋轉 {tr['Lcl Rotation']}）")
        info["ground"] = dict(bbox=gj["ours_pz_bbox"], vanilla=gj["vanilla_pz_bbox"], scale=gj["scale"],
                              node={k: v for nd in nodes.values() for k, v in nd.items()})
    base = cfg.get("variant_of")
    if base:   # 變體沿用原款貼圖與圖示：每個 UV 都要在原款已安裝的男版 .X 裡（同一張貼圖上同一點）
        B = xio.read_x(f"{MEDIA}/{BP}MDB_{base}_M.X")["UV"]
        for k, d in X.items():
            ok(np.abs(d["UV"][:, None] - B[None]).max(2).min(1).max() < 1e-6, f"MDB_{name}_{k}: UV 不在原款 {base} 的 UV 裡（貼圖對不上）")
    for look in () if base else ("Navy", "Olive"):
        p = f"{media}/textures/Clothes/Bag/MDB_{name}_{look}.png"
        n = TEX_SIZE[look]
        ok(os.path.exists(p) and Image.open(p).size == (n, n), f"{look} 貼圖不是 {n}×{n}")
        p = f"{media}/textures/Item_MDB_{name}_{look}.png"
        ok(os.path.exists(p) and Image.open(p).size == (32, 32) and Image.open(p).mode == "RGBA", f"{look} 圖示不是 32×32 RGBA")
    return fail, info


def _mutate(cfg, p, kind):
    d = xio.read_x(p)
    V, F, UV, N = d["V"].copy(), d["F"], d["UV"].copy(), d["N"]
    Wd = np.zeros((len(V), len(d["sw"])))
    bones = list(d["sw"])
    for j, (idx, w, _) in enumerate(d["sw"].values()):
        Wd[idx, j] = w
    if kind == "UV":
        UV[0] = (1.5, 0.5)
    elif kind == "原款UV":
        UV[0, 0] += 0.01
    elif kind == "穿模":
        if cfg["clearance"] == "closed":
            V[:, 2] -= 0.04
        else:   # 繞身體的：往身體中軸縮 30%（胸掛原版自己就貼進身體 2 cm，縮 15% 不夠）
            c = np.r_[0.0, 0.0, 0.02]
            V[:, [0, 2]] = c[[0, 2]] + (V[:, [0, 2]] - c[[0, 2]]) * 0.7
    elif kind == "底部":
        V[:, 1] -= 0.08
    elif kind == "頂點":       # 每個面角各自一份頂點；面少的款式（腰包 364 面）再重複一輪，超過 1100
        c = F.ravel()
        if len(c) <= MAX_VERTS:
            c = np.r_[c, c]
        V, UV, N, Wd, F = V[c], UV[c], N[c], Wd[c], np.arange(len(c)).reshape(-1, 3)
    W = {b: (np.nonzero(Wd[:, j])[0], Wd[np.nonzero(Wd[:, j])[0], j]) for j, b in enumerate(bones)}
    xio.write_skinned_x(PZ + "/" + cfg["worn"]["M"], p, V, N, UV, F, W, name=f"MDB_{cfg['name']}")
    if kind in ("權重", "反綁定"):  # 文字層級：換一根骨名、改第一個 SkinWeights 反綁定矩陣的最後一個數
        t = open(p, encoding="ascii", newline="").read()
        i = t.index("\n  SkinWeights {")   # 跳過檔頭的 template SkinWeights 宣告
        if kind == "權重":
            j = t.index('"', i); k = t.index('"', j + 1)
            t2 = t[:j + 1] + "Bip01_Head" + t[k:]
        else:
            j = t.index(";;", i)
            t2 = t[:j - 8] + "1.500000" + t[j:]
        assert t2 != t
        open(p, "w", encoding="ascii", newline="").write(t2)


def selftest(name):
    """植入違規：每一種都要被抓到。"""
    cfg = bags.get(name)
    expect = {"權重": "白名單", "反綁定": "反綁定矩陣", "UV": "UV 超出", "頂點": "頂點 >", "穿模": "穿模", "節點縮放": "不是單位矩陣"}
    if cfg.get("bedroll") is not None:
        expect["底部"] = "本體底部"
    if cfg.get("variant_of"):
        expect["原款UV"] = "貼圖對不上"
    for kind, msg in expect.items():
        tmp = tempfile.mkdtemp()
        shutil.copytree(out(name), tmp, dirs_exist_ok=True)
        if kind == "節點縮放":   # 換成原版地面 FBX（節點 1/36 或 1/12、轉 90°）
            shutil.copy(PZ + "/" + cfg["ground"]["fbx"], f"{tmp}/models_X/WorldItems/Clothing/MDB_{name}_Ground.fbx")
        else:
            _mutate(cfg, f"{tmp}/{BP}MDB_{name}_M.X", kind)
        fail, _ = check(name, tmp)
        shutil.rmtree(tmp)
        hit = [m for m in fail if msg in m]
        assert hit, f"植入「{kind}」沒被抓到；失敗清單：{fail}"
        print(f"selftest: 植入「{kind}」→ 抓到：{hit[0]}")


if __name__ == "__main__":
    name = sys.argv[1]
    if "--selftest" in sys.argv:
        selftest(name)
    fail, info = check(name, out(name))
    json.dump(info, open(os.path.join(temp(name), "verify_x.json"), "w"), indent=1, ensure_ascii=False)
    for k, v in info.items():
        print(k, v)
    if fail:
        print("VERIFY FAIL")
        for m in fail:
            print("  -", m)
        sys.exit(1)
    print(f"VERIFY OK（穿戴 {info[f'MDB_{name}_M']['verts']} 頂點，目標 ≤{TARGET_VERTS}）")
