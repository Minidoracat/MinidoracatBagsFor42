"""第 1 段（Blender）：Tripo 高模 → 對齊原版尺寸 → 體素重建＋減面 → 展 UV → 烘兩種外觀的底色。
輸出 temp/bags/：low_body.npz（頂點、三角形、每角 UV〔Blender 慣例 v 朝上〕；座標已是 .X 模型空間）、bake_navy.png、bake_olive.png。
blender -b --factory-startup --python stage1_bake.py
"""
import math, os, sys
import bmesh
import bpy
import numpy as np
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
from common import LEAN, PZ, TEMP, TRIPO, Y0, xio

TARGET_TRIS = 420      # 本體三角形：smart project 在減面網格上約拆成 2 倍頂點（420 面→約 410 點），加原版肩帶 148 點 ≤600
VOXEL = 0.004          # .X 單位（背包高 0.314）；先體素重建成單一封閉殼再減面，避免 Tripo 的扣具、網袋碎片
BODY_U = 0.86          # 本體 UV 佔 u∈[0, BODY_U]；右側留給原版肩帶的兩個島
BAKE_PX = 1024
FBM = {"navy": TRIPO + "/fbx/tripo_convert_aa9deccb-b6f2-42fd-b6fd-8d59ee7a682c.fbm/blue_tactical_backpack_3d_model_basecolor.JPEG",
       "olive": TRIPO + "/fbx_Umbrella/tripo_convert_96175343-aabd-4b52-ac31-42cf99cc72b6.fbm/blue_tactical_backpack_3d_model_basecolor.JPEG"}

# Tripo（Blender：z 上、背包正面朝 −y）→ .X 模型空間（y 上、+z 朝角色背後＝背包外側）。
# 等比縮放：高度對原版本體 0.5625～0.8763；背板（Tripo +y 側）底端貼在 z=BACK_Z，往上照原版後傾 LEAN（z 隨 y 加），
# 否則平背板在 y≈0.68–0.72 被男性身體背面（z 0.099–0.102）頂穿。原版背板 y 0.56→0.83 是 z 0.083→0.132（斜率約 0.18）。
H = 0.8763 - Y0
BACK_Z = 0.083

os.makedirs(TEMP, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=TRIPO + "/DayPack.glb")
hi = next(o for o in bpy.context.scene.objects if o.type == "MESH")
for o in list(bpy.context.scene.objects):
    if o is not hi:
        bpy.data.objects.remove(o)
co = np.empty(len(hi.data.vertices) * 3); hi.data.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
lo3, hi3 = co.min(0), co.max(0)
s = H / (hi3[2] - lo3[2])
c = BACK_Z + s * hi3[1]                       # z_X = c − s·y_B：y_B 最大（背板）→ BACK_Z
M = Matrix(((s, 0, 0, -s * (lo3[0] + hi3[0]) / 2), (0, 0, s, Y0 - s * lo3[2]), (0, -s, 0, c), (0, 0, 0, 1)))
M = Matrix(((1, 0, 0, 0), (0, 1, 0, 0), (0, LEAN, 1, -LEAN * Y0), (0, 0, 0, 1))) @ M   # 剪切後傾
hi.data.transform(M)                          # 旋轉＋剪切，det>0，繞序不變
hi.data.update()
print(f"scale {s:.5f}; Tripo bbox {lo3.round(4)} {hi3.round(4)}")

# 低模：體素重建 → 減面 → 三角化
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "DayPackLow"
bpy.context.scene.collection.objects.link(lo)
lo.data.materials.clear()
bpy.context.view_layer.objects.active = lo
m = lo.modifiers.new("remesh", "REMESH"); m.mode = "VOXEL"; m.voxel_size = VOXEL; m.adaptivity = 0
bpy.ops.object.modifier_apply(modifier="remesh")
n0 = len(lo.data.polygons)
m = lo.modifiers.new("dec", "DECIMATE"); m.decimate_type = "COLLAPSE"; m.ratio = TARGET_TRIS / (2 * n0); m.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
m = lo.modifiers.new("tri", "TRIANGULATE")
bpy.ops.object.modifier_apply(modifier="tri")
print(f"remesh polys {n0} -> low tris {len(lo.data.polygons)} verts {len(lo.data.vertices)}")

# UV：smart project → pack → 壓到 u∈[0, BODY_U]
for o in bpy.context.selected_objects:
    o.select_set(False)
lo.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(80), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(margin=0.012, rotate=True)
bpy.ops.object.mode_set(mode="OBJECT")
uvl = lo.data.uv_layers.active.data
uv = np.empty(len(uvl) * 2); uvl.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
uv[:, 0] *= BODY_U
uvl.foreach_set("uv", uv.ravel())

# 烘焙：Cycles 漫射色，高模 → 低模
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
for look, path in FBM.items():
    src.image = bpy.data.images.load(path)
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
