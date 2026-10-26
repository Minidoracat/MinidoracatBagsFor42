"""強化版背包額外掛點的離線預覽：原版身體＋穿戴網格（綁定姿勢）＋掛上去的物品模型，照遊戲的變換鏈算位置後算圖。
先把遊戲會加的掛點匯出成 JSON，再交給 Blender（在 repo 根目錄跑）：
  lua scripts/blender/attach/dump_attach.lua temp/attach.json
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python scripts/blender/attach/preview.py -- temp/attach.json temp/preview full
  … -- temp/attach.json temp/preview axes Base.SpiffoPlushie Base.Pancho …     每個模型自己的軸（R=x、G=y、B=z）從六個方向看
座標：
  身體與背包 .X 照原檔（xio），左手系：y 上、角色面向 -z、+x 是角色左邊；Bip01_BackPack 綁定矩陣＝反綁定矩陣的反矩陣。
  物品 FBX：assimp 套節點鏈、不套 UnitScaleFactor，MAKE_LEFT_HANDED 把 z 取負（skill pz-blender-models items-and-icons.md 第 1 節）。
  變換鏈：骨頭·身體掛點·自身掛點·model scale·網格（AnimatedModel.java:1446-1486、ModelInstanceRenderData.java:106-111）。
  算圖前把 x 取負換回右手系，再轉成 Blender 的 z 上。綁定姿勢不是遊戲待機姿勢，只看方向與大致位置；最後一定要看實機截圖。
"""
import json
import math
import os
import re
import struct
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bags"))
import xio  # noqa: E402

PZ = os.environ.get("PZ_PATH", "D:/SteamLibrary/steamapps/common/ProjectZomboid").replace("\\", "/") + "/media/"
MOD_SCRIPTS = "MOD/MinidoracatBagsFor42/Contents/mods/MinidoracatBagsFor42/42/media/scripts"   # 借給原版物品的本 MOD 模型（MDB_AttachModels.txt）
BODY = {"M": "MaleBody", "F": "FemaleBody"}
BAG = {  # 家族 → (男, 女) 穿戴網格，和 anchors.py 相同
    "Alice": ("M_ALICE_Pack.x", "F_ALICE_Pack.x"), "Duffel": ("M_Duffelbag.x", "F_DuffelBag.x"),
    "Hiking": ("M_HikingBag.x", "F_HikingBag.x"), "BigHiking": ("M_BigHikingBag.x", "F_BigHikingBag.x"),
}
SETS = [  # 和 E2E attach-art-sp 的 full 三組相同
    {"Slot1": "Base.Hammer", "Slot2": "Base.Screwdriver", "Slot3": "Base.KitchenKnife", "BottleR": "Base.WaterBottle",
     "BottleL": "Base.Pop", "Plushie": "Base.Spiffo", "UmbrellaR": "Base.ClosedUmbrellaBlack",
     "UmbrellaL": "Base.ClosedUmbrellaBlack", "Flashlight": "Base.HandTorch"},
    {"Slot1": "Base.Wrench", "Slot2": "Base.MeatCleaver", "Slot3": "Base.WalkieTalkie1", "BottleR": "Base.Wine2",
     "BottleL": "Base.Pills", "Plushie": "Base.Doll", "UmbrellaR": "Base.Saw", "UmbrellaL": "Base.GardenSaw",
     "Flashlight": "Base.Torch"},
    {"Slot1": "Base.Pan", "Slot2": "Base.Saucepan", "Slot3": "Base.Rope", "BottleR": "Base.BeerCan", "BottleL": "Base.Whiskey",
     "Plushie": "Base.BorisBadger", "UmbrellaR": "Base.BlowTorch", "UmbrellaL": "Base.BlowTorch", "Flashlight": "Base.PenLight"},
]
VIEWS = {"back": (0, 30), "back3q": (45, 30), "right": (90, 20), "left": (-90, 20)}   # 繞角色的方位（0＝正後方、90＝右邊）、仰角


# ===== 原版腳本 =====
def blocks(text, kind):
    """module Base 裡的 kind 區塊 → {名稱: 內容}（大括號配對，容許巢狀）。"""
    out = {}
    for m in re.finditer(r"\b" + kind + r"\s+([\w.]+)\s*\{", text):
        depth, j = 0, m.end() - 1
        while True:
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            if depth == 0:
                break
            j += 1
        out[m[1]] = text[m.end():j]
    return out


