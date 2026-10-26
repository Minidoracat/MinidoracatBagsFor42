"""蒙皮 .X 文字檔讀寫（原版背包格式）。Blender 內外都能 import（只用 numpy）。

讀：read_x(path) -> dict(V, F, N, NF, UV, sw={骨名:(索引, 權重, 反綁定 4x4)}, name, material, text)
寫：write_skinned_x(template, out, V, N, UV, F, W, name=None)
    template＝同款、同性別（或同一隻手）的原版 .X：檔頭（template 宣告、Material、Dummy01 骨架、Translation_Data）
    與檔尾（AnimTicksPerSecond＋AnimationSet）原樣照抄，只換掉網格那個 Frame；反綁定矩陣取模板同名骨頭。
格式（縮排、;,、CRLF、%.6f）照原版逐字對齊：原版檔讀進來原樣寫回會逐位元相同（__main__ 自我檢查）。
"""
import re
import numpy as np

_N = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def _block(t, start):
    """t[start] 之後第一個 '{' 到對應 '}'，回 (內容起點, 內容終點)。"""
    i = t.index("{", start)
    depth, j = 0, i
    while True:
        c = t[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1, j
        j += 1


def _nums(s):
    return np.array(_N.findall(s), float)


def _sub(t, a, b, key):
    """區段 [a,b) 內名為 key 的子區塊內容（直屬於網格的那個）。"""
    m = re.compile(r"\n\s*" + key + r"\b[^{]*\{").search(t, a, b)
    s, e = _block(t, m.start())
    return s, e


def _faces(a, k, nf):
    f = a[k:k + 4 * nf].reshape(nf, 4)
    assert (f[:, 0] == 3).all(), "只支援三角形"
    return f[:, 1:].astype(int)


def read_x(path):
    t = open(path, encoding="latin-1", newline="").read()
    m = re.search(r"\n\s*Mesh (\w+) \{", t)
    ms, me = _block(t, m.start())
    name = m[1]
    # 網格本體：頂點與面在第一個子區塊之前
    first = re.compile(r"\n\s*MeshNormals\b").search(t, ms, me).start()
    a = _nums(t[ms:first])
    nv = int(a[0]); V = a[1:1 + 3 * nv].reshape(nv, 3)
    nf = int(a[1 + 3 * nv]); F = _faces(a, 2 + 3 * nv, nf)
    s, e = _sub(t, ms, me, "MeshNormals"); a = _nums(t[s:e])
    nn = int(a[0]); N = a[1:1 + 3 * nn].reshape(nn, 3); NF = _faces(a, 2 + 3 * nn, int(a[1 + 3 * nn]))
    s, e = _sub(t, ms, me, "MeshTextureCoords")
    a = _nums(t[s:e]); UV = a[1:1 + 2 * int(a[0])].reshape(-1, 2)
    s, e = _sub(t, ms, me, "MeshMaterialList")
    material = re.search(r"\{\s*([^}\s]+)\s*\}", t[s:e])[1]
    sw = {}
    for w in re.finditer(r"SkinWeights \{", t[ms:me]):
        s, e = _block(t, ms + w.start())
        body = t[s:e]
        bone = re.search(r'"([^"]+)"', body)[1]
        a = _nums(body[body.index('";') + 2:])
        n = int(a[0])
        sw[bone] = (a[1:1 + n].astype(int), a[1 + n:1 + 2 * n], a[1 + 2 * n:17 + 2 * n].reshape(4, 4))
    hdr_s, hdr_e = _sub(t, ms, me, "XSkinMeshHeader")
    header = _nums(t[hdr_s:hdr_e]).astype(int)
    return dict(V=V, F=F, N=N, NF=NF, UV=UV, sw=sw, name=name, material=material, header=header, text=t)


def _f(x):
    return f"{x:.6f}"


def _rows(items, indent, last=";;", sep=";,"):
    """原版列格式：每列以 ';,' 結尾，最後一列 ';;'。"""
    out = [indent + it + sep for it in items]
    out[-1] = indent + items[-1] + last
    return out


def _mesh_frame(name, V, N, UV, F, W, material, ibm, frame_matrix):
    tri = [f"3;{a},{b},{c}" for a, b, c in F]
    L = [f"Frame {name} {{", " ", "", " FrameTransformMatrix {", frame_matrix, " }", "",
         f" Mesh {name} {{", f"  {len(V)};"]
    L += _rows([";".join(map(_f, v)) for v in V], "  ")
    L += [f"  {len(F)};"] + _rows(tri, "  ") + [""]
    L += ["  MeshNormals {", f"   {len(N)};"] + _rows([";".join(map(_f, v)) for v in N], "   ")
    L += [f"   {len(F)};"] + _rows(tri, "   ") + ["  }", ""]
    L += ["  MeshMaterialList {", "   1;", f"   {len(F)};"]
    L += ["   0,"] * (len(F) - 1) + ["   0;", f"   {{ {material} }}", "  }", ""]
    L += ["  MeshTextureCoords c1 {", f"   {len(UV)};"] + _rows([f"{_f(u)};{_f(v)}" for u, v in UV], "   ") + ["  }", ""]
    cnt = np.zeros(len(V), int)
    for idx, _ in W.values():
        cnt[idx] += 1
    per_face = max(len({b for b, (idx, _) in W.items() if set(f) & set(idx.tolist())}) for f in F)
    L += ["  XSkinMeshHeader {", f"   {cnt.max()};", f"   {per_face};", f"   {len(W)};", "  }"]
    for b, (idx, w) in W.items():
        L += ["", "  SkinWeights {", f'   "{b}";', f"   {len(idx)};"]
        L += [f"   {i}," for i in idx[:-1]] + [f"   {idx[-1]};"]
        L += [f"   {_f(x)}," for x in w[:-1]] + [f"   {_f(w[-1])};"]
        L += ["   " + ",".join(_f(x) for x in ibm[b].ravel()) + ";;", "  }"]
    L += [" }", "}"]
    return L


def write_skinned_x(template, out, V, N, UV, F, W, name=None, extra_ibm=None):
    """W={骨名:(頂點索引 int 陣列, 權重)}；骨名必須在模板裡（反綁定矩陣照抄模板），或由 extra_ibm={骨名: 4x4} 另給
    （側背包鏡像換到另一側的骨頭時，從同性別身體 .X 取）。XSkinMeshHeader 從 W 算。"""
    T = read_x(template)
    t = T["text"]
    ibm = {b: v[2] for b, v in T["sw"].items()} | (extra_ibm or {})
    missing = set(W) - set(ibm)
    assert not missing, f"模板沒有這些骨頭的反綁定矩陣：{missing}"
    # 網格 Frame 多半在檔案頂層；遠征包 LHand 的掛在 Bip01_Prop1 底下（有縮排）：一樣原地換掉，內層縮排不跟著加（.X 不看空白）
    m = re.search(r"\n([ \t]*)Frame " + re.escape(T["name"]) + r" \{", t)
    s, e = _block(t, m.start())
    # 模板網格 Frame 的矩陣原樣照抄（LHand 是 diag(1,-1,-1)）；頂點要和模板原始頂點在同一個空間
    fm = re.search(r"FrameTransformMatrix \{\r?\n([^\r\n]*)", t[s:e])[1]
    body = _mesh_frame(name or T["name"], V, N, UV, F, W, T["material"], ibm, fm)
    txt = t[:m.start() + 1] + m[1] + "\r\n".join(body) + t[e + 1:]
    with open(out, "w", encoding="ascii", newline="") as fh:
        fh.write(txt)


def weights_of(sw):
    return {b: (v[0], v[1]) for b, v in sw.items()}


if __name__ == "__main__":
    # 恆等自我檢查：原版讀進來原樣寫回，逐位元相同（header 也是重算的）
    import sys, os, tempfile
    for p in sys.argv[1:]:
        X = read_x(p)
        o = os.path.join(tempfile.gettempdir(), "xio_roundtrip.x")
        write_skinned_x(p, o, X["V"], X["N"], X["UV"], X["F"], weights_of(X["sw"]))
        assert (X["NF"] == X["F"]).all(), "法線面序與面序不同，寫檔會失真"
        assert open(p, "rb").read() == open(o, "rb").read(), f"{p} 寫回不相同"
        print(os.path.basename(p), "nv", len(X["V"]), "nf", len(X["F"]), "bones", list(X["sw"]), "header", X["header"].tolist(), "IDENTICAL")
