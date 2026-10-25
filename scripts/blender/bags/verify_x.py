"""日行背包產物逐項斷言（研究第 9 步）。build.py 每次建置都跑，任一項失敗就讓建置失敗。
uv run --with numpy --with pillow scripts/blender/bags/verify_x.py [--selftest]
  --selftest：把產物複製一份、植入 5 種違規，確認每一種都被抓到。
"""
import json, os, shutil, sys, tempfile
import numpy as np
from PIL import Image

from common import OUT, PZ, TEMP, xio

BP = "models_X/Skinned/BackPacks/"
VAN = {"MDB_DayPack_M": "M_HikingBag.x", "MDB_DayPack_F": "F_HikingBag.x",
       "MDB_DayPack_RHand": "HikingBag_RHand.x", "MDB_DayPack_LHand": "HikingBag_LHand.x"}
WORN_BONES = {"Bip01_BackPack", "Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_R_Clavicle"}
HAND_BONES = {"MDB_DayPack_RHand": {"Bip01_R_Hand", "Bip01_Prop1"}, "MDB_DayPack_LHand": {"Bip01_L_Hand", "Bip01_Prop2"}}
MAX_VERTS, TARGET_VERTS = 1100, 600
BEDROLL = np.array([0.0, 0.509, 0.167])   # 睡袋掛點（研究第 5 點，bedroll_bottom 經反綁定換算 [INFERENCE]）


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


def check(media):
    fail, info = [], {}

    def ok(cond, msg):
        if not cond:
            fail.append(msg)

    X = {}
    for name, van in VAN.items():
        p = f"{media}/{BP}{name}.X"
        if not os.path.exists(p):
            fail.append(f"{name}.X 不存在"); continue
        d = X[name] = xio.read_x(p)
        T = xio.read_x(PZ + "/models_X/Skinned/BackPacks/" + van)
        nv = len(d["V"])
        ok(nv <= MAX_VERTS, f"{name}: {nv} 頂點 > {MAX_VERTS}")
        bones = set(d["sw"])
        ok(bones <= HAND_BONES.get(name, WORN_BONES) and len(bones) <= 5, f"{name}: 骨頭 {sorted(bones)} 不在白名單")
        cnt, ws = np.zeros(nv, int), np.zeros(nv)
        for b, (idx, w, ibm) in d["sw"].items():
            cnt[idx] += 1; ws[idx] += w
            ok(b in T["sw"] and np.array_equal(ibm, T["sw"][b][2]), f"{name}: {b} 反綁定矩陣和原版 {van} 不同")
        ok(cnt.max() <= 4, f"{name}: 每頂點最多 {cnt.max()} 個權重 > 4")
        ok(np.abs(ws - 1).max() < 2e-3, f"{name}: 權重和 {ws.min():.4f}–{ws.max():.4f} 不是 1")
        ok(d["UV"].min() >= 0 and d["UV"].max() <= 1, f"{name}: UV 超出 [0,1]")
        ok(np.abs(np.linalg.norm(d["N"], axis=1) - 1).max() < 1e-3, f"{name}: 法線不是單位長")
        fn = np.cross(d["V"][d["F"][:, 1]] - d["V"][d["F"][:, 0]], d["V"][d["F"][:, 2]] - d["V"][d["F"][:, 0]])
        out = (np.einsum("ij,ij->i", fn, d["N"][d["F"]].sum(1)) > 0).mean()
        ok(out >= 0.95, f"{name}: 只有 {out:.1%} 的面繞序和頂點法線同向（右手定則朝外）")
        info[name] = dict(verts=nv, tris=len(d["F"]), bones=sorted(bones), max_influences=int(cnt.max()), faces_out=round(float(out), 3),
                          bbox=[d["V"].min(0).round(4).tolist(), d["V"].max(0).round(4).tolist()])
    if len(X) == 4:
        uv = X["MDB_DayPack_M"]["UV"]
        for k, d in X.items():
            ok(len(d["UV"]) == len(uv) and np.abs(d["UV"] - uv).max() < 1e-6, f"{k}: UV 和男版不同")
        g = np.load(os.path.join(TEMP, "ground_check.npz"))["UV"]   # FBX 讀回是 float32：用距離比，不用集合
        dist = lambda A, B: np.abs(A[:, None] - B[None]).max(2).min(1).max()
        ok(max(dist(g, uv), dist(uv, g)) < 1e-4, "地面 FBX 的 UV 和穿戴模型不同")
        # 穿戴版位置：本體（UV 在 u<0.866 的面；右側長條是肩帶）底部、外側、睡袋點；身體頂點不能在封閉的本體裡
        for k, body in (("MDB_DayPack_M", "MaleBody.x"), ("MDB_DayPack_F", "FemaleBody.x")):
            d = X[k]
            bt = d["F"][(d["UV"][d["F"]][..., 0] < 0.866).all(1)]
            b = d["V"][np.unique(bt)]
            ok(0.52 <= b[:, 1].min() <= 0.57, f"{k}: 本體底部 y={b[:, 1].min():.4f} 不在 0.52–0.57（睡袋掛點在底下）")
            ok(b[:, 2].max() >= 0.10, f"{k}: 本體外側 z={b[:, 2].max():.4f} < 0.10")
            ok(BEDROLL[1] < b[:, 1].min(), f"{k}: 睡袋點 y={BEDROLL[1]} 埋進本體")
            B = xio.read_x(PZ + "/models_X/Skinned/" + body)["V"]
            n, first = ray_z(B, d["V"], bt)
            ok((n % 2 == 0).all(), f"{k}: 身體有 {int((n % 2).sum())} 個頂點在背包本體裡（穿模）")
            clr = first - B[:, 2]
            info[k].update(bottom_y=round(float(b[:, 1].min()), 4), outer_z=round(float(b[:, 2].max()), 4),
                           body_inside=int((n % 2).sum()), min_clearance_behind_body=round(float(clr[n % 2 == 0].min()), 4))
        gj = json.load(open(os.path.join(TEMP, "ground.json")))
        o, v = np.array(gj["ours_pz_bbox"]), np.array(gj["vanilla_pz_bbox"])
        ok(np.abs((o[1] - o[0]) / (v[1] - v[0]) - 1).max() < 0.1, f"地面 FBX 尺寸 {o[1] - o[0]} 和原版 {v[1] - v[0]} 差超過 10%")
        ok(abs(o[0][2]) < 0.005, f"地面 FBX 最低點 {o[0][2]:.4f} 沒有貼地")
        ok(all(abs(x - y) < 1e-6 for x, y in zip(gj["fbx_props"]["Lcl Scaling"], (1, 1, 1))), "地面 FBX 節點縮放不是 1")
        info["ground"] = dict(bbox=gj["ours_pz_bbox"], vanilla=gj["vanilla_pz_bbox"])
    for look in ("Navy", "Olive"):
        p = f"{media}/textures/Clothes/Bag/MDB_DayPack_{look}.png"
        ok(os.path.exists(p) and Image.open(p).size == (256, 256), f"{look} 貼圖不是 256×256")
        p = f"{media}/textures/Item_MDB_DayPack_{look}.png"
        ok(os.path.exists(p) and Image.open(p).size == (32, 32) and Image.open(p).mode == "RGBA", f"{look} 圖示不是 32×32 RGBA")
    return fail, info