def field(body, key):
    m = re.search(r"(?mi)^\s*" + key + r"\s*=\s*([^,\n]+?)\s*,?\s*$", body)
    return m and m[1]


def vanilla():
    """原版 module Base 的物品與模型，加上本 MOD module MinidoracatBags 的模型（ATTACH_STATIC 會借）。"""
    items, models = {}, {}
    for top, module in ((PZ + "scripts", "Base"), (MOD_SCRIPTS, "MinidoracatBags")):
        for root, _, files in os.walk(top):
            for f in files:
                if not f.endswith(".txt"):
                    continue
                t = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                if not re.search(r"\bmodule\s+" + module + r"\b", t):
                    continue
                if module == "Base":
                    for n, b in blocks(t, "item").items():
                        # 武器沒有 StaticModel，畫的是 WeaponSprite（多款的取第一個）
                        static = field(b, "StaticModel") or field(b, "WeaponSprite") or (field(b, "WeaponSpritesByIndex") or "").split(";")[0]
                        items["Base." + n] = {"type": field(b, "AttachmentType"), "static": static or None}
                for n, b in blocks(t, "model").items():
                    b = re.sub(r"attachment\s+\w+\s*\{[^}]*\}", "", b)
                    models[module + "." + n] = {"mesh": field(b, "mesh"), "texture": field(b, "texture"), "scale": float(field(b, "scale") or 1)}
    return items, models


# ===== 矩陣（行向量乘在右邊：M·v）=====
def rot(rx, ry, rz):
    def R(axis, a):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        m = np.eye(4)
        i, j = [(1, 2), (2, 0), (0, 1)][axis]
        m[i, i], m[i, j], m[j, i], m[j, j] = c, -s, s, c
        return m
    return R(0, rx) @ R(1, ry) @ R(2, rz)   # JOML rotateXYZ


def att(a):
    t = np.eye(4)
    t[:3, 3] = a["off"]
    return t @ rot(*a["rot"])


def to_blender(P):
    """引擎座標（左手、y 上）→ Blender（右手、z 上）：x 取負，再 (x, y, z) → (x, -z, y)。"""
    return np.c_[-P[:, 0], -P[:, 2], P[:, 1]]


# ===== 場景 =====
def image_mat(name, path=None, color=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    if path and os.path.exists(path):
        tex.image = bpy.data.images.load(path, check_existing=True)
    else:
        img = bpy.data.images.new(name, 1, 1)
        img.pixels = list(color or (1, 0, 1, 1))
        tex.image = img
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.node_tree.nodes.active = tex
    return mat


def add_mesh(name, V, F, UV=None, mat=None, loop_uv=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in V], [], [tuple(f) for f in F])
    if UV is not None or loop_uv is not None:
        layer = me.uv_layers.new()
        for p in me.polygons:
            for k, li in enumerate(p.loop_indices):
                if loop_uv is not None:
                    layer.data[li].uv = loop_uv[p.index][k]
                else:
                    u, v = UV[me.loops[li].vertex_index]
                    layer.data[li].uv = (u, 1 - v)   # .X 的 v 朝下
    if mat:
        me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


_FBX = {}


