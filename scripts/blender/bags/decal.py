"""深藍款的 S.T.A.R.S. 隊徽：在貼圖空間把隊徽當貼花投影到低模表面（不靠 UV 方向，UV 轉過、翻過、跨島都一樣正）。
1. 每個貼圖像素取樣它在低模（男版穿戴，.X 模型空間：y 上、+z 背包外側）上的 3D 位置與面法線。
2. 種子像素（bags.py 的 emblem.seed，1024 烘焙貼圖座標，Tripo 金星上一點）→ 表面點與法線；同一平面上和它相連的圖案像素
   （金星、醫療包的綠草藥）＝舊徽章。舊徽章先用旁邊最近的非圖案像素補掉（黑底或布料），隊徽比舊圖案小的地方不會露出金角。
3. 隊徽中心＝舊徽章的 3D 中心；高＝bags.py 的 h；「上」＝世界上方投影到表面，「右」＝法線×上。
   PZ 把 .X 當左手座標畫：照右手系算的「上×法線」，實機看到的是左右顛倒的「ꟻ」（mdb-stars-orient-1025b，日行包背面大 F 實拍）。
   Blender 預覽是右手系，隊徽特寫要左右翻過來才和實機一樣（stage3）。
4. 每像素 8×8 次取樣，落在隊徽內才蓋上；沒蓋到任何面的邊緣像素（烘焙外擴）用最近的已改像素補，縮圖時不滲出舊顏色。
黑色方形底保留：戰術包的魔鬼氈底（loop panel）本來就是讓臂章黏上去的，圓章四角露出一點黑底才像「布章黏在包上」；
挖掉黑底得替底下的布料補圖，256 px 上會多一圈接縫，改動也不再只在徽章範圍。
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

SUB = 8             # 每像素次取樣
PLANE_TOL = 0.012   # 和種子平面的距離上限（.X 單位）
GRID = 0.0006       # 平面座標找相連圖案用的格子（約 1024 貼圖一像素）


def raster(V, F, UV, res, sub=1, faces=None):
    """UV 空間取樣（.X UV：v 朝下，像素列＝v×res）：回 (y, x, 面編號, 重心座標)；sub>1 時座標是 res×sub 的次像素格。"""
    n = res * sub
    ys, xs, fs, bs = [], [], [], []
    for fi in (range(len(F)) if faces is None else faces):
        t = UV[F[fi]] * n - 0.5
        x0, y0 = np.floor(t.min(0)).astype(int)
        x1, y1 = np.ceil(t.max(0)).astype(int)
        gx, gy = np.meshgrid(np.arange(max(x0, 0), min(x1, n - 1) + 1), np.arange(max(y0, 0), min(y1, n - 1) + 1))
        p = np.c_[gx.ravel(), gy.ravel()].astype(float)
        a, b, c = t
        m = np.array([[b[0] - a[0], c[0] - a[0]], [b[1] - a[1], c[1] - a[1]]])
        if abs(np.linalg.det(m)) < 1e-12:
            continue
        w = np.linalg.solve(m, (p - a).T).T
        bc = np.c_[1 - w.sum(1), w]
        k = (bc >= -1e-9).all(1)
        ys.append(gy.ravel()[k]); xs.append(gx.ravel()[k]); fs.append(np.full(k.sum(), fi)); bs.append(bc[k])
    return np.concatenate(ys), np.concatenate(xs), np.concatenate(fs), np.concatenate(bs)


def face_normals(V, F, N):
    """面法線，朝向和頂點法線平均同側（外側）。"""
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    fn *= np.sign(np.einsum("ij,ij->i", fn, N[F].mean(1)) + 1e-12)[:, None]
    return fn


def art_mask(tex):
    """舊徽章圖案：暖黃（金星）或明顯偏綠（草藥）。tex 是 uint8 RGB。"""
    a = tex.astype(float)
    gold = (a[..., 0] > 120) & (a[..., 2] < 0.65 * a[..., 1]) & (a[..., 0] > a[..., 2] + 60)
    green = (a[..., 1] > a[..., 0] + 25) & (a[..., 1] > a[..., 2] + 15)
    return gold | green


def frame(seed, tex, V, F, UV, N):
    """量種子所在的舊徽章：回 dict(center, normal, up, right, old＝舊圖案像素遮罩, size＝舊圖案在平面上的寬高)。"""
    res = tex.shape[0]
    ys, xs, fs, bs = raster(V, F, UV, res)
    pos = np.einsum("ik,ikj->ij", bs, V[F[fs]])
    fn = face_normals(V, F, N)[fs]
    k = np.argmin((xs - seed[0]) ** 2 + (ys - seed[1]) ** 2)
    assert (xs[k] - seed[0]) ** 2 + (ys[k] - seed[1]) ** 2 <= 2, f"種子 {seed} 不在任何面上"
    p0, n0 = pos[k], fn[k]
    up = np.array([0.0, 1.0, 0.0])
    et = up - (up @ n0) * n0
    et /= np.linalg.norm(et)
    es = np.cross(n0, et)   # 實機看過去的右手邊（見檔頭第 3 點）
    d = pos - p0
    art = art_mask(tex)[ys, xs] & (np.abs(d @ n0) < PLANE_TOL) & (fn @ n0 > 0.7) & (np.linalg.norm(d, axis=1) < 0.05)
    P = np.c_[d[art] @ es, d[art] @ et]
    g = np.floor(P / GRID).astype(int)
    off = g.min(0)
    occ = np.zeros((g.max(0) - off + 1)[::-1], bool)
    occ[g[:, 1] - off[1], g[:, 0] - off[0]] = True
    lab, _ = nd.label(nd.binary_closing(occ, iterations=2) | occ)
    c0 = np.floor(-off).astype(int)
    near = lab[max(c0[1] - 3, 0):c0[1] + 4, max(c0[0] - 3, 0):c0[0] + 4]
    assert near.max() > 0, f"種子 {seed} 附近沒有金星／草藥像素"
    comp = np.bincount(near[near > 0]).argmax()
    # 被 UV 島切開、Tripo 拉長的星角（彈藥背帶）不一定和主體相連：主體 4 mm 內的圖案都算舊徽章
    dist = nd.distance_transform_edt(lab != comp) * GRID
    keep = dist[g[:, 1] - off[1], g[:, 0] - off[0]] <= 0.004
    old = np.zeros((res, res), bool)
    old[ys[art][keep], xs[art][keep]] = True
    Q = P[keep]
    c2 = (Q.min(0) + Q.max(0)) / 2
    return dict(center=p0 + c2[0] * es + c2[1] * et, normal=n0, up=et, right=es, old=old, size=tuple(Q.max(0) - Q.min(0)))


def emblem_box(emb):
    """隊徽圖（RGBA）的不透明外框：回 (中心像素 x, y, 寬, 高)。"""
    a = np.asarray(emb)[..., 3]
    ys, xs = np.nonzero(a > 8)
    return (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1


def apply(tex, V, F, UV, N, fr, emb, h):
    """先補掉舊圖案，再把隊徽（高 h，.X 單位）蓋上。回 (新貼圖 uint8, 隊徽 3D 寬高, 改動遮罩)。"""
    res = tex.shape[0]
    # 1. 舊圖案（外擴 2 像素含反鋸齒邊）→ 最近的非圖案像素（烘焙外擴區也有金色，不能拿來補）
    old = nd.binary_dilation(fr["old"], iterations=2)
    _, (iy, ix) = nd.distance_transform_edt(old | art_mask(tex), return_indices=True)
    base = tex.astype(float) / 255
    base[old] = base[iy[old], ix[old]]
    # 2. 隊徽次取樣
    E = np.asarray(emb.convert("RGBA")).astype(float) / 255
    E[..., :3] *= E[..., 3:]
    ecx, ecy, ew, eh = emblem_box(emb)
    scale = h / eh                                   # .X 單位 / 隊徽像素
    n0, upv, right, c = fr["normal"], fr["up"], fr["right"], fr["center"]
    reach = 0.5 * np.hypot(ew, eh) * scale
    fn = face_normals(V, F, N)
    faces = [i for i in range(len(F)) if fn[i] @ n0 > 0.5 and np.abs((V[F[i]] - c) @ n0).min() < PLANE_TOL
             and np.linalg.norm(V[F[i]].mean(0) - c) < reach + np.linalg.norm(V[F[i]] - V[F[i]].mean(0), axis=1).max()]
    ys, xs, fs, bs = raster(V, F, UV, res, SUB, faces)
    d = np.einsum("ik,ikj->ij", bs, V[F[fs]]) - c
    ex = ecx + (d @ right) / scale - 0.5
    ey = ecy - (d @ upv) / scale - 0.5
    x0, y0 = np.floor(ex).astype(int), np.floor(ey).astype(int)
    fx, fy = (ex - x0)[:, None], (ey - y0)[:, None]
    H, W = E.shape[:2]

    def at(yy, xx):
        inside = (yy >= 0) & (yy < H) & (xx >= 0) & (xx < W)
        o = np.zeros((len(yy), 4))
        o[inside] = E[yy[inside], xx[inside]]
        return o
    s = (at(y0, x0) * (1 - fx) * (1 - fy) + at(y0, x0 + 1) * fx * (1 - fy)
         + at(y0 + 1, x0) * (1 - fx) * fy + at(y0 + 1, x0 + 1) * fx * fy)
    s[np.abs(d @ n0) >= PLANE_TOL] = 0
    acc = np.zeros((res, res, 4))
    np.add.at(acc, (ys // SUB, xs // SUB), s)
    acc /= SUB * SUB
    new = base * (1 - acc[..., 3:]) + acc[..., :3]
    painted = (acc[..., 3] > 1e-4) | old
    # 3. 烘焙外擴：沒有任何面蓋到的像素，貼近已改像素的照最近那個補
    cov = Image.new("L", (res * 4, res * 4), 0)
    dr = ImageDraw.Draw(cov)
    for f in F:
        dr.polygon([tuple(p) for p in UV[f] * res * 4], fill=255)
    cov = np.asarray(cov.resize((res, res), Image.BOX)) > 0
    dist, (iy, ix) = nd.distance_transform_edt(~painted, return_indices=True)
    fillm = ~cov & ~painted & (dist <= 4)
    new[fillm] = new[iy[fillm], ix[fillm]]
    out = np.clip(np.round(new * 255), 0, 255).astype(np.uint8)
    return out, (float(ew * scale), float(h)), painted | fillm
