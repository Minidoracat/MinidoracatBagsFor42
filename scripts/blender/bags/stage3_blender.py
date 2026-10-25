"""第 3 段（Blender）：地面 FBX、圖示原圖、預覽圖。blender -b --factory-startup --python stage3_blender.py -- <款>
- 地面 uvfit：原版地面模型和穿戴模型用同一張圖集 → 同 UV 對點，擬合穿戴→地面的仿射套到新本體；沿用的原版子網格（肩帶、腰帶）
  用原版地面的同 UV 頂點（原版把它們重新攤在地上）。bbox：原版地面用別張圖集時，新模型最薄的方向朝上平放，等比縮到原版地面的長邊。
  匯出靜態 FBX（blender-headless.md §2），再匯入量 bbox。
- 圖示：Workbench、STUDIO 光、貼圖色，正交 256 px 透明底（items-and-icons.md §4），後製在 build.py。只畫本體：
  肩帶、腰帶是繞過身體的環，留著會把 32 px 圖示裡的包擠小一圈（日行包第一版實機圖示）。
- 預覽：新低模（兩種貼圖）疊原版身體，正／側／前／俯／3/4，給人看比例。
- 隊徽（stage2 寫了 emblem.json 的款式）：本體沿第一個隊徽的法線看，整包與特寫各一張，深藍改前（tex_Navy_plain）／改後；
  醫療包的隊徽候選版（alt/）另出預覽與圖示原圖 icon_raw_NavyAlt。
"""
import json, os, sys
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import bags
from common import PZ, fit_affine, keep_groups, obb_axes, out, sel, temp, xio
from io_scene_fbx import parse_fbx

cfg = bags.get(sys.argv[sys.argv.index("--") + 1])
NAME, TEMP, OUT = cfg["name"], temp(cfg["name"]), out(cfg["name"])
G = cfg["ground"]
GROUND_FBX = PZ + "/" + G["fbx"]
X2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # .X（y 上、+z 背包外側）→ Blender（z 上、外側朝 −y）

d = np.load(os.path.join(TEMP, "final_mesh.npz"))
V, F, UV, NB = d["V"], d["F"], d["UV"], int(d["nbody"])
M = xio.read_x(PZ + "/" + cfg["worn"]["M"])
kidx = np.concatenate(keep_groups(cfg, M)) if cfg["keep"] else np.zeros(0, int)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def fbx_props(path):
    props = {}

    def walk(e):
        for q in e.elems:
            if q.id == b"P":
                if q.props[0] == b"UnitScaleFactor":   # 節點變換在 verify_x（common.fbx_node_transforms）讀，這裡只取單位
                    props.setdefault(q.props[0].decode(), q.props[4:])
            else:
                walk(q)
    walk(parse_fbx.parse(path)[0])
    return props


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
        texmat(ob, img)
    return ob