def xstatic(path):
    """靜態 .X 文字檔 → [(引擎原始座標頂點, 面, 每面 UV, None)]。assimp 讀 .X 先轉右手、MAKE_LEFT_HANDED 再轉回來，
    所以就是檔案座標套 Frame 鏈（FrameTransformMatrix 是行向量 v·M）。"""
    t = open(path, encoding="latin-1").read()
    t = re.sub(r"(?m)^\s*template\s+\w+\s*\{[^}]*\}", "", t)
    out = []

    def walk(i, M):
        while i < len(t):
            m = re.compile(r"(Frame|Mesh|FrameTransformMatrix)\b\s*(\w*)\s*\{|\{|\}").search(t, i)
            if not m:
                return len(t)
            if m[0] == "}":
                return m.end()
            if m[0] == "{":
                i = walk(m.end(), M)
                continue
            kind = m[1]
            if kind == "FrameTransformMatrix":
                e = t.index("}", m.end())
                M[:] = (np.array(re.findall(r"-?[\d.]+(?:e[-+]?\d+)?", t[m.end():e]), float)[:16].reshape(4, 4) @ M).tolist()
                i = e + 1
            elif kind == "Frame":
                i = walk(m.end(), [row[:] for row in M])
            else:   # Mesh：頂點數、頂點、面數、面（每面 n 個索引）；之後的子區塊只取 MeshTextureCoords
                s = m.end()
                depth, j = 1, s
                while depth:
                    depth += {"{": 1, "}": -1}.get(t[j], 0)
                    j += 1
                body = t[s:j - 1]
                head = body[:re.search(r"\b(MeshNormals|MeshTextureCoords|MeshMaterialList)\b|$", body).start()]
                a = np.array(re.findall(r"-?[\d.]+(?:e[-+]?\d+)?", head), float)
                nv = int(a[0])
                V = a[1:1 + 3 * nv].reshape(nv, 3)
                k, faces = 2 + 3 * nv, []
                for _ in range(int(a[1 + 3 * nv])):
                    n = int(a[k])
                    faces.append([int(x) for x in a[k + 1:k + 1 + n]])
                    k += 1 + n
                uv = re.search(r"MeshTextureCoords\s*\w*\s*\{([^}]*)\}", body)
                U = np.array(re.findall(r"-?[\d.]+(?:e[-+]?\d+)?", uv[1]), float)[1:].reshape(-1, 2) if uv else np.zeros((nv, 2))
                W = (np.c_[V, np.ones(nv)] @ np.array(M))[:, :3]
                out.append((W, faces, [[(U[v][0], 1 - U[v][1]) for v in f] for f in faces], None))
                i = j
        return i

    walk(0, np.eye(4).tolist())
    return out


def fbx_ascii(path):
    """ASCII FBX（Blender 不收）：Vertices／PolygonVertexIndex／第 0 層 UV，套第一個 Model 的 PreRotation 與 Lcl Scaling
    （照 Knox Pass scripts/blender/dock_spots.py ascii_mesh 的整檔分支）→ 引擎原始座標（z 取負）。"""
    t = open(path, encoding="latin1").read()
    model = t[t.find("Model::"):]
    pre = re.search(r'P: "PreRotation"[^\n]*"",([-\d.e]+),([-\d.e]+),([-\d.e]+)', model)
    sc = re.search(r'P: "Lcl Scaling"[^\n]*"A",([-\d.e]+),([-\d.e]+),([-\d.e]+)', model)
    s = float(sc[1]) if sc else 1.0
    zup = pre is not None and abs(float(pre[1]) + 90) < 1   # Max 匯出的 PreRotation -90°：Z 上 → Y 上
    nums = lambda a: [float(x) for x in a.replace("\n", "").split(",")]
    out = []
    for geo in t.split("Geometry: ")[1:]:
        g = re.search(r"Vertices: \*\d+ \{\s*a: ([^}]*)\}\s*PolygonVertexIndex: \*\d+ \{\s*a: ([^}]*)\}", geo)
        if not g:
            continue
        V = np.array(nums(g[1])).reshape(-1, 3) * s
        V = np.c_[V[:, 0], V[:, 2], -V[:, 1]] if zup else V
        layer = geo[geo.find("LayerElementUV: 0"):]
        uv = re.search(r"UV: \*\d+ \{\s*a: ([^}]*)\}", layer)
        ui = re.search(r"UVIndex: \*\d+ \{\s*a: ([^}]*)\}", layer)
        uv = nums(uv[1]) if uv else []
        ui = [int(x) for x in nums(ui[1])] if ui else None
        faces, uvs, corner, poly = [], [], 0, []
        for i in (int(x) for x in g[2].replace("\n", "").split(",")):
            poly.append(~i if i < 0 else i)
            corner += 1
            if i < 0:
                faces.append(poly)
                idx = ui[corner - len(poly):corner] if ui else range(corner - len(poly), corner)
                uvs.append([(uv[2 * j], uv[2 * j + 1]) if uv else (0.0, 0.0) for j in idx])
                poly = []
        out.append((np.c_[V[:, 0], V[:, 1], -V[:, 2]], faces, uvs, None))
    return out


