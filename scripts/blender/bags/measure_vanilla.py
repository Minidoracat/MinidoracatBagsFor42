"""量原版日行包（研究第 2 步）：穿戴／手持 .X、地面 FBX、貼圖像素，寫 temp/bags/vanilla.json。
blender -b --factory-startup --python measure_vanilla.py
"""
import json, os, struct, sys
import numpy as np
import bpy

sys.path.insert(0, os.path.dirname(__file__))
from common import PZ, TEMP_ROOT as TEMP, xio

X = PZ + "/models_X/Skinned/"


def png_size(p):
    with open(p, "rb") as f:
        h = f.read(24)
    return struct.unpack(">II", h[16:24])


def mx(p):
    d = xio.read_x(p)
    V = d["V"]
    cnt = np.zeros(len(V), int)
    wsum = np.zeros(len(V))
    for idx, w, _ in d["sw"].values():
        cnt[idx] += 1
        wsum[idx] += w
    return dict(verts=len(V), tris=len(d["F"]), header=d["header"].tolist(),
                bones={b: len(v[0]) for b, v in d["sw"].items()},
                max_influences=int(cnt.max()), weight_sum=[float(wsum.min()), float(wsum.max())],
                bbox=[V.min(0).round(4).tolist(), V.max(0).round(4).tolist()],
                uv=[d["UV"].min(0).round(4).tolist(), d["UV"].max(0).round(4).tolist()])


out = {}
for n in ["BackPacks/M_HikingBag.x", "BackPacks/F_HikingBag.x", "BackPacks/HikingBag_RHand.x", "BackPacks/HikingBag_LHand.x",
          "MaleBody.x", "FemaleBody.x"]:
    out[n] = mx(X + n)
# 背包本體（z>0.08，肩帶以外）
for n in ["BackPacks/M_HikingBag.x", "BackPacks/F_HikingBag.x"]:
    V = xio.read_x(X + n)["V"]
    b = V[V[:, 2] > 0.08]
    out[n]["body_bbox"] = [b.min(0).round(4).tolist(), b.max(0).round(4).tolist()]

# 地面 FBX：節點縮放、頂點原始範圍（除 UnitScaleFactor/100，blender-headless.md §7）、世界 bbox
bpy.ops.wm.read_factory_settings(use_empty=True)
fbx = PZ + "/models_X/WorldItems/Clothing/HikingBag_Ground.fbx"
bpy.ops.import_scene.fbx(filepath=fbx)
g = {}
for o in bpy.context.scene.objects:
    e = dict(type=o.type, parent=o.parent.name if o.parent else None,
             loc=[round(x, 5) for x in o.location], rot=[round(x, 5) for x in o.rotation_euler],
             scale=[round(x, 5) for x in o.scale])
    if o.type == "MESH":
        V = np.array([v.co[:] for v in o.data.vertices])
        W = np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices])
        e.update(verts=len(V), polys=len(o.data.polygons), uv_layers=[u.name for u in o.data.uv_layers],
                 local_bbox=[V.min(0).round(4).tolist(), V.max(0).round(4).tolist()],
                 world_bbox=[W.min(0).round(4).tolist(), W.max(0).round(4).tolist()],
                 materials=[m.name for m in o.data.materials if m])
        uv = np.array([d.uv[:] for d in o.data.uv_layers[0].data]) if o.data.uv_layers else None
        if uv is not None:
            e["uv"] = [uv.min(0).round(4).tolist(), uv.max(0).round(4).tolist()]
    g[o.name] = e
# 檔內原始屬性（PZ 讀的是這些）：UnitScaleFactor、軸、節點 Lcl／Pre／Geometric 變換
from io_scene_fbx import parse_fbx
KEYS = {b"UnitScaleFactor", b"OriginalUnitScaleFactor", b"UpAxis", b"FrontAxis", b"CoordAxis", b"Lcl Translation", b"Lcl Rotation",
        b"Lcl Scaling", b"PreRotation", b"GeometricRotation", b"GeometricScaling"}
raw = {}


def walk(e):
    for q in e.elems:
        if q.id == b"P":
            if q.props[0] in KEYS:
                raw[q.props[0].decode()] = [float(x) if isinstance(x, (int, float)) else str(x) for x in q.props[4:]]
        else:
            walk(q)


walk(parse_fbx.parse(fbx)[0])
g["raw_props"] = raw
g["note"] = ("Blender 世界座標＝原始頂點×Lcl Scaling×UnitScaleFactor/100；PZ 不乘 UnitScaleFactor（items-and-icons.md §1），"
             "所以 PZ 單位＝Blender 世界座標÷(UnitScaleFactor/100)，再乘 model 腳本 scale 0.4")
out["HikingBag_Ground.fbx"] = g

tex = PZ + "/textures/Clothes/Bag/"
out["textures"] = {n: png_size(tex + n) for n in sorted(os.listdir(tex)) if n.lower().startswith("hikingbag")}

os.makedirs(TEMP, exist_ok=True)
json.dump(out, open(TEMP + "/vanilla.json", "w"), indent=1, ensure_ascii=False)
print(json.dumps(out, indent=1, ensure_ascii=False))
