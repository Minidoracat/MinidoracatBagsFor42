"""第 2 段（純 Python）：低模本體＋原版肩帶 → 貼圖、權重、男／女／右手／左手四份 .X。
輸入 temp/bags/low_body.npz、bake_*.png（第 1 段）；輸出 temp/bags/out/media/...（MOD 同結構）與 final_mesh.npz。
"""
import json
import os
import numpy as np
from PIL import Image

from common import BELT0, OUT, PZ, STRAP0, TEMP, fit_affine, xio

BP = PZ + "/models_X/Skinned/BackPacks/"
TPL = {k: BP + v for k, v in dict(M="M_HikingBag.x", F="F_HikingBag.x", R="HikingBag_RHand.x", L="HikingBag_LHand.x").items()}
BONES = ["Bip01_BackPack", "Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_R_Clavicle"]
TEX = 256
# 肩帶 UV 島：原版圖集的矩形 → 新圖集右側長條（第二條轉 90°）。.X 的 v 由上往下
STRAP_ISLANDS = [  # (原版頂點範圍, 原版 UV 矩形 u0,v0,u1,v1, 新矩形, 轉 90°)
    ((251, 326), (0.010, 0.120, 0.136, 0.477), (0.872, 0.010, 0.992, 0.490), False),
    ((326, 399), (0.010, 0.005, 0.334, 0.124), (0.872, 0.510, 0.992, 0.990), True),
]


def corr_from_faces(M, T):
    """原版 M 與 T 的面順序相同（第 0 步實測：F、RHand 的 412 面逐角 UV 相同）→ 頂點對應 M→T。"""
    assert (np.abs(M["UV"][M["F"]] - T["UV"][T["F"]]).max() < 1e-6), "面順序不同，不能逐角對應"
    c = np.full(len(M["V"]), -1)
    c[M["F"].ravel()] = T["F"].ravel()
    assert (c >= 0).all()
    return c


def weights(X, bones):
    W = np.zeros((len(X["V"]), len(bones)))
    for j, b in enumerate(bones):
        if b in X["sw"]:
            idx, w, _ = X["sw"][b]
            W[idx, j] = w
    return W


def vertex_normals(V, F):
    n = np.zeros_like(V)
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])  # 面積加權
    for k in range(3):
        np.add.at(n, F[:, k], fn)
    z = np.linalg.norm(n, axis=1) < 1e-12
    n[z] = V[z] - V.mean(0)  # 減面後有幾個點的面法線剛好互相抵消（折起的尖角）：改用由中心往外
    return n / np.linalg.norm(n, axis=1, keepdims=True)


def limit4(W):
    """每頂點最多 4 個權重（ImportedSkinnedMesh.java:19-52 只收 4 個）、去掉 <0.01、正規化。"""
    W = W.copy()
    W[W < 0.01] = 0
    order = np.argsort(-W, axis=1)
    for i in range(len(W)):
        W[i, order[i, 4:]] = 0
    return W / W.sum(1, keepdims=True)


def recolor_navy(img):
    """Tripo 的亮寶藍 → 原稿深藍（A-stars-v2）：藍色調的布料降飽和、壓暗，黑、灰、金不動。"""
    a = np.asarray(img.convert("RGB")).astype(float) / 255
    mx, mn = a.max(2), a.min(2)
    v, s = mx, np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    blue = (a[..., 2] >= a[..., 0]) & (a[..., 2] >= a[..., 1]) & (a[..., 2] - a[..., 0] > 0.04)
    k = np.clip((s - 0.15) / 0.2, 0, 1) * blue                # 越藍越完整套用，灰黑的織帶不受影響
    s2, v2 = s * 0.70, v * 0.82
    # 色相固定 0.625（原稿量到 0.62）：h·6=3.75 落在 HSV 第 3 扇區 → (p, q, v)，f=0.75
    out = np.stack([v2 * (1 - s2), v2 * (1 - s2 * 0.75), v2], -1)
    res = a * (1 - k[..., None]) + out * k[..., None]
    return Image.fromarray((res.clip(0, 1) * 255 + 0.5).astype(np.uint8))