def texmat(ob, img):
    mat = bpy.data.materials.new(ob.name)
    n = mat.node_tree.nodes.new("ShaderNodeTexImage"); n.image = img; n.interpolation = "Closest"
    mat.node_tree.links.new(n.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    mat.node_tree.nodes.active = n
    ob.data.materials.clear(); ob.data.materials.append(mat)


# ---- 地面 ----
UNIT = fbx_props(GROUND_FBX)["UnitScaleFactor"][0] / 100   # Blender 匯入時乘了，PZ 不乘（items-and-icons.md §1）
bpy.ops.import_scene.fbx(filepath=GROUND_FBX)
g = next(o for o in sc.objects if o.type == "MESH")
gme = g.data
GV = np.array([(g.matrix_world @ v.co)[:] for v in gme.vertices])
ref_bbox = (GV / UNIT).min(0), (GV / UNIT).max(0)
flat = V[:NB].copy()
if cfg["place"].get("lean"):
    flat[:, 2] -= cfg["place"]["lean"] * (flat[:, 1] - cfg["place"]["y0"])   # 穿戴版的後傾是為了貼背，平放在地上時去掉
if G["method"] == "uvfit":
    GL = np.empty(len(gme.loops), int); gme.loops.foreach_get("vertex_index", GL)
    GUV = np.empty(len(gme.loops) * 2); gme.uv_layers[0].data.foreach_get("uv", GUV)
    # 以 UV 對點：M 每個頂點找 UV 相同的地面面角；擬合的離群檢查兜底。
    # 沿用子網格每點都要對到；本體參考點對到一半以上就夠（胸掛地面是 171 點的簡化網格，338 點只對到 260）
    MUV = M["UV"].copy(); MUV[:, 1] = 1 - MUV[:, 1]
    dd = np.abs(MUV[:, None] - GUV.reshape(-1, 2)[None]).max(2)
    corr, hit = GL[dd.argmin(1)], dd.min(1) < 2e-3
    assert hit[kidx].all(), f"沿用子網格有 {int((~hit[kidx]).sum())} 個頂點在地面模型找不到同 UV 的點"
    ref = sel(M, cfg["weight_ref"])
    assert hit[ref].mean() >= 0.5, f"本體參考點只有 {hit[ref].mean():.0%} 在地面模型找得到同 UV 的點"
    ref = ref[hit[ref]]
    L, t, r, outl = fit_affine(M["V"][ref], GV[corr[ref]])
    inl = np.delete(r, outl)
    ground_fit = dict(max=float(inl.max()), rms=float(np.sqrt((inl ** 2).mean())), outliers={int(ref[i]): float(r[i]) for i in outl},
                      sv=np.linalg.svd(L, compute_uv=False).round(5).tolist(), det=float(np.linalg.det(L)))
    # 沿用子網格的邊長比（地面／穿戴×整體縮放）只記錄：攤平的地方本來就會拉長或壓短，靠預覽圖看
    if len(kidx):
        SF = M["F"][np.isin(M["F"], kidx).all(1)]
        el = lambda P: np.linalg.norm(P[SF] - P[np.roll(SF, 1, 1)], axis=2)
        ratio = el(GV[corr]) / np.maximum(el(M["V"]) * abs(ground_fit["det"]) ** (1 / 3), 1e-9)
        ground_fit["keep_edge_ratio_p5_p50_p95"] = np.percentile(ratio, [5, 50, 95]).round(3).tolist()
    GVnew = np.r_[flat @ L + t, GV[corr[kidx]]] / UNIT
else:
    if G["method"] == "upright":
        # upright：原版地面是直立的（信差包 Satchel_New：包身立著、背帶從兩個上角垂到地上，UV 和穿戴模型不同）。
        # 本體照穿戴時的主軸立起來（Blender x＝厚、y＝寬、z＝高，右手系）；沿用的長背帶比包頂高的部分壓到 1/4、前後壓到 0.3，
        # 收成包頂上的提把狀，不然整圈背帶會直直豎在包上
        c, ew, eh, ed, *_ = obb_axes(M["V"][sel(M, cfg["place"]["body"])])
        A = np.r_[flat, V[NB:]] - c
        Q = np.c_[A @ ed, A @ ew, A @ eh]
        top = Q[:NB, 2].max()
        Q[NB:, 2] = np.where(Q[NB:, 2] > top, top + (Q[NB:, 2] - top) * 0.25, Q[NB:, 2])
        Q[NB:, 0] *= 0.3
    else:
        # bbox：本體＋沿用子網格一起，主軸分析後最薄的方向朝上（原版地面用別張圖集，UV 對不到）
        P = np.r_[flat, V[NB:]] @ np.array(X2B.to_3x3()).T
        _, _, R = np.linalg.svd(P - P.mean(0))
        R[2] *= np.sign(np.linalg.det(R))                # 純旋轉，不鏡像
        Q = (P - P.mean(0)) @ R.T                        # 0＝最長、2＝最薄
    # 水平長邊對齊原版地面的長邊（要換軸時轉 90°，不鏡像），等比縮放；水平置中，最低點下面再抬到 z=0
    gsz = ref_bbox[1] - ref_bbox[0]
    if (np.ptp(Q[:, 0]) >= np.ptp(Q[:, 1])) != (gsz[0] >= gsz[1]):
        Q = np.c_[-Q[:, 1], Q[:, 0], Q[:, 2]]
    s = float(gsz[:2].max() / np.ptp(Q[:, :2], 0).max())
    Q[:, :2] -= (Q[:, :2].min(0) + Q[:, :2].max(0)) / 2
    GVnew = Q * s + np.r_[(ref_bbox[0] + ref_bbox[1])[:2] / 2, 0]
    ground_fit = dict(method=G["method"], scale=s, det=1.0)   # 兩種擺法都是純旋轉＋等比縮放
GVnew[:, 2] -= GVnew[:, 2].min()   # 新本體最低點和原版不同：整個抬到貼地（原版最低點 z=0）
print("fit M->Ground (Blender m):", ground_fit)
bpy.data.objects.remove(g)
# 日行包：原版地面在 Blender 空間是穿戴模型的鏡像（det<0）。照樣鏡像，面序反轉保持法線朝外
gob = make_mesh(f"MDB_{NAME}_Ground", GVnew, F[:, [0, 2, 1]] if ground_fit["det"] < 0 else F, UV)
for o in sc.objects:
    o.select_set(o is gob)
bpy.context.view_layer.objects.active = gob
fbx_out = f"{OUT}/models_X/WorldItems/Clothing/MDB_{NAME}_Ground.fbx"
os.makedirs(os.path.dirname(fbx_out), exist_ok=True)
bpy.ops.export_scene.fbx(filepath=fbx_out, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
                         bake_space_transform=True, axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                         add_leaf_bones=False, bake_anim=False, path_mode="STRIP")
bpy.data.objects.remove(gob)
# 讀回：Blender 匯入後世界座標＝PZ 單位×UnitScaleFactor/100；原版同樣換算後比 bbox
bpy.ops.import_scene.fbx(filepath=fbx_out)
g2 = next(o for o in sc.objects if o.type == "MESH")
W2 = np.array([(g2.matrix_world @ v.co)[:] for v in g2.data.vertices])
props = fbx_props(fbx_out)
pz_scale = 1 / (props["UnitScaleFactor"][0] / 100)
Wpz = W2 * pz_scale
guv = np.empty(len(g2.data.loops) * 2); g2.data.uv_layers[0].data.foreach_get("uv", guv); guv = guv.reshape(-1, 2)
guv[:, 1] = 1 - guv[:, 1]
np.savez(os.path.join(TEMP, "ground_check.npz"), UV=guv)   # verify_x.py 比 UV
ground = dict(fit=ground_fit, fbx_props={k: [float(x) for x in v] for k, v in props.items()},
              ours_pz_bbox=[Wpz.min(0).round(4).tolist(), Wpz.max(0).round(4).tolist()],
              vanilla_pz_bbox=[ref_bbox[0].round(4).tolist(), ref_bbox[1].round(4).tolist()], verts=len(g2.data.vertices),
              tris=len(g2.data.polygons), scale=G["scale"])
print("ground", ground)
json.dump(ground, open(os.path.join(TEMP, "ground.json"), "w"), indent=1)

# ---- 預覽與圖示 ----
imgs = {look: bpy.data.images.load(f"{OUT}/textures/Clothes/Bag/MDB_{NAME}_{look}.png") for look in ("Navy", "Olive")}
texmat(g2, imgs["Navy"])
bpy.ops.import_scene.fbx(filepath=GROUND_FBX)
gv = next(o for o in sc.objects if o.type == "MESH" and o is not g2)
texmat(gv, bpy.data.images.load(PZ + "/" + G.get("tex", cfg["keep_tex"])))
# 兩者都換成 PZ 單位（原版 ÷UNIT；我們的 ×pz_scale）並排
gw = float(ref_bbox[1][0] - ref_bbox[0][0])
gv.matrix_world = Matrix.Translation((-0.5 * gw - 0.05, 0, 0)) @ Matrix.Scale(1 / UNIT, 4) @ gv.matrix_world
g2.matrix_world = Matrix.Translation((0.5 * gw + 0.05, 0, 0)) @ Matrix.Scale(pz_scale, 4) @ g2.matrix_world
bag = make_mesh("bag", V, F, UV, imgs["Navy"])
bag.matrix_world = X2B
icon_bag = make_mesh("icon_bag", V, F[(F < NB).all(1)], UV, imgs["Navy"])
icon_bag.matrix_world = X2B
icon_bag.hide_render = True
body_x = xio.read_x(PZ + "/models_X/Skinned/MaleBody.x")
body = make_mesh("body", body_x["V"], body_x["F"])
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
shoot(f"{TEMP}/preview_ground.png", (0, 0, 0.1), (0.3, -1, 1.2), max(2.0, 2.6 * gw), 768)   # 左原版、右我們的（PZ 單位，script scale 前）
gv.hide_render = g2.hide_render = True
bag.hide_render = body.hide_render = False
Bb = V[:NB] @ np.array(X2B.to_3x3()).T
bc = cfg.get("icon", {}).get("center", tuple(((Bb.min(0) + Bb.max(0)) / 2).round(4)))   # 本體中心（Blender 座標）
io = cfg.get("icon", {}).get("ortho", round(float(np.ptp(Bb, axis=0).max()) * 1.35, 4))
idir = cfg.get("icon", {}).get("dir", (0.55, -1, 0.45))   # 看外側正面偏右上；斜掛的款式（信差包）另給
for look in ("Navy", "Olive"):
    bag.data.materials[0].node_tree.nodes.active.image = imgs[look]
    for name, dirn in (("back", (0.0001, -1, 0)), ("side", (1, 0, 0)), ("front", (0.0001, 1, 0)), ("top", (0.0001, -0.3, 1)), ("3q", (0.8, -1, 0.5))):
        shoot(f"{TEMP}/preview_{look}_{name}.png", (0, -0.05, 0.62), dirn, 0.75, 512)
    icon_bag.data.materials[0].node_tree.nodes.active.image = imgs[look]
    bag.hide_render = body.hide_render = True
    icon_bag.hide_render = False
    shoot(f"{TEMP}/icon_raw_{look}.png", bc, idir, io, 256)
    bag.hide_render = body.hide_render = False
    icon_bag.hide_render = True

ej = os.path.join(TEMP, "emblem.json")
if os.path.exists(ej):
    em = json.load(open(ej))[0]
    ec = X2B @ Vector(em["center"])
    en = X2B.to_3x3() @ Vector(em["normal"])
    views = {"Navy": imgs["Navy"], "NavyPlain": bpy.data.images.load(os.path.join(TEMP, "tex_Navy_plain.png"))}
    alt = os.path.join(TEMP, "alt", f"MDB_{NAME}_Navy.png")
    if os.path.exists(alt):
        views["NavyAlt"] = bpy.data.images.load(alt)
    bag.hide_render = body.hide_render = True
    icon_bag.hide_render = False
    for look, im in views.items():
        icon_bag.data.materials[0].node_tree.nodes.active.image = im
        shoot(f"{TEMP}/emblem_{look}_bag.png", bc, en, float(np.ptp(Bb, axis=0).max()) * 1.15, 512)
        shoot(f"{TEMP}/emblem_{look}_close.png", ec, en, em["size"][1] * 2.2, 512)
    if "NavyAlt" in views:
        icon_bag.data.materials[0].node_tree.nodes.active.image = views["NavyAlt"]
        shoot(f"{TEMP}/icon_raw_NavyAlt.png", bc, idir, io, 256)
print("stage3 done")
