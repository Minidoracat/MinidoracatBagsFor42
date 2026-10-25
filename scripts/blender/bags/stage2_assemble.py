"""第 2 段（純 Python）：低模本體＋沿用的原版子網格 → 貼圖、權重、男／女（／ALT）／右手／左手 .X。
輸入 temp/bags/<款>/low_body.npz、bake_*.png（第 1 段）；輸出 temp/bags/<款>/out/media/...（MOD 同結構）與 final_mesh.npz。
深藍調色參數是 common.NAVY_S／NAVY_V（7 款共用；2026-10-25 使用者選「中」0.70／1.00）。
uv run --with numpy --with pillow python stage2_assemble.py <款>
"""
import json
import os
import sys
import numpy as np
from PIL import Image

import bags
from common import NAVY_S, NAVY_V, PZ, fit_affine, keep_groups, out, sel, temp, xio

TEX = 256


# ---- 原版各版本之間對點 ----
def corr_from_faces(M, T):
    """面順序相同（日行包實測：F、RHand 的 412 面逐角 UV 相同）→ 頂點對應 M→T。"""
    assert (np.abs(M["UV"][M["F"]] - T["UV"][T["F"]]).max() < 1e-6), "面順序不同，不能逐角對應"
    c = np.full(len(M["V"]), -1)
    c[M["F"].ravel()] = T["F"].ravel()
    assert (c >= 0).all()
    return c


def corr_from_uv(M, T):
    """同 UV（<2e-3）對點。原版對稱零件常共用 UV（遠征包 8 點、信差包 322 點有歧義）：
    先用只有一個位置的點擬合仿射，歧義的點挑離仿射預測最近的候選，再擬合一次。
    最後歧義點的位移和最近 8 個鄰點的位移中位數差 >8 cm 單位的當錯配丟掉（信差包女版 4 點、右手 1 點差 0.17：兩個候選都不對）；
    唯一對點不丟（遠征包右手第 23 點是捲起的肩帶，和鄰點本來就不同向）。
    對不到的點回 -1。"""
    d = np.abs(M["UV"][:, None] - T["UV"][None]).max(2)
    cand = [np.nonzero(row < 2e-3)[0] for row in d]
    c = np.full(len(M["V"]), -1)
    uniq = np.zeros(len(M["V"]), bool)
    for i, k in enumerate(cand):
        if len(k) and np.ptp(T["V"][k], axis=0).max() < 1e-4:
            c[i], uniq[i] = k[0], True
    for _ in range(2):
        m = c >= 0
        L, t, _, _ = fit_affine(M["V"][m], T["V"][c[m]])
        pred, predN = M["V"] @ L + t, M["N"] @ np.linalg.inv(L).T
        for i, k in enumerate(cand):
            if len(k) and not uniq[i]:
                # 雙面薄片（信差包背帶）正反兩面同 UV、位置只差厚度：法線反向的候選加 1 單位懲罰，才不會挑到背面
                score = np.linalg.norm(T["V"][k] - pred[i], axis=1) + (T["N"][k] @ predN[i] < 0)
                c[i] = k[score.argmin()]
    m = np.nonzero(c >= 0)[0]
    disp = T["V"][c[m]] - M["V"][m]
    nn = np.argsort(np.linalg.norm(M["V"][m][:, None] - M["V"][m][None], axis=2), 1)[:, 1:9]
    bad = m[np.linalg.norm(disp - np.median(disp[nn], axis=1), axis=1) > 0.08]
    c[bad[~uniq[bad]]] = -1
    return c


def weights(X, bones, merge):
    """原版權重換成白名單骨頭；merge 的骨頭併進指定骨頭；兩邊都沒列的骨頭直接報錯（不悄悄丟權重）。"""
    stray = set(X["sw"]) - set(bones) - set(merge)
    assert not stray, f"模板有骨頭 {stray} 沒列在 bones 或 merge"
    W = np.zeros((len(X["V"]), len(bones)))
    for b, (idx, w, _) in X["sw"].items():
        W[idx, bones.index(merge.get(b, b))] += w
    return W


def idw(dist, k=4):
    nn = np.argsort(dist, 1)[:, :k]
    w = 1 / np.maximum(np.take_along_axis(dist, nn, 1), 1e-4) ** 2
    return nn, w / w.sum(1, keepdims=True)