def strap_paint(tex, src):
    """原版肩帶島的像素仿射搬到新矩形，轉成黑色尼龍（亮度 ×0.32＋底 0.06）。"""
    a = np.asarray(tex).copy()
    s = np.asarray(src.convert("RGB")).astype(float) / 255
    N = a.shape[0]
    for _, (su0, sv0, su1, sv1), (du0, dv0, du1, dv1), rot in STRAP_ISLANDS:
        x0, x1, y0, y1 = int(du0 * N) - 2, int(np.ceil(du1 * N)) + 2, int(dv0 * N) - 2, int(np.ceil(dv1 * N)) + 2
        yy, xx = np.mgrid[y0:y1, x0:x1]
        u, v = (xx + 0.5) / N, (yy + 0.5) / N
        fu, fv = (u - du0) / (du1 - du0), (v - dv0) / (dv1 - dv0)
        if rot:
            fu, fv = fv, fu
        su, sv = su0 + fu * (su1 - su0), sv0 + fv * (sv1 - sv0)
        px = np.clip((su * s.shape[1]).astype(int), 0, s.shape[1] - 1)
        py = np.clip((sv * s.shape[0]).astype(int), 0, s.shape[0] - 1)
        lum = s[py, px] @ [0.299, 0.587, 0.114]
        c = (0.06 + 0.32 * lum)[..., None] * [1.0, 1.0, 1.05]
        a[max(y0, 0):y1, max(x0, 0):x1] = (c.clip(0, 1) * 255).astype(np.uint8)[max(0, -y0):, max(0, -x0):]
    return Image.fromarray(a)


def strap_uv(UV):
    UV = UV.copy()
    for (i0, i1), (su0, sv0, su1, sv1), (du0, dv0, du1, dv1), rot in STRAP_ISLANDS:
        u, v = UV[i0:i1, 0], UV[i0:i1, 1]
        assert u.min() >= su0 and u.max() <= su1 and v.min() >= sv0 and v.max() <= sv1, "肩帶島超出來源矩形"
        fu, fv = (u - su0) / (su1 - su0), (v - sv0) / (sv1 - sv0)
        if rot:
            fu, fv = fv, fu
        UV[i0:i1] = np.c_[du0 + fu * (du1 - du0), dv0 + fv * (dv1 - dv0)]
    return UV


