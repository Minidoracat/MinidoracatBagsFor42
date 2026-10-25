"""第 1 段（Blender）：Tripo 高模 → 放到原版的 .X 空間 → 體素重建＋減面 → 展 UV → 烘兩種外觀的底色。
輸出 temp/bags/<款>/：low_body.npz（頂點、三角形、每角 UV〔Blender 慣例 v 朝上〕；座標已是 .X 模型空間）、bake_navy.png、bake_olive.png。
blender -b --factory-startup --python stage1_bake.py -- <款>
設定（bags.py）：tris＝本體三角形數（smart project 在減面網格上約拆成 2 倍頂點）、voxel＝體素大小（.X 單位，
先重建成單一封閉殼再減面，避免扣具、網袋碎片）、uv_angle、body_u＝本體 UV 佔 u∈[0, body_u]（右側留給沿用的原版子網格）。
"""
import math, os, sys
import bpy
import numpy as np
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import bags
from common import PZ, obb_axes, sel, temp, xio

BAKE_PX = 1024
cfg = bags.get(sys.argv[sys.argv.index("--") + 1])
TEMP = temp(cfg["name"])
P = cfg["place"]


def place(co):
    """Tripo（Blender：z 上、背包正面朝 −y）→ .X 模型空間（y 上、+z 朝角色背後＝背包外側）的 4×4 矩陣。
    back：等比縮放讓高度＝height、底在 y0，背板（Tripo +y 側）底端貼 z=back_z，再照原版後傾 lean（z += lean·(y−y0)）。
    日行包：平背板在 y≈0.68–0.72 被男性身體背面（z 0.099–0.102）頂穿；原版背板 y 0.56→0.83 是 z 0.083→0.132（斜率約 0.18）。
    obb：對齊原版男版本體（頂點區間 body）的主軸外框：Tripo 寬（x）→最長軸、高（z）→朝上的軸、正面（−y）→最薄軸朝外；
    等比縮放取寬、高兩個比例的幾何平均；背面貼原版背面那一層，上下、左右置中。
    front：穿在胸前的（胸掛）：Tripo 正面（−y）→角色正面（−z），繞上軸轉 180°（x 反向，det>0）；
    三軸各自縮放到原版男版外框再乘 grow（空腔要套得住身體），中心對齊原版外框中心。"""
    lo3, hi3 = co.min(0), co.max(0)
    if P["mode"] == "front":
        B = xio.read_x(PZ + "/" + cfg["worn"]["M"])["V"]
        bl, bh = B.min(0), B.max(0)
        s3 = (bh - bl) / np.array([hi3[0] - lo3[0], hi3[2] - lo3[2], hi3[1] - lo3[1]]) * P.get("grow", 1.0)
        R = np.array([[-s3[0], 0, 0], [0, 0, s3[1]], [0, s3[2], 0]])   # x_X=−x_B、y_X=z_B、z_X=y_B
        t = (bl + bh) / 2 - R @ ((lo3 + hi3) / 2)
        M = Matrix([list(R[0]) + [t[0]], list(R[1]) + [t[1]], list(R[2]) + [t[2]], [0, 0, 0, 1]])
        print(f"front: per-axis scale {s3.round(5)}; vanilla bbox {bl.round(4)} {bh.round(4)}")
        return M, float(np.cbrt(np.prod(s3)))
    if P["mode"] == "obb":
        MV = xio.read_x(PZ + "/" + cfg["worn"]["M"])
        c, ew, eh, ed, lw, lh, ld = obb_axes(MV["V"][sel(MV, P["body"])])
        tw, th = (hi3[0] - lo3[0]) * P.get("w_frac", 1.0), hi3[2] - lo3[2]   # w_frac：Tripo 寬度裡包身佔的比例（兩側腰帶短截不算）
        s = float(np.sqrt(lw / tw * lh / th))
        back = c - ed * (ld / 2 - P.get("push", 0))
        mid = np.array([(lo3[0] + hi3[0]) / 2, 0, (lo3[2] + hi3[2]) / 2])
        R = np.c_[ew, -ed, eh] * s                          # Tripo x→ew、y→−ed、z→eh
        t = back - R @ np.array([mid[0], P.get("back_y", hi3[1]), mid[2]])   # back_y：Tripo 背面 y（腰包兩側腰帶往身體彎，比背面還後面）
        M = Matrix([list(R[0]) + [t[0]], list(R[1]) + [t[1]], list(R[2]) + [t[2]], [0, 0, 0, 1]])
        print(f"obb: van extents w {lw:.4f} h {lh:.4f} d {ld:.4f}; ours w {s * tw:.4f} h {s * th:.4f} d {s * (hi3[1] - lo3[1]):.4f}")
        return M, s
    assert P["mode"] == "back", P["mode"]
    s = P["height"] / (hi3[2] - lo3[2])
    c = P["back_z"] + s * P.get("back_y", hi3[1])  # z_X = c − s·y_B：背板（y_B 最大，或 back_y）→ back_z
    M = Matrix(((s, 0, 0, -s * (lo3[0] + hi3[0]) / 2), (0, 0, s, P["y0"] - s * lo3[2]), (0, -s, 0, c), (0, 0, 0, 1)))
    M = Matrix(((1, 0, 0, 0), (0, 1, 0, 0), (0, P["lean"], 1, -P["lean"] * P["y0"]), (0, 0, 0, 1))) @ M
    print(f"scale {s:.5f}; Tripo bbox {lo3.round(4)} {hi3.round(4)}")
    return M, s