def fbx(mesh):
    """模型檔 → [(引擎原始座標頂點, 面, 每面 UV, 匯入的貼圖路徑)]。找檔順序照遊戲 .fbx → .x（FileTask_AbstractLoadModel.java:89-100）。
    FBX：節點鏈已套、單位不套、z 取負。"""
    if mesh in _FBX:
        return _FBX[mesh]
    base = PZ + "models_X/" + mesh
    path = next((base + e for e in (".fbx", ".FBX") if os.path.exists(base + e)), None)
    if not path:
        xp = next((base + e for e in (".x", ".X") if os.path.exists(base + e)), None)
        _FBX[mesh] = xstatic(xp) if xp else []
        if not xp:
            print("no mesh file", mesh)
        return _FBX[mesh]
    d = open(path, "rb").read()
    if not d.startswith(b"Kaydara"):
        _FBX[mesh] = fbx_ascii(path)
        return _FBX[mesh]
    u = 1.0   # Blender 把 UnitScaleFactor/100 乘進 matrix_world，assimp 不乘（Knox Pass dock_spots.py 同做法）
    i = d.find(b"UnitScaleFactor")
    for k in range(i, i + 80 if i >= 0 else i):
        if d[k:k + 1] == b"D" and 1e-4 < struct.unpack_from("<d", d, k + 1)[0] < 1e4:
            u = struct.unpack_from("<d", d, k + 1)[0] / 100.0
            break
    before = set(bpy.data.objects)
    # assimp 不看 FBX GlobalSettings 的上軸（原版有些檔是 Z 上）：固定用 Y 上換算，換回來才是遊戲裡的原始座標
    bpy.ops.import_scene.fbx(filepath=path, use_manual_orientation=True, axis_forward="-Z", axis_up="Y")
    out = []
    for o in set(bpy.data.objects) - before:
        if o.type == "MESH":
            W = np.array([tuple(o.matrix_world @ v.co) for v in o.data.vertices]) / u
            E = np.c_[W[:, 0], W[:, 2], W[:, 1]]          # Blender z 上 → FBX y 上 (x, z, -y)，再 MAKE_LEFT_HANDED 取負 z
            layer = o.data.uv_layers[0].data if o.data.uv_layers else None
            faces = [list(p.vertices) for p in o.data.polygons]
            uvs = [[tuple(layer[li].uv) if layer else (0, 0) for li in p.loop_indices] for p in o.data.polygons]
            img = None
            for m in o.data.materials:
                for n in (m.node_tree.nodes if m and m.use_nodes else []):
                    if n.type == "TEX_IMAGE" and n.image:
                        img = bpy.path.abspath(n.image.filepath)
            out.append((E, faces, uvs, img))
        bpy.data.objects.remove(o)
    _FBX[mesh] = out
    return out


def item_mesh(name, model, M, models):
    """model 全名 → 套上 M（4×4，引擎座標）放進場景。"""
    ms = models.get(model)
    if not ms or not ms["mesh"]:
        print("no model", model)
        return
    tex = ms["texture"] or ms["mesh"]
    S = np.diag([ms["scale"]] * 3 + [1])
    for k, (E, faces, uvs, img) in enumerate(fbx(ms["mesh"])):
        P = (M @ S @ np.c_[E, np.ones(len(E))].T).T[:, :3]
        path = PZ + "textures/" + tex + ".png"
        add_mesh(f"{name}{k}", to_blender(P), faces, loop_uv=uvs,
                 mat=image_mat(f"{name}{k}", path if os.path.exists(path) else img))


def body_and_bag(fam, sex):
    """身體＋背包網格；回 Bip01_BackPack 的綁定矩陣（引擎座標、M·v）。"""
    b = xio.read_x(PZ + "models_X/Skinned/" + BODY[sex] + ".X")
    add_mesh("body", to_blender(b["V"]), b["F"][:, ::-1], mat=image_mat("skin", color=(0.85, 0.7, 0.55, 1)))
    if fam:
        g = xio.read_x(PZ + "models_X/Skinned/BackPacks/" + BAG[fam][0 if sex == "M" else 1])
        add_mesh("bag", to_blender(g["V"]), g["F"][:, ::-1], mat=image_mat("bag", color=(0.3, 0.35, 0.2, 1)))
    return np.linalg.inv(b["sw"]["Bip01_BackPack"][2]).T


def axes(M, length=0.15):
    for i, c in enumerate([(1, 0, 0, 1), (0, 1, 0, 1), (0, 0, 1, 1)]):
        P = np.array([[0, 0, 0, 1], [0, 0, 0, 1], [0, 0, 0, 1], [0, 0, 0, 1]], float)
        w = 0.004
        P[1, i] = length
        P[2, i] = length
        P[2, (i + 1) % 3] = w
        P[3, (i + 1) % 3] = w
        Q = (M @ P.T).T[:, :3]
        add_mesh(f"axis{i}", to_blender(Q), [(0, 1, 2, 3)], mat=image_mat(f"axis{i}", color=c))


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)


