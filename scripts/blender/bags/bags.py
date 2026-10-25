"""每款背包一份設定（build.py <款>）。原版樣板照 MDB_Items.txt 每件上方註明借用的那款。

欄位（路徑都相對 PZ media/）：
  worn      男女穿戴模板 .X（反綁定矩陣、骨架、動畫原樣照抄）；alt＝ClothingItem 的 m_Alt*Model 模板（胸掛）
  hands     手持模板；原版沒有手持模型的款式寫 None（物品不加 ReplaceIn*Hand）
  L_from_R  左手怎麼來：negate＝右手點對稱（原版日行包實測逐點相同）；icp＝用原版左右手點雲對齊求的變換
  bones     穿戴骨頭白名單（≤5）；merge＝砍掉的骨頭權重併到哪根
  corr      原版各版本之間怎麼對點：faces＝面序相同逐角對（日行包）；uv＝同 UV 對點，歧義用仿射擬合挑最近的
  deform    本體怎麼搬到女版／手持：affine＝單一仿射（日行包殘差 ~0）；field＝仿射＋最近 4 點的殘差位移場；
            field_ref＝同 field，但只用 weight_ref 的本體點（沿用子網格在手持模型裡被捲起來的款式）
  keep_from 沿用子網格在女版／手持的位置：預設逐點取對到的原版點；smooth＝男版位置＋鄰近位移中位數（雙面薄片正反同 UV 的款式）
  keep      沿用的原版子網格（肩帶、腰帶）：每組一個 UV 島，(a, b)＝原版男版頂點區間、("uv", 矩形)＝UV 在矩形內的點（weight_ref、body 同）；islands＝(原版 UV 矩形, 新矩形, 轉 90°)，None＝自動
  weight_ref 本體權重參考的原版頂點區間（不含 keep 和不要的部分）
  place     Tripo 高模放到 .X 空間的方式：back＝背在背後（底 y0、高、背板 back_z、後傾 lean、背面 back_y；side="front" 改掛肚子前）；obb＝對齊原版本體（body）的主軸外框，push＝沿外側法線再推出去，w_frac＝Tripo 寬度裡包身佔的比例，back_y＝Tripo 背面的 y（預設最大 y）；
            tris／voxel／uv_angle／body_u 見 stage1_bake.py；icon＝圖示相機（center、ortho、dir，沒寫就自動）
  ground    原版地面模型：fbx、腳本 scale；method uvfit＝用同 UV 擬合穿戴→地面；upright＝原版地面直立、UV 另一套時，本體照穿戴主軸立起；
            bbox＝原版地面用別張圖集時，最薄方向朝上擺平
  skin_push 本體頂點貼進身體超過原版最貼的那點時沿身體法線推出去（stage2）
  clearance closed＝身體頂點不能在封閉本體裡（背在背後的）；skin＝每個頂點沿最近身體頂點法線的距離不比原版差 5 mm 以上（繞身體的）
  bedroll   AttachmentsProvided 的睡袋掛點 y（本體底部要在它上面）
"""
from common import TRIPO_ROOT

TRIPO_DAYPACK = TRIPO_ROOT + "/日行背包(DayPack)/model"

