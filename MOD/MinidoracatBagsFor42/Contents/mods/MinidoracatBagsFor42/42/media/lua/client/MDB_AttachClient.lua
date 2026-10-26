-- 強化版背包額外掛點的 client 兩層（另兩層在 shared/MDB_Attach.lua）：
--   快捷列定義 ISHotbarAttachDefinition，以及 FemaleBody／MaleBody 的模型掛點。
-- 模型掛點不能用 model 腳本加：同名 model 腳本整份重設再載入（ScriptType.java:108-116、ScriptBucket.java:181-191），
-- 會蓋掉原版與其他 MOD 的掛點。改在腳本載入後用 ModelScript:addAttachment 加（ModelScript.java:194-199，原版
-- AttachmentEditorUI.lua:637-638 同樣做法）；ModelScript 每次 Lua 重載前都重新讀過，這裡照名稱找到就只改值。
require "Hotbar/ISHotbarAttachDefinition"
require "Hotbar/ISHotbar"

-- ===== 座標 =====
-- 全部掛在 Bip01_BackPack（原版背包的掛點骨頭）。骨頭空間：+x 離開背部朝外、+y 角色左邊、+z 往上。
-- 位置起點由 scripts/blender/attach/anchors.py 從原版穿戴網格算出，再照實機截圖（E2E attach-art-sp）調整。
-- ANCHOR[家族][性別][掛點] = { x, y, z, yaw }：yaw 是掛點那一面的朝向（繞 z 轉，度）：背面與頂部 0、右側 -90、左側 90。
local ANCHOR = {
    Alice = {
        M = { Slot1 = { 0.139, 0.055, -0.027, 0 }, Slot2 = { 0.145, 0.000, -0.027, 0 }, Slot3 = { 0.138, -0.055, -0.027, 0 },
              Plushie = { 0.101, 0.000, 0.090, 0 }, BottleR = { 0.044, -0.114, -0.066, -90 }, BottleL = { 0.044, 0.120, -0.066, 90 },
              UmbrellaR = { 0.100, -0.117, -0.001, -90 }, Flashlight = { 0.044, 0.110, 0.064, 90 } },
        F = { Slot1 = { 0.121, 0.055, -0.018, 0 }, Slot2 = { 0.134, 0.000, -0.018, 0 }, Slot3 = { 0.124, -0.055, -0.018, 0 },
              Plushie = { 0.090, 0.000, 0.099, 0 }, BottleR = { 0.030, -0.113, -0.057, -90 }, BottleL = { 0.030, 0.119, -0.057, 90 },
              UmbrellaR = { 0.087, -0.117, 0.008, -90 }, Flashlight = { 0.030, 0.110, 0.073, 90 } },
    },
    Duffel = {
        M = { Slot1 = { 0.148, 0.070, -0.074, 0 }, Slot2 = { 0.138, -0.020, -0.118, 0 }, Slot3 = { 0.119, -0.110, -0.139, 0 },
              Plushie = { 0.060, 0.138, -0.014, 0 }, BottleR = { 0.095, -0.161, -0.148, -90 }, UmbrellaR = { 0.060, -0.191, -0.148, -90 },
              Flashlight = { 0.060, -0.050, -0.036, 0 } },
        F = { Slot1 = { 0.140, 0.070, -0.067, 0 }, Slot2 = { 0.133, -0.020, -0.115, 0 }, Slot3 = { 0.119, -0.110, -0.142, 0 },
              Plushie = { 0.060, 0.137, -0.000, 0 }, BottleR = { 0.110, -0.140, -0.143, -90 }, UmbrellaR = { 0.060, -0.170, -0.143, -90 },
              Flashlight = { 0.060, -0.050, -0.036, 0 } },
    },
    Hiking = {
        M = { Slot1 = { 0.096, 0.055, -0.021, 0 }, Slot2 = { 0.108, 0.000, -0.021, 0 }, Slot3 = { 0.096, -0.055, -0.021, 0 },
              Plushie = { 0.077, 0.000, 0.163, 0 }, BottleR = { 0.036, -0.104, -0.068, -90 }, BottleL = { 0.036, 0.101, -0.068, 90 },
              UmbrellaL = { 0.083, 0.074, 0.011, 90 }, Flashlight = { 0.036, -0.077, 0.089, -90 } },
        F = { Slot1 = { 0.073, 0.055, -0.018, 0 }, Slot2 = { 0.085, 0.000, -0.018, 0 }, Slot3 = { 0.073, -0.055, -0.018, 0 },
              Plushie = { 0.053, 0.000, 0.162, 0 }, BottleR = { 0.014, -0.102, -0.064, -90 }, BottleL = { 0.014, 0.099, -0.064, 90 },
              UmbrellaL = { 0.060, 0.073, 0.013, 90 }, Flashlight = { 0.014, -0.075, 0.090, -90 } },
    },
    BigHiking = {
        M = { Slot1 = { 0.092, 0.055, -0.036, 0 }, Slot2 = { 0.102, 0.000, -0.036, 0 }, Slot3 = { 0.092, -0.055, -0.036, 0 },
              Plushie = { 0.064, 0.000, 0.181, 0 }, BottleR = { 0.031, -0.106, -0.092, -90 }, BottleL = { 0.031, 0.102, -0.092, 90 },
              UmbrellaL = { 0.074, 0.074, 0.002, 90 }, Flashlight = { 0.031, -0.079, 0.095, -90 } },
        F = { Slot1 = { 0.072, 0.055, -0.032, 0 }, Slot2 = { 0.082, 0.000, -0.032, 0 }, Slot3 = { 0.072, -0.055, -0.032, 0 },
              Plushie = { 0.044, 0.000, 0.185, 0 }, BottleR = { 0.011, -0.106, -0.088, -90 }, BottleL = { 0.011, 0.102, -0.088, 90 },
              UmbrellaL = { 0.053, 0.074, 0.006, 90 }, Flashlight = { 0.011, -0.079, 0.099, -90 } },
    },
}
-- 擺法：物品模型在掛點那一面的旋轉與位移。面座標：+x 朝外（離開包面）、+y 面的左邊、+z 往上。
-- POSE[擺法] = { rx, ry, rz, dx, dy, dz }，旋轉照 JOML rotateXYZ（ModelInstanceRenderData.java:106-111）。
-- 拿在手上的模型（StaticModel／WeaponSprite）握點在原點、握柄與頭沿 +y、扁平物品（鋸、剁刀、扳手）的大面朝 +x，
-- 所以 rx=90 頭朝上、rx=-90 頭朝下，大面都貼著包面朝外。dz 把同一類物品的典型長度置中在掛點上（頭朝上往下移、
-- 頭朝下往上移），dx 讓背面貼著包面。長度與方向用 scripts/blender/attach/preview.py sizes 量原版模型，
-- 再用 preview.py 離線算圖與 E2E attach-art-sp 實機截圖核對（2026-10-27）。
local POSE = {
    Hammer = { 90, 0, 0, 0.012, 0, -0.120 }, Wrench = { 90, 0, 0, 0.010, 0, -0.120 }, Walkie = { 90, 0, 0, 0.015, 0, -0.085 },
    Gear = { 90, 0, 0, 0.015, 0, -0.085 },
    Screwdriver = { -90, 0, 0, 0.010, 0, 0.100 }, Knife = { -90, 0, 0, 0.010, 0, 0.105 }, Cleaver = { -90, 0, 0, 0.012, 0, 0.110 },
    Saucepan = { -90, 0, 0, 0.060, 0, 0.100 }, Pan = { -90, 0, 0, 0.040, 0, 0.120 },
    -- 繩圈（Rope_Looped 平放：圈面在 xz、長邊沿 x、厚度沿 +y）立起來貼在包面，長邊直放才不會蓋到隔壁的槽
    Rope = { -90, 0, -90, 0.010, 0, 0 },
    Bottle = { 90, 0, 0, 0.030, 0, 0 }, Can = { 90, 0, 0, 0.030, 0, 0 }, Pills = { 90, 0, 0, 0.022, 0, 0 },
    -- 玩偶借地面模型：y 朝上、正面朝 +z、原點在底部中央（Spiffo 與 *_Ground），轉成 y→上、z→朝外，坐在包頂
    Plushie = { 90, 90, 0, 0, 0, 0 },
    -- 側邊束帶的長物品置中：傘柄露在包頂上、傘尖到包底下
    Umbrella = { -90, 0, 0, 0.025, 0, 0.240 }, Saw = { -90, 0, 0, 0.012, 0, 0.160 }, Tool = { 90, 0, 0, 0.020, 0, -0.180 },
    Flashlight = { 90, 0, 0, 0.020, 0, 0 }, Torch = { 90, 0, 0, 0.040, 0, 0 },
}
-- 不照上面慣例做的物品模型：在那個 model 腳本上加同名掛點當自身校正。
-- 掛上去時 parent 與 self 用同一個掛點名（ModelManager.java:601-607），變換是 骨頭·身體掛點·自身掛點·網格
-- （AnimatedModel.java:1455-1484；invertAttachmentSelfTransform 從來沒被設成 true，自身掛點照原樣乘）。
-- FIX[model 全名] = { 擺法, rx, ry, rz, ox, oy, oz }：只加在那個擺法的掛點上；位移在擺法轉過之後的座標裡（同上面的慣例座標），
-- 給原點不在握點或背面的模型補回去。方向用 preview.py axes 看各軸，再用 preview.py slot 核對。
local FIX = {
    -- *_Ground 玩偶正面朝 -z
    ["Base.PlushieBadger_Ground"] = { "Plushie", 0, 180, 0 }, ["Base.PlushieRabbit_Ground"] = { "Plushie", 0, 180, 0 },
    ["Base.PlushieFox_Ground"] = { "Plushie", 0, 180, 0 }, ["Base.PlushieSquirrel_Ground"] = { "Plushie", 0, 180, 0 },
    ["Base.PlushieBeaver_Ground"] = { "Plushie", 0, 180, 0 }, ["Base.PlushieMole_Ground"] = { "Plushie", 0, 180, 0 },
    ["Base.PlushieHedgehog_Ground"] = { "Plushie", 0, 180, 0 },
    ["Base.Pancho"] = { "Plushie", 0, -90, 0 },                       -- 正面朝 +x
    -- 原點在背面：往後推半個厚度，置中坐在包頂
    ["Base.Plushabug"] = { "Plushie", 90, 90, 0, 0, 0, -0.045 },      -- 平趴、頭朝 +x：改成背殼朝外、頭朝上，像攀在包上
    ["Base.Doll"] = { "Plushie", 90, 0, 0, 0, 0, -0.035 },            -- 仰躺、頭朝 -z
    ["Base.PlushieEyeOfChulhu_Ground"] = { "Plushie", 90, 0, 0, 0, 0, -0.070 },   -- 瞳孔朝 +y
    -- 平放在地上的鋸（長邊沿 z、原點在中間）：長邊轉到 +y、大面朝 +x，再往 +y 推半個長度對齊握點慣例
    ["Base.SawForgedWood"] = { "Saw", -90, 0, -90, 0, 0.137, 0 }, ["Base.SmallMetalworkingSaw"] = { "Saw", -90, 0, -90, 0, 0.104, 0 },
    ["Base.SheetRope"] = { "Rope", 0, 90, 0 },                        -- 布繩長邊沿 z，先轉到 x 再照繩圈立起來
}
MDB.ATTACH_ANCHOR, MDB.ATTACH_POSE, MDB.ATTACH_FIX = ANCHOR, POSE, FIX

