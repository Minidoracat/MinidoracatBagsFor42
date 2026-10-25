"""第 3 段（Blender）：地面 FBX、圖示原圖、預覽圖。
- 地面：原版 HikingBag_Ground.fbx 和 M_HikingBag 的 412 面同序（逐角 UV 相同）→ 擬合穿戴→地面的仿射，套到新低模本體；
  肩帶用原版地面模型的同序頂點。匯出靜態 FBX（blender-headless.md §2），再匯入量 bbox。
- 圖示：Workbench、STUDIO 光、貼圖色，正交 256 px 透明底（items-and-icons.md §4），後製在第 4 段。
- 預覽：新低模（兩種貼圖）疊原版身體，正面／側面／背面／俯視，給人看比例與肩帶。
blender -b --factory-startup --python stage3_blender.py
"""
import json, math, os, sys
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
from common import PZ, TEMP, xio
from common import BELT0, LEAN, OUT, STRAP0, Y0, fit_affine

GROUND_FBX = PZ + "/models_X/WorldItems/Clothing/HikingBag_Ground.fbx"
UNIT = 0.9144   # 原版地面 FBX 的 UnitScaleFactor/100：Blender 匯入時乘了，PZ 不乘（items-and-icons.md §1）
X2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # .X（y 上、+z 背包外側）→ Blender（z 上、外側朝 −y）

