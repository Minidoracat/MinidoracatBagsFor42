"""強化版主題款的圖示原圖（gen_theme.py 呼叫）：blender -b --factory-startup --python theme_icons.py -- job.json
job.json：[{"npz": 網格（V、F、UV，.X 空間，已去掉繞過身體的背帶）, "tex": 貼圖, "dir": 相機方向（實機的方向）, "out": 256 px 原圖}]。
做法同 stage3_blender.py 的圖示：Workbench、STUDIO 光、貼圖色、正交、透明底；shoot() 拍成實機的左右（.X 在實機是左手座標）。
後製（裁切、縮到 32、外框）在 gen_theme.py 用 build.icon，和本 MOD 7 款相同。
"""
import json
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

X2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # .X（y 上、+z 背包外側）→ Blender（z 上、外側朝 −y）
job = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "TEXTURE"; sh.show_backface_culling = True
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
sc.render.resolution_x = sc.render.resolution_y = 256
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"


def mirror_png(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    a = np.array(im.pixels[:]).reshape(h, w, 4)[:, ::-1].copy()
    im.pixels[:] = a.ravel()
    im.filepath_raw = path; im.file_format = "PNG"; im.save()
    bpy.data.images.remove(im)


for e in job:
    d = np.load(e["npz"])
    V, F, UV = d["V"], d["F"], d["UV"]
    me = bpy.data.meshes.new("bag")
    me.from_pydata(V.tolist(), [], F.tolist())
    uvl = me.uv_layers.new(name="UVMap")
    c = UV[F.ravel()].copy(); c[:, 1] = 1 - c[:, 1]
    uvl.data.foreach_set("uv", c.ravel())
    me.update()
    ob = bpy.data.objects.new("bag", me); sc.collection.objects.link(ob)
    ob.matrix_world = X2B
    mat = bpy.data.materials.new("bag")
    n = mat.node_tree.nodes.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(e["tex"]); n.interpolation = "Linear"
    mat.node_tree.links.new(n.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(mat)
    B = V @ np.array(X2B.to_3x3()).T
    center = Vector(((B.min(0) + B.max(0)) / 2).tolist())
    cam.data.ortho_scale = float(np.ptp(B, axis=0).max()) * 1.2
    dx, dy, dz = e["dir"]
    dvec = Vector((-dx, dy, dz)).normalized()   # 實機從 dir 看＝場景從 x 取負的方向看、再把圖左右翻（stage3 shoot）
    cam.location = center + dvec * 3
    cam.rotation_euler = (-dvec).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.abspath(e["out"])
    bpy.ops.render.render(write_still=True)
    mirror_png(e["out"])
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
print("theme icons done")