BAGS = {
    "DayPack": dict(
        tripo=dict(glb=TRIPO_DAYPACK + "/DayPack.glb",
                   navy=TRIPO_DAYPACK + "/fbx/tripo_convert_aa9deccb-b6f2-42fd-b6fd-8d59ee7a682c.fbm/blue_tactical_backpack_3d_model_basecolor.JPEG",
                   olive=TRIPO_DAYPACK + "/fbx_Umbrella/tripo_convert_96175343-aabd-4b52-ac31-42cf99cc72b6.fbm/blue_tactical_backpack_3d_model_basecolor.JPEG"),
        worn=dict(M="models_X/Skinned/BackPacks/M_HikingBag.x", F="models_X/Skinned/BackPacks/F_HikingBag.x"),
        alt=None,
        hands=dict(R="models_X/Skinned/BackPacks/HikingBag_RHand.x", L="models_X/Skinned/BackPacks/HikingBag_LHand.x"),
        L_from_R="negate",
        bones=["Bip01_BackPack", "Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_R_Clavicle"], merge={},
        corr="faces", deform="affine",
        keep=[(251, 326), (326, 399)],          # 兩條肩帶；195-250 是繞到前面的腰帶，不要
        islands=[((0.010, 0.120, 0.136, 0.477), (0.872, 0.010, 0.992, 0.490), False),
                 ((0.010, 0.005, 0.334, 0.124), (0.872, 0.510, 0.992, 0.990), True)],
        keep_tex="textures/Clothes/Bag/HikingBagBlue.png",
        weight_ref=(0, 195),
        place=dict(mode="back", y0=0.5625, height=0.8763 - 0.5625, back_z=0.083, lean=0.17),
        tris=420, voxel=0.004, uv_angle=80, body_u=0.86,
        ground=dict(fbx="models_X/WorldItems/Clothing/HikingBag_Ground.fbx", scale=0.4, method="uvfit"),
        clearance="closed", bedroll=0.509,
        icon=dict(center=(0, -0.16, 0.72), ortho=0.42),   # 圖示相機（Blender 座標）；沒寫就照本體外框自動
    ),
    # ---- 以下 6 款：原版那半邊先填好；Tripo 那半邊（tripo、place、keep、islands、weight_ref、tris）收到模型才填 ----
    "ExpeditionPack": dict(   # 借 Base.Bag_BigHikingBag
        tripo=dict(glb=TRIPO_ROOT + "/遠征框架背包(ExpeditionPack)/model/ExpeditionPack.glb",
                   navy=TRIPO_ROOT + "/遠征框架背包(ExpeditionPack)/model/fbx/tripo_convert_94d7dec8-740a-4873-b5a5-aa9ce4fcf401.fbm/tactical_backpack_3d_model_basecolor.JPEG",
                   olive=TRIPO_ROOT + "/遠征框架背包(ExpeditionPack)/model/fbx_Umbrella/tactical_backpack_3d_model.fbm/tactical_backpack_3d_model_basecolor.jpg"),
        worn=dict(M="models_X/Skinned/BackPacks/M_BigHikingBag.x", F="models_X/Skinned/BackPacks/F_BigHikingBag.x"),
        alt=None,
        hands=dict(R="models_X/Skinned/BackPacks/BigHikingBag_RHand.x", L="models_X/Skinned/BackPacks/BigHikingBag_LHand.x"),
        L_from_R="icp",
        # 原版 7 骨：L／R_UpperArm 各只有 2 個頂點、權重約 0.02，併回同側鎖骨
        bones=["Bip01_BackPack", "Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_R_Clavicle"],
        merge={"Bip01_L_UpperArm": "Bip01_L_Clavicle", "Bip01_R_UpperArm": "Bip01_R_Clavicle"},
        corr="uv", deform="field",
        # 原版男版三塊：0-353 包身（含 291-306、319-353 繞到前面的腰帶，307-318 背板上的小扣片）、354-428 與 429-508 兩條肩帶（x<0、x>0）
        keep=[(354, 429), (429, 509)], islands=None,
        keep_tex="textures/Clothes/Bag/BigHikingBagBlue.png",
        weight_ref=(0, 291),
        # 底部照原版 0.5235（睡袋 BedrollBottomBig 掛點和一般款同一點，models_characters.txt:364-369），高度到原版頂 0.8974；
        # 背板起點與後傾先沿用日行包（同一副男性身體）
        place=dict(mode="back", y0=0.5235, height=0.8974 - 0.5235, back_z=0.083, lean=0.17),
        tris=400, voxel=0.008, uv_angle=80, body_u=0.86,   # 0.004 時背架細管減面後正反面相疊（面朝外 90%），UV 拆到 613 點
        ground=dict(fbx="models_X/WorldItems/Clothing/BigHikingBag_Ground.fbx", scale=0.4, method="uvfit"),
        clearance="closed", bedroll=0.509,
    ),
    "CourierSatchel": dict(   # 借 Base.Bag_Satchel_Military
        tripo=dict(glb=TRIPO_ROOT + "/信差側背包(CourierSatchel)/model/CourierSatchel.glb",
                   navy=TRIPO_ROOT + "/信差側背包(CourierSatchel)/model/fbx/tripo_convert_621b0dd8-c572-4020-9a6e-7e1b5305c84d.fbm/tactical_messenger_bag_3d_model_basecolor.JPEG",
                   olive=TRIPO_ROOT + "/信差側背包(CourierSatchel)/model/fbx_Umbrella/tactical_messenger_bag_3d_model.fbm/tactical_messenger_bag_3d_model_basecolor.jpg"),
        worn=dict(M="models_X/Skinned/BackPacks/M_Satchel_New.x", F="models_X/Skinned/BackPacks/F_Satchel_New.x"),
        alt=None,
        hands=dict(R="models_X/Skinned/BackPacks/Satchel_New_RHand.x", L="models_X/Skinned/BackPacks/Satchel_New_LHand.x"),
        L_from_R="icp",
        bones=["Bip01_BackPack", "Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_L_UpperArm"], merge={},
        corr="uv", deform="field_ref", keep_from="smooth",
        # 原版男版五塊：0-149 斜背帶（掛左肩，骨頭有 L_Clavicle／L_UpperArm）、150-254 包身、255-278 與 279-302 背帶兩端扣環、303-375 包頂上的一段背帶。
        # Tripo 只有兩個上角的短帶耳，長背帶與扣環沿用原版
        keep=[(0, 150), (255, 279), (279, 303), (303, 376)],
        islands=[((0.007, 0.903, 0.996, 0.999), (0.872, 0.010, 0.992, 0.640), True),
                 ((0.804, 0.045, 0.899, 0.164), (0.872, 0.660, 0.992, 0.740), False),
                 ((0.801, 0.049, 0.899, 0.159), (0.872, 0.760, 0.992, 0.840), False),
                 ((0.350, 0.907, 0.750, 0.999), (0.872, 0.860, 0.992, 0.990), True)],
        keep_tex="textures/Clothes/Bag/Satchel_Military.png",
        weight_ref=(150, 255),
        place=dict(mode="obb", body=(150, 255), push=0.008),   # 原版包身斜掛在後腰一側（寬軸繞 y 轉約 27°）；背面貼原版背面時離臀部 −5 mm，往外推 8 mm
        tris=300, voxel=0.003, uv_angle=80, body_u=0.86,
        icon=dict(dir=(-0.18, -1, 0.5)),           # 包身外側法線（Blender 座標約 (−0.45, −0.89, 0.06)）偏右上
        ground=dict(fbx="models_X/WorldItems/Clothing/Satchel_New.fbx", scale=0.08, method="upright"),   # 原版地面 UV 自成一套（u 跨 −0.6～1.6），對不到
        clearance="skin", bedroll=None,
    ),
    "ScoutChestRig": dict(    # 借 Base.Bag_ChestRig
        tripo=dict(glb=TRIPO_ROOT + "/偵察胸掛(ScoutChestRig)/model/ScoutChestRig.glb",
                   navy=TRIPO_ROOT + "/偵察胸掛(ScoutChestRig)/model/fbx/tripo_convert_2bbbcaf7-5a4b-4914-8ca6-828143829178.fbm/tactical_vest_3d_model_basecolor.JPEG",
                   olive=TRIPO_ROOT + "/偵察胸掛(ScoutChestRig)/model/fbx_Umbrella/tactical_vest_3d_model.fbm/tactical_vest_3d_model_basecolor.jpg"),
        worn=dict(M="models_X/Skinned/Clothes/Bob_ChestRig.x", F="models_X/Skinned/Clothes/Kate_ChestRig.x"),
        alt=dict(M="models_X/Skinned/Clothes/Bob_ChestRig_ALT.x", F="models_X/Skinned/Clothes/Kate_ChestRig_ALT.x"),
        hands=None, L_from_R=None,
        bones=["Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_R_Clavicle"], merge={},
        corr="uv", deform="field",
        # 原版是一整片（338 點），Tripo 有自己的肩帶、背後 X 帶與腰帶，原版不沿用
        keep=[], islands=None,
        keep_tex="textures/Clothes/Bag/ChestRig.png",
        weight_ref=(0, 338),
        place=dict(mode="front", grow=1.0),
        icon=dict(dir=(-0.55, 1, 0.45)),   # 看正面（Blender +y＝角色正面），不是背後的 X 帶
        thin=True,   # 帶子是薄片，減面後正反兩面共用頂點（stage2 split_body）
        tris=400, voxel=0.002, uv_angle=89, body_u=1.0,   # 帶子是薄片：voxel 0.003 會斷成 6 塊；面數再多 UV 接縫點超過 600
        ground=dict(fbx="models_X/WorldItems/Clothing/ChestRig_Ground.fbx", scale=0.15, method="uvfit"),
        clearance="skin", bedroll=None,
    ),
    "MedicHipPouch": dict(    # 借 Base.Bag_FannyPackBack
        tripo=dict(glb=TRIPO_ROOT + "/醫療腰包(MedicHipPouch)/model/MedicHipPouch.glb",
                   navy=TRIPO_ROOT + "/醫療腰包(MedicHipPouch)/model/fbx/tripo_convert_efd8f899-13a6-4548-9002-449be9d039ea.fbm/waist_bag_3d_model_basecolor.JPEG",
                   olive=TRIPO_ROOT + "/醫療腰包(MedicHipPouch)/model/fbx_Umbrella/waist_bag_3d_model.fbm/waist_bag_3d_model_basecolor.jpg"),
        worn=dict(M="models_X/Skinned/BackPacks/M_FannyPactBack.x", F="models_X/Skinned/BackPacks/F_FannyPactBack.x"),
        alt=None, hands=None, L_from_R=None,
        bones=["Bip01_Pelvis"], merge={},
        corr="uv", deform="field",
        # 原版一整片 112 點：UV v>0.5 的兩個島是包身（背後），v 0.33-0.48 的兩個島是繞到前面的腰帶；腰帶沿用
        keep=[("uv", (0, 0.3, 1, 0.5))], islands=None,
        keep_tex="textures/Clothes/Bag/FannyPack.png",
        weight_ref=("uv", (0, 0.5, 1, 1)),
        # 原版包身扁（寬 0.19、高 0.06），Tripo 是方包：照原版大小會壓進臀部（y 0.46-0.52 的臀部 z 到 0.093）。
        # 改用 back 擺法：方包高 0.113（寬約 0.11，兩側腰帶短截到 ±0.083），底 y 0.49，背面 z 0.085（臀部最凸處再由 skin_push 推出）；
        # Tripo 背面 y≈0.035（兩側腰帶往身體彎到 y 0.36，不能拿最大 y 當背面）
        place=dict(mode="back", y0=0.49, height=0.113, back_z=0.085, lean=0.0, back_y=0.035),
        thin=True,   # 兩側腰帶短截與插扣是薄片
        skin_push=True,   # Tripo 背面那條橫腰帶會壓進下背：推到原版最貼身的距離（stage2）
        tris=300, voxel=0.002, uv_angle=80, body_u=0.86,
        ground=dict(fbx="models_X/WorldItems/Clothing/M_FannyPackFront_Ground.fbx", scale=0.4, method="uvfit"),
        clearance="skin", bedroll=None,
    ),
    "ToolBeltPouch": dict(    # 借 Base.Bag_FannyPackFront
        tripo=dict(glb=TRIPO_ROOT + "/腰掛工具包(ToolBeltPouch)/model/ToolBeltPouch.glb",
                   navy=TRIPO_ROOT + "/腰掛工具包(ToolBeltPouch)/model/fbx/tripo_convert_2c72b989-27f5-4774-8dc4-bac21403b63d.fbm/navy_waist_bag_3d_model_basecolor.JPEG",
                   olive=TRIPO_ROOT + "/腰掛工具包(ToolBeltPouch)/model/fbx_Umbrella/tripo_convert_6d38bd42-33df-468b-a654-2b371e59a9f3.fbm/navy_waist_bag_3d_model_basecolor.JPEG"),
        worn=dict(M="models_X/Skinned/BackPacks/M_FannyPackFront.x", F="models_X/Skinned/BackPacks/F_FannyPackFront.x"),
        alt=None, hands=None, L_from_R=None,
        bones=["Bip01_Pelvis", "Bip01_Spine", "Bip01_Spine1", "Bip01_L_Thigh", "Bip01_R_Thigh"], merge={},
        corr="uv", deform="field",
        # 原版和醫療腰包同一套 UV：v>0.5 是包身（肚子前），v 0.33-0.48 是繞到背後的腰帶；腰帶沿用
        keep=[("uv", (0, 0.3, 1, 0.5))], islands=None,
        keep_tex="textures/Clothes/Bag/FannyPack.png",
        weight_ref=("uv", (0, 0.5, 1, 1)),
        # 主袋加兩側袋寬 0.84（Tripo 單位）、高 0.455，腰帶在上緣 z 0.27-0.41。縮 0.2 倍：寬 0.17 同原版，
        # 腰帶中心落在原版腰帶 y≈0.565；背面 y≈0.066（兩側腰帶往身體彎到 0.34），背面放在 z −0.05，肚子再由 skin_push 推出
        place=dict(mode="back", side="front", y0=0.497, height=0.091, back_z=0.05, lean=0.0, back_y=0.066),
        icon=dict(dir=(-0.55, 1, 0.45)),   # 看外側（角色正面）
        thin=True, skin_push=True,
        tris=360, voxel=0.002, uv_angle=80, body_u=0.86,
        ground=dict(fbx="models_X/WorldItems/Clothing/M_FannyPackFront_Ground.fbx", scale=0.4, method="uvfit"),
        clearance="skin", bedroll=None,
    ),
    "AmmoBandolier": dict(    # 借 Base.AmmoStrap_Shells
        worn=dict(M="models_X/Skinned/Clothes/Bob_AmmoStrap.x", F="models_X/Skinned/Clothes/Kate_AmmoStrap.x"),
        alt=None, hands=None, L_from_R=None,
        # 原版 8 骨。背帶從左肩斜到右髖，留軀幹三節＋左肩兩節；Neck（38 點）、Head（20 點）只在領口附近，併進 Spine1；
        # R_UpperArm（8 點）是右腋下那段，也併進 Spine1
        bones=["Bip01_Spine1", "Bip01_Spine", "Bip01_Pelvis", "Bip01_L_Clavicle", "Bip01_L_UpperArm"],
        merge={"Bip01_Neck": "Bip01_Spine1", "Bip01_Head": "Bip01_Spine1", "Bip01_R_UpperArm": "Bip01_Spine1"},
        corr="uv", deform="field",
        keep_tex="textures/Clothes/Straps/AmmoStrap_Shells.png",
        # 原版地面 WorldItems/AmmoStrap 用另一張圖集（WorldItems/AmmoStrap_Shells），UV 對不到穿戴模型
        ground=dict(fbx="models_X/WorldItems/AmmoStrap.fbx", scale=0.4, method="bbox"),
        clearance="skin", bedroll=None,
    ),
}


def get(name):
    cfg = dict(BAGS[name], name=name)
    missing = [k for k in ("tripo", "place", "keep", "weight_ref", "tris") if k not in cfg]
    if missing:
        raise SystemExit(f"{name} 的設定缺 {missing}：Tripo 模型到了才填（bags.py）")
    return cfg