os.makedirs(TEMP, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=cfg["tripo"]["glb"])
hi = next(o for o in bpy.context.scene.objects if o.type == "MESH")
for o in list(bpy.context.scene.objects):
    if o is not hi:
        bpy.data.objects.remove(o)
co = np.empty(len(hi.data.vertices) * 3); hi.data.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
M, s = place(co)
hi.data.transform(M)                              # 旋轉＋剪切，det>0，繞序不變
hi.data.update()

# 低模：體素重建 → 減面 → 三角化
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "Low"
bpy.context.scene.collection.objects.link(lo)
lo.data.materials.clear()
bpy.context.view_layer.objects.active = lo
m = lo.modifiers.new("remesh", "REMESH"); m.mode = "VOXEL"; m.voxel_size = cfg["voxel"]; m.adaptivity = 0
bpy.ops.object.modifier_apply(modifier="remesh")
n0 = len(lo.data.polygons)
m = lo.modifiers.new("dec", "DECIMATE"); m.decimate_type = "COLLAPSE"; m.ratio = cfg["tris"] / (2 * n0); m.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
m = lo.modifiers.new("tri", "TRIANGULATE")
bpy.ops.object.modifier_apply(modifier="tri")
print(f"remesh polys {n0} -> low tris {len(lo.data.polygons)} verts {len(lo.data.vertices)}")

# UV：smart project → pack → 壓到 u∈[0, body_u]
for o in bpy.context.selected_objects:
    o.select_set(False)
lo.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(cfg["uv_angle"]), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(margin=0.012, rotate=True)
bpy.ops.object.mode_set(mode="OBJECT")
uvl = lo.data.uv_layers.active.data
uv = np.empty(len(uvl) * 2); uvl.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
uv[:, 0] *= cfg["body_u"]
uvl.foreach_set("uv", uv.ravel())

# 烘焙：Cycles 漫射色，高模 → 低模；兩種外觀共用網格與 UV，只換高模的底色貼圖
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 4
bk = sc.render.bake
bk.use_selected_to_active = True; bk.cage_extrusion = 0.01; bk.max_ray_distance = 0.03
bk.margin = 16; bk.margin_type = "EXTEND"; bk.use_pass_direct = False; bk.use_pass_indirect = False; bk.use_pass_color = True
mat = bpy.data.materials.new("bake"); lo.data.materials.append(mat)
nt = mat.node_tree
tex = nt.nodes.new("ShaderNodeTexImage"); nt.nodes.active = tex
src = next(n for n in hi.active_material.node_tree.nodes if n.type == "TEX_IMAGE" and n.outputs[0].links
           and n.outputs[0].links[0].to_socket.name == "Base Color")
for look in ("navy", "olive"):
    src.image = bpy.data.images.load(cfg["tripo"][look])
    img = bpy.data.images.new(f"bake_{look}", BAKE_PX, BAKE_PX, alpha=False)
    tex.image = img
    hi.select_set(True); lo.select_set(True); bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_selected_to_active=True, cage_extrusion=0.01,
                        max_ray_distance=0.03, margin=16, use_clear=True)
    img.filepath_raw = os.path.join(TEMP, f"bake_{look}.png"); img.file_format = "PNG"; img.save()
    print("baked", look)

# 低模資料：.X 模型空間
me = lo.data
V = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", V); V = V.reshape(-1, 3)
F = np.empty(len(me.polygons) * 3, int); me.polygons.foreach_get("vertices", F); F = F.reshape(-1, 3)
LV = np.empty(len(me.loops), int); me.loops.foreach_get("vertex_index", LV)
uv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
assert (LV.reshape(-1, 3) == F).all()
np.savez(os.path.join(TEMP, "low_body.npz"), V=V, F=F, UV=uv.reshape(-1, 3, 2), scale=s)
print("low_body", V.shape, F.shape, "bbox", V.min(0).round(4), V.max(0).round(4))