d = np.load(os.path.join(TEMP, "final_mesh.npz"))
V, F, UV, NB = d["V"], d["F"], d["UV"], int(d["nbody"])
M = xio.read_x(PZ + "/models_X/Skinned/BackPacks/M_HikingBag.x")
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def make_mesh(name, V, F, UV=None, img=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], F.tolist())
    if UV is not None:
        uvl = me.uv_layers.new(name="UVMap")
        c = UV[F.ravel()].copy(); c[:, 1] = 1 - c[:, 1]
        uvl.data.foreach_set("uv", c.ravel())
    me.update()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    if img:
        mat = bpy.data.materials.new(name)
        n = mat.node_tree.nodes.new("ShaderNodeTexImage"); n.image = img; n.interpolation = "Closest"
        mat.node_tree.links.new(n.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        mat.node_tree.nodes.active = n
        me.materials.append(mat)
    return ob


# ---- 地面 ----
bpy.ops.import_scene.fbx(filepath=GROUND_FBX)
g = next(o for o in sc.objects if o.type == "MESH")
gme = g.data
GV = np.array([(g.matrix_world @ v.co)[:] for v in gme.vertices])
GL = np.empty(len(gme.loops), int); gme.loops.foreach_get("vertex_index", GL)
GUV = np.empty(len(gme.loops) * 2); gme.uv_layers[0].data.foreach_get("uv", GUV); GUV = GUV.reshape(-1, 3, 2)
GL = GL.reshape(-1, 3)
assert len(GL) == len(M["F"]) == 412
# 面序和穿戴模型不同 → 以 UV 對點：M 每個頂點找 UV 相同的地面面角（原版 UV 島不重疊，同 UV＝同一點）；擬合的離群檢查兜底
MUV = M["UV"].copy(); MUV[:, 1] = 1 - MUV[:, 1]
GUVf, GLf = GUV.reshape(-1, 2), GL.ravel()
dd = np.abs(MUV[:, None] - GUVf[None]).max(2)
corr = GLf[dd.argmin(1)]
assert dd.min(1).max() < 2e-3, f"有 {int((dd.min(1) >= 2e-3).sum())} 個頂點在地面模型找不到同 UV 的點"
assert (corr >= 0).all()
ref = np.arange(BELT0)
L, t, r, out = fit_affine(M["V"][ref], GV[corr[ref]])
inl = np.delete(r, out)
ground_fit = dict(max=float(inl.max()), rms=float(np.sqrt((inl ** 2).mean())), outliers={int(i): float(r[i]) for i in out},
                  sv=np.linalg.svd(L, compute_uv=False).round(5).tolist())
ground_fit["det"] = float(np.linalg.det(L))
print("fit M->Ground (Blender m):", ground_fit)
# 肩帶用原版地面的同序頂點（原版地面把肩帶重新攤在地上，不是同一個仿射：殘差中位數約 0.1 m）。
# UV 對點的距離都 <2e-3；邊長比（地面／穿戴×整體縮放）只記錄，攤平的地方本來就會拉長或壓短，靠預覽圖看
SF = M["F"][264:]
el = lambda P: np.linalg.norm(P[SF] - P[np.roll(SF, 1, 1)], axis=2)
ratio = el(GV[corr]) / np.maximum(el(M["V"]) * abs(ground_fit["det"]) ** (1 / 3), 1e-9)
ground_fit["strap_edge_ratio_p5_p50_p95"] = np.percentile(ratio, [5, 50, 95]).round(3).tolist()
flat = V[:NB].copy()
flat[:, 2] -= LEAN * (flat[:, 1] - Y0)   # 穿戴版的後傾是為了貼背，平放在地上時去掉
GVnew = np.r_[flat @ L + t, GV[corr[STRAP0:]]] / UNIT
GVnew[:, 2] -= GVnew[:, 2].min()   # 新本體最低點和原版不同：整個抬到貼地（原版最低點 z=0）
ref_bbox = (GV / UNIT).min(0), (GV / UNIT).max(0)
bpy.data.objects.remove(g)
# 原版地面在 Blender 空間是穿戴模型的鏡像（det<0）：照樣鏡像，面序反轉保持法線朝外
gob = make_mesh("MDB_DayPack_Ground", GVnew, F[:, [0, 2, 1]] if ground_fit["det"] < 0 else F, UV)
for o in sc.objects:
    o.select_set(o is gob)
bpy.context.view_layer.objects.active = gob
fbx_out = f"{OUT}/models_X/WorldItems/Clothing/MDB_DayPack_Ground.fbx"
os.makedirs(os.path.dirname(fbx_out), exist_ok=True)
bpy.ops.export_scene.fbx(filepath=fbx_out, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
                         bake_space_transform=True, axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                         add_leaf_bones=False, bake_anim=False, path_mode="STRIP")
bpy.data.objects.remove(gob)
# 讀回：Blender 匯入後世界座標＝PZ 單位×UnitScaleFactor/100；原版同樣換算後比 bbox
bpy.ops.import_scene.fbx(filepath=fbx_out)
g2 = next(o for o in sc.objects if o.type == "MESH")
usf = sc.unit_settings.scale_length
W2 = np.array([(g2.matrix_world @ v.co)[:] for v in g2.data.vertices])
from io_scene_fbx import parse_fbx
root, _ = parse_fbx.parse(fbx_out)
props = {}


def walk(e):
    for q in e.elems:
        if q.id == b"P":
            if q.props[0] in (b"UnitScaleFactor", b"Lcl Scaling", b"Lcl Rotation", b"PreRotation"):
                props.setdefault(q.props[0].decode(), q.props[4:])
        else:
            walk(q)


walk(root)
pz_scale = 1 / (props["UnitScaleFactor"][0] / 100)
Wpz = W2 * pz_scale
guv = np.empty(len(g2.data.loops) * 2); g2.data.uv_layers[0].data.foreach_get("uv", guv); guv = guv.reshape(-1, 2)
guv[:, 1] = 1 - guv[:, 1]
np.savez(os.path.join(TEMP, "ground_check.npz"), UV=guv)   # verify_x.py 比 UV 集合
ground = dict(fit=ground_fit, fbx_props={k: [float(x) for x in v] for k, v in props.items()},
              ours_pz_bbox=[Wpz.min(0).round(4).tolist(), Wpz.max(0).round(4).tolist()],
              vanilla_pz_bbox=[ref_bbox[0].round(4).tolist(), ref_bbox[1].round(4).tolist()], verts=len(g2.data.vertices),
              tris=len(g2.data.polygons))
print("ground", ground)
json.dump(ground, open(os.path.join(TEMP, "ground.json"), "w"), indent=1)

# ---- 預覽與圖示 ----
imgs = {look: bpy.data.images.load(f"{OUT}/textures/Clothes/Bag/MDB_DayPack_{look}.png") for look in ("Navy", "Olive")}


def texmat(ob, img):
    mat = bpy.data.materials.new(ob.name)
    n = mat.node_tree.nodes.new("ShaderNodeTexImage"); n.image = img; n.interpolation = "Closest"
    mat.node_tree.links.new(n.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    mat.node_tree.nodes.active = n
    ob.data.materials.clear(); ob.data.materials.append(mat)


texmat(g2, imgs["Navy"])
bpy.ops.import_scene.fbx(filepath=GROUND_FBX)
gv = next(o for o in sc.objects if o.type == "MESH" and o is not g2)
texmat(gv, bpy.data.images.load(PZ + "/textures/Clothes/Bag/HikingBagBlue.png"))
# 兩者都換成 PZ 單位（原版 ÷UNIT；我們的 ×pz_scale）並排
gv.matrix_world = Matrix.Translation((-0.4, 0, 0)) @ Matrix.Scale(1 / UNIT, 4) @ gv.matrix_world
g2.matrix_world = Matrix.Translation((0.4, 0, 0)) @ Matrix.Scale(pz_scale, 4) @ g2.matrix_world
bag = make_mesh("bag", V, F, UV, imgs["Navy"])
bag.matrix_world = X2B
# 圖示只畫本體：肩帶是繞過肩膀的環，留著會把 32 px 圖示裡的背包擠小一圈（第一版實機圖示）
icon_bag = make_mesh("icon_bag", V, F[(F < NB).all(1)], UV, imgs["Navy"])
icon_bag.matrix_world = X2B
icon_bag.hide_render = True
body = make_mesh("body", xio.read_x(PZ + "/models_X/Skinned/MaleBody.x")["V"], xio.read_x(PZ + "/models_X/Skinned/MaleBody.x")["F"])
body.matrix_world = X2B
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "TEXTURE"; sh.show_backface_culling = True
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"


def shoot(path, center, direction, ortho, px):
    sc.render.resolution_x = sc.render.resolution_y = px
    cam.data.ortho_scale = ortho
    c = Vector(center)
    cam.location = c + Vector(direction).normalized() * 3
    cam.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)


bag.hide_render = body.hide_render = True
shoot(f"{TEMP}/preview_ground.png", (0, 0, 0.1), (0.3, -1, 1.2), 2.0, 768)   # 左原版、右我們的（PZ 單位，script scale 前）
gv.hide_render = g2.hide_render = True
bag.hide_render = body.hide_render = False
bc = (0, -0.16, 0.72)   # 背包中心（Blender 座標）
for look in ("Navy", "Olive"):
    bag.data.materials[0].node_tree.nodes.active.image = imgs[look]
    for name, dirn in (("back", (0.0001, -1, 0)), ("side", (1, 0, 0)), ("front", (0.0001, 1, 0)), ("top", (0.0001, -0.3, 1)), ("3q", (0.8, -1, 0.5))):
        shoot(f"{TEMP}/preview_{look}_{name}.png", (0, -0.05, 0.62), dirn, 0.75, 512)
    icon_bag.data.materials[0].node_tree.nodes.active.image = imgs[look]
    bag.hide_render = body.hide_render = True
    icon_bag.hide_render = False
    shoot(f"{TEMP}/icon_raw_{look}.png", bc, (0.55, -1, 0.45), 0.42, 256)
    bag.hide_render = body.hide_render = False
    icon_bag.hide_render = True
print("stage3 done")