def setup(res=520):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_backface_culling = False
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("w")


def shoot(path, target, az, el, scale=0.75):
    """target＝Blender 座標；az：0＝從角色背後（-y）看、90＝從角色右邊（+x）看。"""
    cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if cam.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    a, e = math.radians(az), math.radians(el)
    d = np.array([math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)])
    cam.location = tuple(np.array(target) + 3 * d)
    look = -d
    cam.rotation_euler = (math.atan2(math.hypot(look[0], look[1]), -look[2]), 0, math.atan2(look[1], look[0]) - math.pi / 2)
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    data, outdir, job = json.load(open(argv[0])), os.path.abspath(argv[1]), argv[2]
    os.makedirs(outdir, exist_ok=True)
    items, models = vanilla()
    setup()
    if job == "sizes":   # 每個掛得上的物品：擺法、模型、原始座標×scale 的範圍（握點在原點）
        poses = {}
        for acc in data["accepts"].values():
            poses.update(acc)
        for it in sorted(set(data["items"]) | {k for k, v in items.items() if v["type"] in poses}):
            kind = data["items"].get(it) or items[it]["type"]
            model = data["static"].get(it) or items.get(it, {}).get("static")
            model = model and (model if "." in model else "Base." + model)
            ms = models.get(model)
            parts = fbx(ms["mesh"]) if ms and ms["mesh"] else []
            if not parts:
                print(f"SIZE {it} {kind} {poses[kind]} {model} -")
                continue
            P = np.vstack([p[0] for p in parts]) * ms["scale"]
            lo, hi = P.min(0), P.max(0)
            print(f"SIZE {it} {kind} {poses[kind]} {model} " + " ".join(f"{a:.3f}..{b:.3f}" for a, b in zip(lo, hi)))
        return
    if job == "axes":
        for model in argv[3:]:
            clear()
            item_mesh("m", model, np.eye(4), models)
            axes(np.eye(4))
            for tag, (az, el) in {"px": (-90, 0), "nx": (90, 0), "py": (0, 89), "ny": (0, -89), "pz": (0, 0), "nz": (180, 0)}.items():
                # 引擎 → Blender：+x→-X、+y→+Z、+z→-Y；鏡頭從那一軸的正向看回原點
                shoot(f"{outdir}/axes-{model}-{tag}.png", (0, 0, 0), az, el, 0.5)
        return
    def place(fam, sex, slot, it, bone):
        """照遊戲的查法：物品 AttachmentType → 掛點擺法 → 身體掛點·（有的話）模型自身掛點。"""
        kind = data["items"].get(it) or items.get(it, {}).get("type")
        pose = data["accepts"][slot].get(kind)
        model = data["static"].get(it) or items.get(it, {}).get("static")
        if not pose or not model:
            print("skip", fam, slot, it, kind, pose, model)
            return
        model = model if "." in model else "Base." + model
        aid = f"mdb_{fam}_{slot}_{pose}".lower()
        M = bone @ att(data["attach"][BODY[sex]][aid])
        fix = data["attach"].get(model, {}).get(aid)
        item_mesh(slot, model, M @ att(fix) if fix else M, models)

    def target(bone):
        return to_blender((bone @ np.array([[0.0, 0, 0, 1]]).T).T[:, :3])[0]

    if job == "slot":   # -- … slot <家族> <M|F> <掛點> <物品…>：每個物品單獨掛上去拍背面與右側
        fam, sex, slot = argv[3:6]
        for it in argv[6:]:
            clear()
            bone = body_and_bag(fam, sex)
            place(fam, sex, slot, it, bone)
            for view in ("back", "right"):
                shoot(f"{outdir}/slot-{fam.lower()}-{sex.lower()}-{slot}-{it}-{view}.png", target(bone), *VIEWS[view])
        return
    for fam in [f["name"] for f in data["families"] if not argv[3:] or f["name"] in argv[3:]]:
        slots = next(f["slots"] for f in data["families"] if f["name"] == fam)
        for sex in ("M", "F"):
            for si, s in enumerate(SETS):
                clear()
                bone = body_and_bag(fam, sex)
                for slot in slots:
                    place(fam, sex, slot, s[slot], bone)
                for view, (az, el) in VIEWS.items():
                    shoot(f"{outdir}/{fam.lower()}-{sex.lower()}-set{si + 1}-{view}.png", target(bone), az, el)


main()