def target_arrays(M, T, c, bones, merge):
    """T 的位置、法線、權重，排成 M 的頂點序；對不到的點用已對到的點補（仿射＋最近 4 點殘差，權重距離反比）。"""
    TV, TN, TW = np.zeros_like(M["V"]), np.zeros_like(M["V"]), np.zeros((len(M["V"]), len(bones)))
    m = c >= 0
    WT = weights(T, bones, merge)
    TV[m], TN[m], TW[m] = T["V"][c[m]], T["N"][c[m]], WT[c[m]]
    if not m.all():
        L, t, _, _ = fit_affine(M["V"][m], TV[m])
        nn, w = idw(np.linalg.norm(M["V"][~m][:, None] - M["V"][m][None], axis=2))
        res = (TV[m] - (M["V"][m] @ L + t))[nn]
        TV[~m] = M["V"][~m] @ L + t + np.einsum("ik,ikj->ij", w, res)
        n = M["N"][~m] @ np.linalg.inv(L).T
        TN[~m] = n / np.linalg.norm(n, axis=1, keepdims=True)
        TW[~m] = np.einsum("ik,ikj->ij", w, TW[m][nn])
    return TV, TN, TW


def deform(cfg, M, TV, ref, P, PN):
    """本體頂點 P（M 空間）搬到 T：affine＝參考點仿射；field＝全部點仿射＋最近 4 點的殘差位移；
    field_ref＝仿射與殘差都只用參考點（信差包：手持模型把長背帶捲成一團，全部點擬合的仿射在一軸壓到 0.15）。回 (P', N', 殘差摘要)。"""
    pts = np.arange(len(M["V"])) if cfg["deform"] == "field" else ref
    L, t, r, outl = fit_affine(M["V"][pts], TV[pts])
    inl = np.delete(r, outl)
    info = dict(max=float(inl.max()), rms=float(np.sqrt((inl ** 2).mean())), outliers={int(pts[i]): float(r[i]) for i in outl},
                sv=np.linalg.svd(L, compute_uv=False).round(5).tolist(), det=float(np.linalg.det(L)))
    Q = P @ L + t
    if cfg["deform"] != "affine":
        nn, w = idw(np.linalg.norm(P[:, None] - M["V"][pts][None], axis=2))
        disp = np.einsum("ik,ikj->ij", w, (TV[pts] - (M["V"][pts] @ L + t))[nn])
        Q = Q + disp
        info["field_max"] = float(np.linalg.norm(disp, axis=1).max())
    n = PN @ np.linalg.inv(L).T
    return Q, n / np.linalg.norm(n, axis=1, keepdims=True), info


def icp_affine(A, B, iters=30):
    """沒有對應點時，把點雲 A 對齊到 B（原版左右手）：先試 8 種軸向鏡像當起點，最近點＋仿射最小平方疊代；回 (L, t, 最近點殘差)。"""
    best = None
    ca, cb = A.mean(0), B.mean(0)
    for sx in (1, -1):
        for sy in (1, -1):
            for sz in (1, -1):
                L = np.diag([sx, sy, sz]).astype(float); t = cb - ca @ L
                for _ in range(iters):
                    P = A @ L + t
                    j = np.linalg.norm(P[:, None] - B[None], axis=2).argmin(1)
                    L, t, _, _ = fit_affine(A, B[j])
                r = np.linalg.norm((A @ L + t)[:, None] - B[None], axis=2).min(1)
                if best is None or r.max() < best[2].max():
                    best = (L, t, r)
    return best


# ---- 貼圖 ----
def recolor_navy(img):
    """Tripo 的亮寶藍 → 原稿深藍（A-stars-v2）：藍色調的布料 飽和度×NAVY_S、亮度×NAVY_V，黑、灰、金不動。"""
    a = np.asarray(img.convert("RGB")).astype(float) / 255
    mx, mn = a.max(2), a.min(2)
    v, s = mx, np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    blue = (a[..., 2] >= a[..., 0]) & (a[..., 2] >= a[..., 1]) & (a[..., 2] - a[..., 0] > 0.04)
    k = np.clip((s - 0.15) / 0.2, 0, 1) * blue                # 越藍越完整套用，灰黑的織帶不受影響
    s2, v2 = s * NAVY_S, v * NAVY_V
    # 色相固定 0.625（原稿量到 0.62）：h·6=3.75 落在 HSV 第 3 扇區 → (p, q, v)，f=0.75
    out_ = np.stack([v2 * (1 - s2), v2 * (1 - s2 * 0.75), v2], -1)
    res = a * (1 - k[..., None]) + out_ * k[..., None]
    return Image.fromarray((res.clip(0, 1) * 255 + 0.5).astype(np.uint8))