-- ===== 旋轉：3×3 矩陣（列優先），JOML rotateXYZ 的 M = Rx·Ry·Rz =====
local RAD = math.pi / 180
local function euler(x, y, z)
    local cx, sx = math.cos(x * RAD), math.sin(x * RAD)
    local cy, sy = math.cos(y * RAD), math.sin(y * RAD)
    local cz, sz = math.cos(z * RAD), math.sin(z * RAD)
    return {
        { cy * cz, -cy * sz, sy },
        { cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
        { sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
    }
end
local function mul(a, b)
    local m = {}
    for i = 1, 3 do
        m[i] = {}
        for j = 1, 3 do m[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
    end
    return m
end
local function toEuler(m)
    local sy = math.max(-1, math.min(1, m[1][3]))
    if math.abs(sy) < 0.99999 then
        return math.atan2(-m[2][3], m[3][3]) / RAD, math.asin(sy) / RAD, math.atan2(-m[1][2], m[1][1]) / RAD
    end
    return math.atan2(m[3][2], m[2][2]) / RAD, math.asin(sy) / RAD, 0   -- 萬向鎖：z 併進 x
end
MDB.attachEuler, MDB.attachMul, MDB.attachToEuler = euler, mul, toEuler

-- 掛點最終的 offset 與 rotate：位置＝起點＋面旋轉·擺法位移；旋轉＝面旋轉·擺法旋轉
function MDB.attachTransform(anchor, pose)
    local face = euler(0, 0, anchor[4])
    local r = mul(face, euler(pose[1], pose[2], pose[3]))
    local d = { pose[4], pose[5], pose[6] }
    local off = {}
    for i = 1, 3 do off[i] = anchor[i] + face[i][1] * d[1] + face[i][2] * d[2] + face[i][3] * d[3] end
    local rx, ry, rz = toEuler(r)
    return off, { rx, ry, rz }
end

-- 找到同名掛點就只改值（Lua 重載時 model 腳本可能還是同一份），沒有才加
local function upsert(ms, id, bone, off, rot)
    local a = ms:getAttachmentById(id)
    if not a then
        a = ModelAttachment.new(id)
        ms:addAttachment(a)
    end
    if bone then a:setBone(bone) end
    a:getOffset():set(off[1], off[2], off[3])
    a:getRotate():set(rot[1], rot[2], rot[3])
end

function MDB.installAttachClient()
    local sm = getScriptManager()
    for sex, body in pairs({ M = "MaleBody", F = "FemaleBody" }) do
        local ms = sm:getModelScript(body)
        if ms then
            MDB.eachAttachPose(function(fam, slot, pose)
                local off, rot = MDB.attachTransform(ANCHOR[fam][sex][slot], POSE[pose])
                upsert(ms, MDB.attachModelId(fam, slot, pose), "Bip01_BackPack", off, rot)
            end)
        end
    end
    for model, fix in pairs(FIX) do
        local ms = sm:getModelScript(model)
        if ms then
            local off = { fix[5] or 0, fix[6] or 0, fix[7] or 0 }
            MDB.eachAttachPose(function(fam, slot, pose)
                if pose == fix[1] then upsert(ms, MDB.attachModelId(fam, slot, pose), nil, off, { fix[2], fix[3], fix[4] }) end
            end)
        end
    end
    for _, f in ipairs(MDB.ATTACH_FAMILIES) do
        for _, slot in ipairs(f.slots) do
            local attachments = {}
            for itemType, pose in pairs(MDB.ATTACH_ACCEPTS[slot]) do
                attachments[itemType] = MDB.attachLocation(f.name, slot, pose)
            end
            -- name 只在缺翻譯時顯示；欄位名稱走 IGUI_HotbarAttachment_<type>（ISHotbar.lua:138、:152）
            table.insert(ISHotbarAttachDefinition, { type = MDB.attachSlotType(f.name, slot), name = "Backpack",
                animset = "back", attachments = attachments })
        end
    end
end

-- 沒有欄位可掛時，原版把每個接受這個類型的定義各列一行（ISHotbar.lua:176-195）；四個家族同名的欄位會重複四次，這裡去掉重複的行。
-- 第一行前面帶著 <INDENT:20>，比對時去掉。
local doMenuFromInventory = ISHotbar.doMenuFromInventory
function ISHotbar.doMenuFromInventory(playerNum, item, context)
    doMenuFromInventory(playerNum, item, context)
    local opt = context:getOptionFromName(getText("ContextMenu_Attach"))
    local tip = opt and opt.notAvailable and opt.toolTip
    if not tip or not tip.description then return end
    local d, pos, seen, lines = tip.description, 1, {}, {}
    while true do
        local s, e = d:find(" <LINE> ", pos, true)
        local line = d:sub(pos, (s or 0) - 1)
        local key = line:gsub("^<INDENT:%d+> ", "")
        if line == "" or not seen[key] then
            seen[key] = true
            lines[#lines + 1] = line
        end
        if not s then break end
        pos = e + 1
    end
    tip.description = table.concat(lines, " <LINE> ")
end

MDB.installAttachClient()