def main():
    os.makedirs(OUT + "/models_X/Skinned/BackPacks", exist_ok=True)
    os.makedirs(OUT + "/textures/Clothes/Bag", exist_ok=True)
    van = {k: xio.read_x(p) for k, p in TPL.items()}
    M = van["M"]
    corr = {k: corr_from_faces(M, van[k]) for k in ("F", "R")}

    # 本體：依 (頂點, UV) 拆點；Blender UV v 朝上 → .X 朝下
    d = np.load(os.path.join(TEMP, "low_body.npz"))
    bV, bF, bUVc = d["V"], d["F"], d["UV"].copy()
    bUVc[..., 1] = 1 - bUVc[..., 1]
    key, src, F = {}, [], np.zeros_like(bF)
    for fi in range(len(bF)):
        for k in range(3):
            kk = (bF[fi, k], round(bUVc[fi, k, 0], 6), round(bUVc[fi, k, 1], 6))
            if kk not in key:
                key[kk] = len(src); src.append(kk)
            F[fi, k] = key[kk]
    BV = bV[[s[0] for s in src]]
    BUV = np.array([s[1:] for s in src])
    BN = vertex_normals(bV, bF)[[s[0] for s in src]]
    cen = bV.mean(0)
    out_ok = (np.einsum("ij,ij->i", np.cross(bV[bF[:, 1]] - bV[bF[:, 0]], bV[bF[:, 2]] - bV[bF[:, 0]]), bV[bF].mean(1) - cen) > 0).mean()
    print(f"body: {len(bV)} welded -> {len(BV)} split verts, {len(F)} tris; faces facing out {out_ok:.1%}")

    # 肩帶：原版 M 的 251-398 與面 264-411，UV 搬到新矩形
    sidx = np.arange(STRAP0, len(M["V"]))
    sF = M["F"][264:] - STRAP0
    assert sF.min() == 0 and (M["F"][:264] < STRAP0).all()
    SUV = strap_uv(M["UV"])[STRAP0:]

    nb = len(BV)
    UV = np.r_[BUV, SUV]
    FF = np.r_[F, sF + nb]
    assert UV.min() >= 0 and UV.max() <= 1

    # 權重：本體每頂點取原版本體（不含腰帶）最近 4 點、距離反比；各版本取該版本自己的權重（同序）
    body_ref = np.arange(BELT0)
    dist = np.linalg.norm(BV[:, None] - M["V"][body_ref][None], axis=2)
    nn = np.argsort(dist, 1)[:, :4]
    w_idw = 1 / np.maximum(np.take_along_axis(dist, nn, 1), 1e-4) ** 2
    w_idw /= w_idw.sum(1, keepdims=True)

    def body_weights(T, bones, c=None):
        WT = weights(T, bones)
        Wv = WT if c is None else WT[c]                   # 以 M 的頂點序排列
        return limit4(np.einsum("ik,ikj->ij", w_idw, Wv[body_ref][nn])), Wv[STRAP0:]

    meshes = {}
    # 男
    Wb, Ws = body_weights(M, BONES)
    meshes["M"] = dict(V=np.r_[BV, M["V"][sidx]], N=np.r_[BN, M["N"][sidx]], W=np.r_[Wb, Ws], bones=BONES)
    # 女、右手：本體用原版 M→T 的仿射擬合（只用本體頂點），肩帶用原版 T 的同序頂點
    resid = {}
    for k, bones in (("F", BONES), ("R", ["Bip01_R_Hand", "Bip01_Prop1"])):
        T, c = van[k], corr[k]
        L, t, r, out = fit_affine(M["V"][body_ref], T["V"][c[body_ref]])
        inl = np.delete(r, out)
        resid[k] = dict(max=float(inl.max()), rms=float(np.sqrt((inl ** 2).mean())), outliers={int(i): float(r[i]) for i in out},
                        sv=np.linalg.svd(L, compute_uv=False).round(5).tolist())
        print(f"fit M->{k}: inlier residual max {inl.max() * 1000:.2f}, rms {resid[k]['rms'] * 1000:.2f} (×0.001 units)；"
              f"outliers {resid[k]['outliers']}；singular values {resid[k]['sv']}, t {t.round(4)}")
        nrm = BN @ np.linalg.inv(L).T
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
        Wb, Ws = body_weights(T, bones, c)
        meshes[k] = dict(V=np.r_[BV @ L + t, T["V"][c[sidx]]], N=np.r_[nrm, T["N"][c[sidx]]], W=np.r_[Wb, Ws], bones=bones)
    # 左手：原版 LHand 的頂點＝RHand 點對稱（−V）、法線取負（第 0 步實測逐點相同）；點對稱翻手性 → 面反轉。UV 不動
    R = meshes["R"]
    meshes["L"] = dict(V=-R["V"], N=-R["N"], W=R["W"], bones=["Bip01_L_Hand", "Bip01_Prop2"], flip=True)

    names = dict(M="MDB_DayPack_M", F="MDB_DayPack_F", R="MDB_DayPack_RHand", L="MDB_DayPack_LHand")
    for k, m in meshes.items():
        W = m["W"]
        Wd = {b: (np.nonzero(W[:, j])[0], W[np.nonzero(W[:, j])[0], j]) for j, b in enumerate(m["bones"]) if W[:, j].any()}
        Fk = FF[:, [0, 2, 1]] if m.get("flip") else FF
        xio.write_skinned_x(TPL[k], f"{OUT}/models_X/Skinned/BackPacks/{names[k]}.X", m["V"], m["N"], UV, Fk, Wd, name="MDB_DayPack")
        print(f"{names[k]}.X: {len(m['V'])} verts, {len(FF)} tris, bones {list(Wd)}")

    # 貼圖：1024 烘焙 → 調色 → 肩帶 → 縮 256
    van_tex = Image.open(PZ + "/textures/Clothes/Bag/HikingBagBlue.png")
    for look, fix in (("Navy", recolor_navy), ("Olive", lambda i: i.convert("RGB"))):
        img = strap_paint(fix(Image.open(os.path.join(TEMP, f"bake_{look.lower()}.png"))), van_tex)
        img.resize((TEX, TEX), Image.LANCZOS).save(f"{OUT}/textures/Clothes/Bag/MDB_DayPack_{look}.png")
        img.save(os.path.join(TEMP, f"tex_{look}_1024.png"))

    np.savez(os.path.join(TEMP, "final_mesh.npz"), V=meshes["M"]["V"], N=meshes["M"]["N"], F=FF, UV=UV, nbody=nb)
    json.dump(resid, open(os.path.join(TEMP, "fit_residuals.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