def keep_paint(tex, src, islands):
    """沿用的原版 UV 島：原版貼圖像素仿射搬到新矩形，轉成黑色尼龍（亮度 ×0.32＋底 0.06）。"""
    a = np.asarray(tex).copy()
    s = np.asarray(src.convert("RGB")).astype(float) / 255
    N = a.shape[0]
    for (su0, sv0, su1, sv1), (du0, dv0, du1, dv1), rot in islands:
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


def islands_of(cfg, M):
    """(原版頂點索引, 原版 UV 矩形, 新矩形, 轉 90°)。設定沒寫就自動：外框放寬 0.006，在右側長條由上往下等分，寬的島轉 90°。"""
    groups = keep_groups(cfg, M)
    if not groups:
        return []
    if cfg.get("islands"):
        return [(g,) + tuple(i) for g, i in zip(groups, cfg["islands"])]
    n, u0, gap = len(groups), cfg["body_u"] + 0.012, 0.02
    h = (0.98 - gap * (n - 1)) / n
    res = []
    for k, g in enumerate(groups):
        lo_, hi_ = M["UV"][g].min(0) - 0.006, M["UV"][g].max(0) + 0.006
        src = (max(lo_[0], 0), max(lo_[1], 0), min(hi_[0], 1), min(hi_[1], 1))
        dst = (u0, 0.010 + k * (h + gap), 0.992, 0.010 + k * (h + gap) + h)
        res.append((g, src, dst, (src[2] - src[0]) > (src[3] - src[1])))
    return res


def keep_uv(UV, isl):
    UV = UV.copy()
    for g, (su0, sv0, su1, sv1), (du0, dv0, du1, dv1), rot in isl:
        u, v = UV[g, 0], UV[g, 1]
        assert u.min() >= su0 and u.max() <= su1 and v.min() >= sv0 and v.max() <= sv1, "沿用的 UV 島超出來源矩形"
        fu, fv = (u - su0) / (su1 - su0), (v - sv0) / (sv1 - sv0)
        if rot:
            fu, fv = fv, fu
        UV[g] = np.c_[du0 + fu * (du1 - du0), dv0 + fv * (dv1 - dv0)]
    return UV


# ---- 幾何 ----
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


def split_body(d, thin=False):
    """依 (頂點, UV) 拆點；Blender UV v 朝上 → .X 朝下。
    thin（胸掛）：薄帶減面後正反兩面共用頂點，焊接法線互相抵消；和拆點後自己那面的法線夾角超過 60° 的點改用拆點法線。"""
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
    if thin:
        NS = vertex_normals(BV, F)
        bad = np.einsum("ij,ij->i", BN, NS) < 0.5
        BN[bad] = NS[bad]
        print(f"thin: {int(bad.sum())} verts use split normals")
    cen = bV.mean(0)
    out_ok = (np.einsum("ij,ij->i", np.cross(bV[bF[:, 1]] - bV[bF[:, 0]], bV[bF[:, 2]] - bV[bF[:, 0]]), bV[bF].mean(1) - cen) > 0).mean()
    print(f"body: {len(bV)} welded -> {len(BV)} split verts, {len(F)} tris; faces facing out {out_ok:.1%}")
    return BV, BUV, BN, F