def _mutate(p, kind):
    d = xio.read_x(p)
    V, F, UV, N = d["V"].copy(), d["F"], d["UV"].copy(), d["N"]
    Wd = np.zeros((len(V), len(d["sw"])))
    bones = list(d["sw"])
    for j, (idx, w, _) in enumerate(d["sw"].values()):
        Wd[idx, j] = w
    tpl = PZ + "/models_X/Skinned/BackPacks/M_HikingBag.x"
    if kind == "UV":
        UV[0] = (1.5, 0.5)
    elif kind == "穿模":
        V[:, 2] -= 0.04
    elif kind == "底部":
        V[:, 1] -= 0.08
    elif kind == "頂點":       # 每個面角各自一份頂點 → 1704 點，超過 1100
        c = F.ravel()
        V, UV, N, Wd, F = V[c], UV[c], N[c], Wd[c], np.arange(len(c)).reshape(-1, 3)
    W = {b: (np.nonzero(Wd[:, j])[0], Wd[np.nonzero(Wd[:, j])[0], j]) for j, b in enumerate(bones)}
    xio.write_skinned_x(tpl, p, V, N, UV, F, W, name="MDB_DayPack")
    if kind in ("權重", "反綁定"):  # 文字層級：換骨名、改第一個 SkinWeights 反綁定矩陣的最後一個數
        t = open(p, encoding="ascii", newline="").read()
        i = t.index("\n  SkinWeights {")   # 跳過檔頭的 template SkinWeights 宣告
        if kind == "權重":
            t2 = t[:i] + t[i:].replace('"Bip01_BackPack";', '"Bip01_Head";', 1)
        else:
            j = t.index(";;", i)
            t2 = t[:j - 8] + "1.500000" + t[j:]
        assert t2 != t
        open(p, "w", encoding="ascii", newline="").write(t2)


def selftest():
    """植入違規：每一種都要被抓到。"""
    expect = {"權重": "白名單", "反綁定": "反綁定矩陣", "UV": "UV 超出", "底部": "本體底部", "頂點": "頂點 >", "穿模": "穿模"}
    for kind, msg in expect.items():
        tmp = tempfile.mkdtemp()
        shutil.copytree(OUT, tmp, dirs_exist_ok=True)
        _mutate(f"{tmp}/{BP}MDB_DayPack_M.X", kind)
        fail, _ = check(tmp)
        shutil.rmtree(tmp)
        hit = [m for m in fail if msg in m]
        assert hit, f"植入「{kind}」沒被抓到；失敗清單：{fail}"
        print(f"selftest: 植入「{kind}」→ 抓到：{hit[0]}")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    fail, info = check(OUT)
    json.dump(info, open(os.path.join(TEMP, "verify_x.json"), "w"), indent=1, ensure_ascii=False)
    for k, v in info.items():
        print(k, v)
    if fail:
        print("VERIFY FAIL")
        for m in fail:
            print("  -", m)
        sys.exit(1)
    print(f"VERIFY OK（穿戴 {info['MDB_DayPack_M']['verts']} 頂點，目標 ≤{TARGET_VERTS}）")
