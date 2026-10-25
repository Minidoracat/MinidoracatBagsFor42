"""背包產線共用：路徑、深藍調色參數、仿射擬合、FBX 節點縮放。Blender 內外都能 import（只用 numpy）。"""
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEMP_ROOT = os.path.join(REPO, "temp", "bags")
PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media"
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
TRIPO_ROOT = "D:/github/tripo-refs/collections/MinidoracatBagsFor42/items"
# 深藍調色（7 款共用，只放這裡）：Tripo 的藍色布料 飽和度×NAVY_S、亮度×NAVY_V，色相固定 0.625。
# 2026-10-25 使用者看實機對照（ServerPatch temp/bags-design/ingame/navy/）選「中」；另兩版是 0.70/0.82（太暗近黑）、0.72/1.20
NAVY_S, NAVY_V = 0.70, 1.00
# 穿戴貼圖邊長（7 款共用，只放這裡）：2026-10-25 使用者看過隊徽 256／512 對照，深藍款改 512（隊徽在 512 上讀得出 S.T.A.R.S.）；
# 保護傘款沒被問到，維持 256
TEX_SIZE = {"Navy": 512, "Olive": 256}

sys.path.insert(0, HERE)
import xio  # noqa: E402


def temp(name):
    """每款的中間產物資料夾；產物在 <temp>/out/media（結構同 MOD 的 media/）。"""
    return os.path.join(TEMP_ROOT, name)


def out(name):
    return os.path.join(temp(name), "out", "media")


def _fbx_nodes(b, pos, end, wide):
    """二進位 FBX 的節點串：回 [(名稱, 屬性值清單, 子節點)]。只解出純量與字串屬性；陣列屬性（頂點、UV）跳過，回 None。"""
    res = []
    hdr = "<QQQB" if wide else "<IIIB"
    hsz = struct.calcsize(hdr)
    while pos < end:
        e, n, plen, nl = struct.unpack_from(hdr, b, pos)
        if e == 0:
            break
        name = b[pos + hsz:pos + hsz + nl].decode("ascii", "replace")
        p = pos + hsz + nl
        props = []
        for _ in range(n):
            t = chr(b[p]); p += 1
            if t in "YCIFDL":
                fmt = {"Y": "<h", "C": "<?", "I": "<i", "F": "<f", "D": "<d", "L": "<q"}[t]
                props.append(struct.unpack_from(fmt, b, p)[0]); p += struct.calcsize(fmt)
            elif t in "SR":
                ln = struct.unpack_from("<I", b, p)[0]
                props.append(b[p + 4:p + 4 + ln]); p += 4 + ln
            else:   # f d l i b 陣列
                _, _, cl = struct.unpack_from("<III", b, p)
                props.append(None); p += 12 + cl
        res.append((name, props, _fbx_nodes(b, p, e, wide) if p < e else []))
        pos = e
    return res


LCL = (b"Lcl Translation", b"Lcl Rotation", b"Lcl Scaling")


def fbx_node_transforms(path):
    """每個 Model 節點的 Lcl Translation／Rotation／Scaling：節點自己的 Properties70 有寫就用它，沒寫用 Definitions 裡 Model（FbxNode）樣板的預設值。
    回 {節點名: {"Lcl Scaling": (sx, sy, sz), ...}}。只看第一個 P 出現的地方會讀到樣板（原版 HikingBag_Ground 樣板是 1、節點是 1/36）。PZ 讀靜態網格會套節點變換鏈（items-and-icons.md §1），所以這個值直接影響地上大小。"""
    b = open(path, "rb").read()
    assert b[:21] == b"Kaydara FBX Binary  \x00", f"{path} 不是二進位 FBX"
    ver = struct.unpack_from("<I", b, 23)[0]
    top = _fbx_nodes(b, 27, len(b), ver >= 7500)
    P70 = lambda node: {q[1][0]: q[1][4:] for q in next((c for c in node[2] if c[0] == "Properties70"), ("", [], []))[2] if q[0] == "P"}
    default = {k: (1.0, 1.0, 1.0) if k == b"Lcl Scaling" else (0.0, 0.0, 0.0) for k in LCL}
    for d in next((n for n in top if n[0] == "Definitions"), ("", [], []))[2]:
        if d[0] == "ObjectType" and d[1] and d[1][0] == b"Model":
            for tpl in d[2]:
                if tpl[0] == "PropertyTemplate":
                    default = {k: tuple(P70(tpl).get(k, v)) for k, v in default.items()}
    out = {}
    for m in next((n for n in top if n[0] == "Objects"), ("", [], []))[2]:
        if m[0] == "Model":
            own = P70(m)
            out[m[1][1].split(b"\x00")[0].decode()] = {k.decode(): tuple(float(x) for x in own.get(k, v)) for k, v in default.items()}
    return out


def fit_affine(A, B):
    """最小平方 B ≈ A·L + t；殘差 >5×中位數（且 >2 mm 單位）的點當離群剔除後重擬一次。
    回 (L 3x3, t, 每點殘差, 離群點索引)。原版 F／RHand 各有第 16、35 號兩點被美術另外推過（約 9、21 mm 單位）。"""
    Ah = np.c_[A, np.ones(len(A))]
    keep = np.ones(len(A), bool)
    for _ in range(2):
        X, *_ = np.linalg.lstsq(Ah[keep], B[keep], rcond=None)
        r = np.linalg.norm(Ah @ X - B, axis=1)
        keep = r < max(0.002, 5 * np.median(r))
    return X[:3], X[3], r, np.nonzero(~keep)[0]


def sel(M, spec):
    """原版頂點選取：(a, b)＝頂點區間；("uv", (u0, v0, u1, v1))＝UV 落在矩形內的點（腰包的包身、腰帶是不連續區間的 UV 島）。"""
    if spec[0] == "uv":
        u0, v0, u1, v1 = spec[1]
        return np.nonzero((M["UV"][:, 0] >= u0) & (M["UV"][:, 0] <= u1) & (M["UV"][:, 1] >= v0) & (M["UV"][:, 1] <= v1))[0]
    return np.arange(*spec)


def keep_groups(cfg, M):
    """沿用子網格：每組一個頂點索引陣列（輸出時一組一個 UV 島）。"""
    return [sel(M, s) for s in cfg["keep"]]


def obb_axes(B):
    """原版本體頂點的主軸外框：回 (外框中心, ew 寬, eh 高〔最接近 +y〕, ed 厚〔背離身體中軸〕, 寬, 高, 厚)；(ew, eh, ed) 右手系。"""
    c = B.mean(0)
    ax = np.linalg.svd(B - c)[2]
    q = (B - c) @ ax.T
    c = c + ((q.min(0) + q.max(0)) / 2) @ ax
    ext = np.ptp(q, 0)
    h = int(np.argmax(np.abs(ax[:, 1])))
    w, d = [k for k in range(3) if k != h]
    if ext[w] < ext[d]:
        w, d = d, w
    eh = ax[h] * np.sign(ax[h][1])
    ed = ax[d] * np.sign(np.dot(ax[d], c - np.array([0, c[1], 0.02])))
    return c, np.cross(eh, ed), eh, ed, ext[w], ext[h], ext[d]