def main(name):
    cfg = bags.get(name)
    TEMP, OUT = temp(name), out(name)
    os.makedirs(OUT + "/models_X/Skinned/BackPacks", exist_ok=True)
    os.makedirs(OUT + "/textures/Clothes/Bag", exist_ok=True)
    tpl = {"M": cfg["worn"]["M"], "F": cfg["worn"]["F"]}
    if cfg.get("alt"):
        tpl.update(AM=cfg["alt"]["M"], AF=cfg["alt"]["F"])
    if cfg.get("hands"):
        tpl.update(R=cfg["hands"]["R"], L=cfg["hands"]["L"])
    tpl = {k: PZ + "/" + v for k, v in tpl.items()}
    van = {k: xio.read_x(p) for k, p in tpl.items()}
    M = van["M"]

    BV, BUV, BN, F = split_body(np.load(os.path.join(TEMP, "low_body.npz")), thin=cfg.get("thin", False))
    kidx = np.concatenate(keep_groups(cfg, M)) if cfg["keep"] else np.zeros(0, int)
    local = np.full(len(M["V"]), -1); local[kidx] = np.arange(len(kidx))
    kF = local[M["F"][np.isin(M["F"], kidx).all(1)]]
    isl = islands_of(cfg, M)
    nb = len(BV)
    UV = np.r_[BUV, keep_uv(M["UV"], isl)[kidx]]
    FF = np.r_[F, kF + nb]
    assert UV.min() >= 0 and UV.max() <= 1

    # 權重：本體每頂點取原版參考點（weight_ref）最近 4 點、距離反比；各版本取該版本自己的權重（排成 M 的頂點序）
    ref = sel(M, cfg["weight_ref"])
    nn, w_idw = idw(np.linalg.norm(BV[:, None] - M["V"][ref][None], axis=2))
    bones, merge = cfg["bones"], cfg["merge"]
    hand_bones = {"R": ["Bip01_R_Hand", "Bip01_Prop1"], "L": ["Bip01_L_Hand", "Bip01_Prop2"]}

    meshes, resid = {}, {}
    WM = weights(M, bones, merge)

    def keep_w(W):
        """沿用子網格照原版權重；原版超過 4 個權重的點（信差包背帶有 5 個）才砍到 4 個，其餘原樣（日行包、遠征包位元組不變）。"""
        W = W.copy()
        many = (W > 0).sum(1) > 4
        W[many] = limit4(W[many])
        return W

    def keep_smooth(TV):
        """keep_from="smooth"：沿用子網格不直接取對到的原版點，而是男版位置＋最近 8 個原版點位移的中位數，法線照變形後的面重算。
        信差包背帶是雙面薄片、正反同 UV，逐點對應會讓正反兩面塌到同一層（女版 23%、手持 43% 的面和法線反向）。"""
        disp = TV - M["V"]
        nn8 = np.argsort(np.linalg.norm(M["V"][kidx][:, None] - M["V"][None], axis=2), 1)[:, :8]
        V = M["V"][kidx] + np.median(disp[nn8], axis=1)
        return V, vertex_normals(V, kF)

    meshes["M"] = dict(V=np.r_[BV, M["V"][kidx]], N=np.r_[BN, M["N"][kidx]],
                       W=np.r_[limit4(np.einsum("ik,ikj->ij", w_idw, WM[ref][nn])), keep_w(WM[kidx])], bones=bones)
    targets = [k for k in ("F", "AM", "AF", "R") if k in van]
    for k in targets:
        T = van[k]
        bk = hand_bones["R"] if k == "R" else bones
        c = corr_from_faces(M, T) if cfg["corr"] == "faces" else corr_from_uv(M, T)
        TV, TN, TW = target_arrays(M, T, c, bk, {} if k == "R" else merge)
        V2, N2, info = deform(cfg, M, TV, ref, BV, BN)
        info["matched"] = int((c >= 0).sum())
        resid[k] = info
        print(f"fit M->{k}: {info}")
        KV, KN = keep_smooth(TV) if cfg.get("keep_from") == "smooth" else (TV[kidx], TN[kidx])
        meshes[k] = dict(V=np.r_[V2, KV], N=np.r_[N2, KN],
                         W=np.r_[limit4(np.einsum("ik,ikj->ij", w_idw, TW[ref][nn])), keep_w(TW[kidx])], bones=bk, flip=info["det"] < 0)
    if "L" in van:
        R = meshes["R"]
        if cfg["L_from_R"] == "negate":
            # 原版日行包 LHand 的頂點＝RHand 點對稱（−V）、法線取負（逐點實測相同）；點對稱翻手性 → 面反轉。UV 不動
            meshes["L"] = dict(V=-R["V"], N=-R["N"], W=R["W"], bones=hand_bones["L"], flip=True)
        else:
            L, t, r = icp_affine(van["R"]["V"], van["L"]["V"])
            resid["L"] = dict(icp_max=float(r.max()), icp_rms=float(np.sqrt((r ** 2).mean())), det=float(np.linalg.det(L)))
            n = R["N"] @ np.linalg.inv(L).T
            meshes["L"] = dict(V=R["V"] @ L + t, N=n / np.linalg.norm(n, axis=1, keepdims=True), W=R["W"], bones=hand_bones["L"],
                               flip=(np.linalg.det(L) < 0) != R["flip"])
            print(f"icp R->L: {resid['L']}")

    if cfg.get("skin_push"):
        # 本體頂點貼進身體超過原版最貼的那點時，沿最近 3 個身體頂點法線推出去到原版那個距離（腰包：Tripo 背面那條橫腰帶會壓進下背）。
        # 和 verify_x.skin_dist 同一種量法；沿用的原版子網格不動
        for k, body in (("M", "MaleBody.x"), ("F", "FemaleBody.x"), ("AM", "MaleBody.x"), ("AF", "FemaleBody.x")):
            if k not in meshes:
                continue
            Bd = xio.read_x(f"{PZ}/models_X/Skinned/{body}")
            Vt = xio.read_x(tpl[k])["V"]
            V = meshes[k]["V"].copy()
            for _ in range(3):
                nn3 = np.argsort(np.linalg.norm(V[:nb, None] - Bd["V"][None], axis=2), 1)[:, :3]
                s = np.einsum("ikj,ikj->ik", V[:nb, None] - Bd["V"][nn3], Bd["N"][nn3])
                j = s.argmax(1)
                van_d = np.linalg.norm(Vt[:, None] - Bd["V"][None], axis=2)
                vn = np.argsort(van_d, 1)[:, :3]
                target = np.einsum("ikj,ikj->ik", Vt[:, None] - Bd["V"][vn], Bd["N"][vn]).max(1)[van_d.min(1) < 0.05].min()
                lack = np.maximum(target - s.max(1), 0)
                V[:nb] += Bd["N"][nn3[np.arange(nb), j]] * lack[:, None]
            print(f"skin_push {k}: moved {int((np.linalg.norm(V - meshes[k]['V'], axis=1) > 1e-6).sum())} verts, max {np.linalg.norm(V - meshes[k]['V'], axis=1).max():.4f}")
            meshes[k]["V"] = V

    suffix = dict(M="M", F="F", AM="ALT_M", AF="ALT_F", R="RHand", L="LHand")
    for k, m in meshes.items():
        W = m["W"]
        Wd = {b: (np.nonzero(W[:, j])[0], W[np.nonzero(W[:, j])[0], j]) for j, b in enumerate(m["bones"]) if W[:, j].any()}
        Fk = FF[:, [0, 2, 1]] if m.get("flip") else FF
        xio.write_skinned_x(tpl[k], f"{OUT}/models_X/Skinned/BackPacks/MDB_{name}_{suffix[k]}.X", m["V"], m["N"], UV, Fk, Wd,
                            name=f"MDB_{name}")
        print(f"MDB_{name}_{suffix[k]}.X: {len(m['V'])} verts, {len(FF)} tris, bones {list(Wd)}")

    # 貼圖：1024 烘焙 → 調色 → 沿用的原版子網格塗黑 → 縮 256
    van_tex = Image.open(PZ + "/" + cfg["keep_tex"])
    for look, fix in (("Navy", recolor_navy), ("Olive", lambda i: i.convert("RGB"))):
        img = keep_paint(fix(Image.open(os.path.join(TEMP, f"bake_{look.lower()}.png"))), van_tex, [i[1:] for i in isl])
        img.resize((TEX, TEX), Image.LANCZOS).save(f"{OUT}/textures/Clothes/Bag/MDB_{name}_{look}.png")
        img.save(os.path.join(TEMP, f"tex_{look}_1024.png"))

    np.savez(os.path.join(TEMP, "final_mesh.npz"), V=meshes["M"]["V"], N=meshes["M"]["N"], F=FF, UV=UV, nbody=nb)
    json.dump(resid, open(os.path.join(TEMP, "fit_residuals.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
